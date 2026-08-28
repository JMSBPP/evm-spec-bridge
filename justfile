# The strings CI runs are the strings you run. If these diverge, the gate stops
# predicting local behaviour and a green local build means nothing.
#
# STACK_FLAGS is empty locally; CI sets it once after making system-GHC global.

default: seam build test drift

# CFMM-01 seam guard. Cheap ONLY when .stack-work is warm (~0.3s); a cold tree
# costs ~119s. CI must restore its cache before this runs.
seam:
    ./scripts/seam-guard.sh

# Proves the guard actually fires. Runs in a scratch copy; never mutates the tree.
seam-negative:
    ./scripts/seam-negative-test.sh

build:
    stack build --system-ghc --no-install-ghc --test --no-run-tests --pedantic

test:
    stack build --system-ghc --no-install-ghc --test --pedantic

# Committed .cabal files must match package.yaml.
drift:
    ./scripts/hpack-drift.sh

# DIST-06. The full local assertion: the forge on THIS box is the pinned forge, by commit SHA.
# CI runs the SAME script with --check-format (see .github/workflows/ci.yml) -- one script, two
# callers, so the two sides cannot drift apart.
foundry-pin:
    ./scripts/foundry-pin.sh

# Local mirror of the CI `image` job (01-06 / DIST-04). The tag is a fixed local
# name -- CI computes a lowercase, slash-free ref from github.repository, which is
# not reproducible off a runner. Same Dockerfile, same context, same smoke command.
image:
    docker build -f docker/Dockerfile -t evm-spec-bridge:local .

# A Dockerfile that builds but produces a binary that cannot start is a false green.
# CI runs this exact command against the loaded image; so do we.
image-run:
    docker run --rm evm-spec-bridge:local --version

# THROWAWAY. `spike/` is a self-contained Stack project -- NOT a package in the root
# stack.yaml -- plus a self-contained forge project under spike/forge. BOTH recipes
# below (`spike-server` and `spike-test`) are deleted in plan 02-05 along with
# `rm -rf spike/`. Nothing outside spike/ may depend on either.
#
# Server-start and test-run stay SEPARATE recipes: a combined one hides which half
# failed, and 02-03 specifically needs to observe the Foundry test go red when the
# server is absent.
spike-server PORT="8547":
    stack --stack-yaml spike/stack.yaml run stub-server -- {{PORT}}

# The pin assertion runs FIRST and its failure aborts the recipe: a measurement taken
# on a drifted forge is not a measurement of anything.
#
# Note on verbosity: -vvv prints traces for FAILING tests only. To read the raw
# returndata of a PASSING run, use `cd spike/forge && forge test -vvvv`.
spike-test:
    ./scripts/foundry-pin.sh
    cd spike/forge && forge test -vvv

# THROWAWAY. The 02-04 Content-Type matrix, made re-runnable. Deleted in plan 02-05
# together with `spike-server`, `spike-test` and `rm -rf spike/`.
#
# This probe has NO expected outcome. "alloy enforces a response Content-Type" and
# "it does not" are BOTH valid results, so a non-zero `forge test` in any row is DATA
# and the loop RECORDS it and CONTINUES -- aborting on the first red row would throw
# away the two rows that answer the other two questions.
#
# What DOES abort: a failed pin assertion, a failed build, or a stub that never binds.
# Those are broken instruments, not measurements. The recipe's own exit status is 0
# whenever all three rows RAN; the per-row exit statuses printed below are the result.
spike-matrix PORT="8547":
    #!/usr/bin/env bash
    # No `set -e`: every command's status is captured explicitly, because a red row must
    # not terminate the run. `set -u` still catches typo'd variables.
    set -uo pipefail

    echo "=== 02-04 Content-Type matrix: modes json, text, none on port {{PORT}} ==="

    # The pin FIRST. A measurement taken on a drifted forge is not a measurement.
    ./scripts/foundry-pin.sh
    pin_status=$?
    if [ "$pin_status" -ne 0 ]; then
      echo "ABORT: foundry pin assertion failed (exit $pin_status). No row was measured."
      exit "$pin_status"
    fi

    stack --stack-yaml spike/stack.yaml build
    build_status=$?
    if [ "$build_status" -ne 0 ]; then
      echo "ABORT: stub-server build failed (exit $build_status). No row was measured."
      exit "$build_status"
    fi

    # Run the binary DIRECTLY rather than via `stack run`, so $! is the server's own PID
    # and `kill` actually stops the listener instead of stack's wrapper.
    BIN="$(stack --stack-yaml spike/stack.yaml path --local-install-root)/bin/stub-server"
    if [ ! -x "$BIN" ]; then
      echo "ABORT: stub binary not executable at $BIN"
      exit 1
    fi

    stub_pid=""
    cleanup() { if [ -n "$stub_pid" ]; then kill "$stub_pid" 2>/dev/null; fi; }
    trap cleanup EXIT INT TERM

    passed=""
    failed=""

    for mode in json text none; do
      echo ""
      echo "================================================================"
      echo "== MODE: $mode"
      echo "================================================================"

      "$BIN" {{PORT}} "$mode" &
      stub_pid=$!

      up=0
      for _ in $(seq 1 100); do
        if curl -sS -o /dev/null -X POST "http://127.0.0.1:{{PORT}}" -d '{}' 2>/dev/null; then
          up=1; break
        fi
        sleep 0.1
      done
      if [ "$up" -ne 1 ]; then
        echo "ABORT: stub did not bind 127.0.0.1:{{PORT}} within 10s in mode $mode."
        exit 1
      fi

      echo "-- response headers on the wire (curl -i), mode $mode:"
      curl -sS -i -X POST "http://127.0.0.1:{{PORT}}" \
        -H 'content-type: application/json' \
        -d '{"jsonrpc":"2.0","id":7,"method":"spec_health","params":[]}' \
        | sed -n '1,/^\r\{0,1\}$/p' | sed 's/^/     /'

      echo "-- forge test, mode $mode:"
      ( cd spike/forge && forge test -vvv )
      forge_status=$?
      echo "-- MODE $mode: forge test EXIT STATUS = $forge_status"
      if [ "$forge_status" -eq 0 ]; then
        passed="$passed $mode"
      else
        failed="$failed $mode"
      fi

      kill "$stub_pid" 2>/dev/null
      wait "$stub_pid" 2>/dev/null
      stub_pid=""
      echo "-- MODE $mode: stub stopped"
    done

    echo ""
    echo "================================================================"
    echo "== SUMMARY (02-04 Content-Type matrix)"
    echo "================================================================"
    echo "   forge test PASSED (exit 0)      in mode(s):${passed:- <none>}"
    echo "   forge test FAILED (exit non-0)  in mode(s):${failed:- <none>}"
    echo "   All three rows RAN, so this recipe exits 0. A red row is DATA, not a"
    echo "   recipe failure -- read the per-mode EXIT STATUS lines above."
