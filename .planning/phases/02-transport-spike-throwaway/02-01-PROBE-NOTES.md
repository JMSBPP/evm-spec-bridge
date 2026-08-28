# Phase 2 — Probe Notes

Shared notebook for Phase 2. Values measured live during inline execution, recorded here so
later plans read them back rather than re-deriving or guessing.

**Staging rule:** every commit task in this phase must `git add` this file.

---

## Toolchain ground truth (02-01-T1)

Measured 2026-08-28 on this box, before any file in this plan was written.

### `forge --version`

| Field | Value |
|-------|-------|
| Version | `forge Version: 1.5.1-stable` |
| Commit SHA | `b0a9dd9ceda36f63e2326ce530c10e6916f4b8a2` |
| Build Timestamp | `2025-12-22T11:39:01.425730780Z` |
| Build Profile | `maxperf` |

The Commit SHA is byte-identical to the commit `cfmm-vol-markets` pins in its own
`.github/foundry-version` (their requirement CI-05). This box and the consumer's runner are on
the same binary.

### `forge config --json`

- **111 keys total.**
- The only version-bearing key is `evm_version`, whose value is `prague`. That is the **EVM
  hardfork the compiler targets**, NOT the forge binary.
- Filtering the key set for names containing `forge`, `foundry`, `toolchain` or `binary` returns
  an **EMPTY list**.

### Conclusion — why the pin cannot live in `foundry.toml`

`foundry.toml` has no key of any kind that pins the toolchain. The reason is structural, not an
oversight in the key set: **forge reads `foundry.toml` after it is already running**, so the file
cannot constrain the thing reading it. By the time the config is parsed, the binary has already
been chosen.

Consequence, and the shape of the rest of this plan: the pin must live somewhere that can
**assert** — i.e. a script that can exit non-zero. A value in a config file is something you can
read; `forge --version | grep -qF "$FOUNDRY_COMMIT" || exit 1` is a proposition that goes red.
That is what `scripts/foundry-pin.sh` (02-01-T3) is.

---

## Script sanity check during 02-01-T3 — NOT the T4 negative test

**This does NOT satisfy 02-01-T4.** T4 is a blocking human-verify checkpoint that must be run on
the REPO tree with the user, with restoration proved by `git diff --exit-code`. What follows was
run in a throwaway `/tmp` copy of `scripts/` + `.github/foundry-version` during T3, purely to
avoid committing an assertion that cannot fail. The repo tree was never mutated.

All four failure modes fire, and each fires DIFFERENTLY:

| Perturbation (scratch copy) | Exit | Message class |
|---|---|---|
| last char of `FOUNDRY_COMMIT` changed to `…a3` | 1 | "the forge on this box is NOT the pinned toolchain", quotes EXPECTED commit and full ACTUAL `forge --version` |
| `FOUNDRY_VERSION=` line deleted | 1 | `FOUNDRY_VERSION: ERROR: FOUNDRY_VERSION is unset or empty in .github/foundry-version` — a missing-variable error, not a mismatch |
| `forge` removed from `PATH` | 1 | "could not run \`forge --version\` (exit status 127) … This is NOT a version mismatch" |
| `FOUNDRY_COMMIT` shortened to `b0a9dd9` (`--check-format`) | 1 | "not a full 40-character lowercase hex SHA" |

The third row is the one the two-variable capture buys: a `forge` that cannot start reports as
absent, not as the wrong version.

---

## Wiring (02-01-T5)

`justfile` recipe `foundry-pin` -> `./scripts/foundry-pin.sh` (full local assertion, no flag).
`.github/workflows/ci.yml` seam job -> `./scripts/foundry-pin.sh --check-format`, placed as the
FIRST runnable step (line 42, immediately after `actions/checkout@v5` at line 29), well before the
cache restore at line 57. One script, two callers, identical path.

`grep -ci 'foundryup\|foundry-toolchain' .github/workflows/ci.yml` -> `0`. No Foundry install step
was added to CI, by design.

### UNVERIFIED on this box: `just foundry-pin`

`just` is **not installed** on this machine — `command -v just` is empty and it is absent from
`/usr/bin`, `~/.cargo/bin`, `~/.local/bin` and the nix profile; `pacman -Q just` reports the
package is not installed. So the T5 acceptance criterion "`just foundry-pin` exits 0" is
**unverified here**, not verified-and-passing. What IS verified is that the recipe body invokes
the identical string CI would, and that `./scripts/foundry-pin.sh` itself exits 0 (see T3). This
gap applies equally to the Phase 1 recipes (`just seam`, `just drift`, …) — CI never invokes
`just`, it calls the scripts directly, so nothing in the gate depends on it.

---

## 02-01-T4 — the pin assertion was made to FIRE, on the repo tree

Run inline with the user. This supersedes the `/tmp` scratch sanity check recorded earlier, which
explicitly did NOT satisfy T4.

| Stage | Tree state | exit | Message class |
|---|---|---|---|
| CONTROL | clean | **0** | `PASS: forge matches the pin -- v1.5.1 at commit b0a9dd9…` |
| NEGATIVE | last char of `FOUNDRY_COMMIT` changed to `…a3` | **1** | version mismatch |
| CONTRAST | `FOUNDRY_VERSION` line deleted | **1** | **missing variable — a different failure** |
| CONTRAST (`--check-format`) | same | **1** | same missing-variable error, so CI catches it too |
| RESTORE | `git checkout` | — | `git diff --exit-code = 0` (byte-identical) |
| post-restore | clean | **0** | PASS |

### Why CONTRAST is the stage that matters

NEGATIVE alone cannot distinguish "the guard fired for the reason we think" from "the guard exits 1
at anything". The two failure messages are unmistakably different — a commit mismatch that prints
EXPECTED vs ACTUAL, versus a `: "${VAR:?}"` unset-variable error naming the variable. Same shape as
01-04's seam negative test, where CONTRAST separated "the guard fired" from "the package name was
bad".

### The NEGATIVE message, verbatim

```
ERROR: the forge on this box is NOT the pinned toolchain.
       EXPECTED commit: b0a9dd9ceda36f63e2326ce530c10e6916f4b8a3
       ACTUAL `forge --version`:
         forge Version: 1.5.1-stable
         Commit SHA: b0a9dd9ceda36f63e2326ce530c10e6916f4b8a2
       Fix by installing the pin, not by editing it:
         foundryup --install 1.5.1
       Editing the pin changes what every measurement in this repo is scoped to, and
       must match cfmm-vol-markets' own pin (their CI-05).
```

The remediation advice matters: the tempting fix for a red pin is to edit the pin. That silently
re-scopes every measurement in the repo. The message says so at the moment someone is about to.

---

## Finding: `just` is NOT installed on this box — and Phase 1 never noticed

Discovered while verifying 02-01-T5.

```
$ command -v just
(absent)  — not in /usr/bin, ~/.cargo/bin, ~/.local/bin, or the nix profile; `pacman -Q just` reports not installed
```

**Consequences, stated honestly:**

1. **T5's criterion "`just foundry-pin` exits 0" is UNVERIFIED**, not satisfied. What IS verified:
   the recipe body is the identical string CI runs modulo the flag, and `./scripts/foundry-pin.sh`
   exits 0 directly.
2. **CI does not depend on `just`.** Its only two occurrences in `ci.yml` are prose in comments;
   every gate calls `scripts/*.sh` directly. Verified by reading both matches.
3. **Phase 1 carried `just`-based acceptance criteria that could never run.** `01-06-PLAN.md:480`
   has `<automated>… && just --list | grep -q 'image-run'</automated>` and `:485` requires
   "`just --list` lists `image` and `image-run`". The current `justfile` contains
   `default, seam, seam-negative, build, test, drift, foundry-pin` — **there is no `image` or
   `image-run` recipe.** That criterion was neither met nor flagged.
4. No FALSE claim was recorded: `01-SUMMARY.md` and `01-01-PROBE-NOTES.md` make no assertion that
   any `just` recipe was run. The gap is an unverified criterion, not a fabricated result.

**This is instrument failure #10, and it is ours.** The pattern is the familiar one: a check that
could not execute at all, in a spot nobody executed it. Distinct from the earlier nine only in that
the instrument was *absent* rather than *mis-scoped*.

**Not fixed here.** Adding the missing `image`/`image-run` recipes and installing `just` is Phase 1
gap-closure, deliberately not smuggled into Phase 2. Recorded in STATE.md blockers.

---

## 02-01-T6 — CI green, and the pin costs nothing

Run `33171542201` on `JMSBPP/evm-spec-bridge@develop`, commit `aed92a1`. **All three jobs success.**

| Job | Conclusion | Duration | Phase 1 baseline |
|---|---|---|---|
| seam | success | **145 s** | 125 s |
| build | success | **427 s** | 440 s |
| image | success | **56 s** | — |

### Step-level, seam job — the +20 s is NOT the pin

| # | Step | Duration |
|---|---|---|
| 2 | `actions/checkout@v5` | 2 s |
| **3** | **Foundry pin well-formedness (DIST-06)** | **0 s** |
| 4 | `haskell-actions/setup@v2` | **117 s** |
| 6 | Restore Stack cache BEFORE the guard | 11 s |
| 7 | Seam guard (CFMM-01) | 1 s |
| 8 | Prove the guard fires | 2 s |

The pin step is **0 s**, as predicted — it reads one small file and does no I/O beyond that. The
seam job's rise from the 125 s Phase 1 baseline is `haskell-actions/setup` taking 117 s this run
against 106 s previously: **runner variance in a step both jobs already paid for**, not a cost the
pin introduced. Recorded this way rather than as "seam got slower", because the job-level number
alone would have supported that wrong conclusion.

The pin step runs 3rd, immediately after checkout — so a malformed pin fails before the 117 s
toolchain setup is spent.

---

## Instrument failure #11 — `gh run list` returned `[]` for the wrong repo

While verifying T6, `gh run list --branch develop` returned an empty array. That reads as
"CI did not run".

It was not. `gh repo view` resolves this checkout to **`d2p-finance/evm-spec-bridge`** — the
CANONICAL repo — while the push went to `origin`, the **fork** `JMSBPP/evm-spec-bridge`. Canonical
has no Actions runs because, by DIST-03's design, nothing is ever pushed to it directly.

```
$ gh repo view --json nameWithOwner -q .nameWithOwner
d2p-finance/evm-spec-bridge          <- NOT where we pushed

$ git remote -v
origin    https://github.com/JMSBPP/evm-spec-bridge.git      (push)
upstream  https://github.com/d2p-finance/evm-spec-bridge.git (push)
```

`gh run list --repo JMSBPP/evm-spec-bridge` immediately showed the run.

**This is the same shape as Phase 1's `gh api` 404**, which meant a missing OAuth scope and read as
a missing package. Both are cases where a tool answered a DIFFERENT question than the one asked and
returned something indistinguishable from a substantive negative. There an authorization artefact
wore the costume of an existence claim; here a repo-resolution artefact wore the costume of
"no CI ran".

**Rule, carried forward:** in this repo every `gh` invocation must pass `--repo
JMSBPP/evm-spec-bridge` explicitly. The fork/canonical split that DIST-03 exists to enforce is
exactly what makes bare `gh` commands ambiguous here.

---

## 02-01 — plan complete

DIST-06's mechanism exists and has been observed to fail. Surviving artifacts:
`.github/foundry-version`, `scripts/foundry-pin.sh`, one `justfile` recipe, one CI step.
Everything else in Phase 2 is throwaway.

---

## 02-02-T2 — the spike is a self-contained Stack project

`spike/` has its own `stack.yaml` and is NOT listed in the root `stack.yaml`. Consequence: CI's
`build` job never compiles warp/wai or their transitive closure, and deletion in 02-05 is
`rm -rf spike/` plus one `justfile` recipe rather than a five-step cleanup (remove packages entry,
regenerate .cabal, re-run the drift gate, re-run the seam guard). Code that is annoying to delete
does not get deleted -- it gets adopted.

The snapshot block is byte-identical to the root's, confirmed mechanically:

```
$ diff <(sed -n '/^snapshot:/,/^  size:/p' stack.yaml) \
       <(sed -n '/^snapshot:/,/^  size:/p' spike/stack.yaml)
$ echo $?
0
```

`extra-deps: []` -- warp-3.4.9, wai-3.2.5, http-types-0.12.6, aeson, bytestring and text are all
present in LTS 24.55, so the spike pins nothing of its own.

`spike/` is deliberately NOT in `.gitignore`; the files are committed so the 02-05 deletion shows up
as a visible diff:

```
$ git check-ignore spike/README.md; echo "exit=$?"
exit=1                                   <- not ignored

$ git diff --exit-code stack.yaml stack-core.yaml .github/workflows/ci.yml; echo "exit=$?"
exit=0                                   <- root project untouched
```

---

## 02-02-T3 — the stub: hardcoded payload, echoed id, loopback bind, required port

`spike/stub-server/app/Main.hs`, 56 lines. Four properties, each with a reason:

**1. The payload is EVEN-nibble.** It was generated mechanically rather than typed, precisely
because a hand-typed run of zeros is where an odd nibble count comes from:

```
$ printf '%064x' 42
000000000000000000000000000000000000000000000000000000000000002a
$ echo -n "$(printf '%064x' 42)" | wc -c
64
```

64 hex characters after `0x` -- even, all `[0-9a-f]`, integer value 42, one 32-byte EVM word. An
odd count is not valid hex and falls into a different `json_value_to_token` coercion branch
(PITFALLS.md:82), which would invalidate the whole spike without necessarily turning the test red
in an obvious way. NOTE: the payload literal written out in the 02-02 plan's `<action>` block is
60 zeros + `2a` = 62 characters, NOT 64. The plan's own instruction to "count it, do not assume"
caught its own example. The committed value is the 64-character one.

**2. Bound to 127.0.0.1 and nothing else.**

```
$ grep -c '0\.0\.0\.0' spike/stub-server/app/Main.hs
0
$ ss -ltn | grep 8547
LISTEN 0      4096       127.0.0.1:8547       0.0.0.0:*
```

The `0.0.0.0:*` on the right is the PEER-address column (any remote may connect); the local bind
address is `127.0.0.1:8547`, which is what alloy's `guess_local_url` requires in order to apply
`no_proxy`. This is the check curl cannot make: a wrong bind still answers curl on localhost
perfectly while also being reachable from the network.

**3. Port is required; there is no default.**

```
$ stack --stack-yaml spike/stack.yaml run stub-server
usage: stub-server PORT   (PORT is required; there is no default)
exit=1
```

**4. The id is echoed.** alloy correlates a response to its request by id.

```
$ curl -sS -i -X POST http://127.0.0.1:8547 -H 'content-type: application/json' \
    -d '{"jsonrpc":"2.0","id":7,"method":"spec_health","params":[]}'
HTTP/1.1 200 OK
Transfer-Encoding: chunked
Date: Fri, 28 Aug 2026 13:28:04 GMT
Server: Warp/3.4.9
Content-Type: application/json

{"jsonrpc":"2.0","id":7,"result":"0x000000000000000000000000000000000000000000000000000000000000002a"}
```

`"id":7`, not 1 -- so the echo is real and not the fallback accidentally agreeing. The fallback was
exercised separately: a body with no `"id"`, and a body that is not JSON at all, both return
`"id":1`.

Request log on the stub's stdout (this is what makes a red `forge test` in 02-03 diagnosable):

```
[stub] listening on 127.0.0.1:8547
[stub] path="/" body-bytes=59 echoed-id=7
```

After the process was stopped, `ss -ltn | grep 8547` returned nothing (exit 1) -- port released.

**Build:** `stack --stack-yaml spike/stack.yaml build` exits 0. `-Wall` produced NO warnings for
`Main` -- the compile went `[1 of 2] Compiling Main` straight to `[2 of 2] Compiling
Paths_spike_stub_server` with nothing between. The warnings visible in the build output are all
`-Wdeprecations` from inside the `warp-3.4.9` dependency's own modules, not from our source.

### Finding: the spike is NOT entirely invisible to the root gates

`scripts/hpack-drift.sh` ends with `git status --porcelain -- '*.cabal'`, and that glob is
REPO-WIDE. The freshly generated `spike/stub-server/spike-stub-server.cabal` therefore turned
`just drift` red as an untracked generated artifact:

```
$ ./scripts/hpack-drift.sh
ERROR: untracked or unstaged .cabal files -- generated artifacts must be committed
?? spike/stub-server/spike-stub-server.cabal
drift exit=1
```

Resolved by committing it, which is the repo's stated policy for generated .cabal files anyway. It
lives inside `spike/`, so 02-05's deletion is still `rm -rf spike/` -- but the claim "the spike is
invisible to the root project" is now precisely: invisible to `stack build`, `stack-core.yaml` and
`ci.yml`, NOT invisible to the repo-wide `*.cabal` glob in the drift gate.
