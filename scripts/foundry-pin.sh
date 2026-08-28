#!/usr/bin/env bash
# DIST-06 Foundry pin assertion. Asserts: the forge on THIS box is the forge named in
# .github/foundry-version -- by commit SHA, not by tag.
#
# Two modes, because CI and the local box can honestly assert different things:
#
#   --check-format  (CI)     The pin file is sourceable, all three values are present, and
#                            FOUNDRY_COMMIT is 40 hex chars. Needs no forge and no network.
#   (default)       (local)  All of the above, PLUS `forge --version` must contain the pinned
#                            commit.
#
# Why the binary assertion is NOT run in CI: forge is deliberately not installed there. Installing
# forge purely to assert that it is the forge you just installed is CIRCULAR -- it can only fail
# if foundryup itself is broken, and it costs an unmeasured install on every run. Asserting only
# what you can actually see is the honest form.
#
# EXIT CODE BEFORE GREPS: `forge --version` output and its exit status are captured SEPARATELY. A
# forge that fails to run must not be reported as a version mismatch, and a grep over empty output
# must not be mistaken for either.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PIN_FILE=".github/foundry-version"

if [ ! -f "$PIN_FILE" ]; then
  echo "ERROR: pin file missing: $ROOT/$PIN_FILE" >&2
  echo "       This file IS the pin (DIST-06). Restore it from git; do not inline the values." >&2
  exit 1
fi

# shellcheck source=/dev/null
. ./.github/foundry-version

# Missing-value failures are deliberately distinct from a commit mismatch: the message names the
# variable, so "the pin file is broken" never reads as "this box has the wrong forge".
: "${FOUNDRY_VERSION:?ERROR: FOUNDRY_VERSION is unset or empty in $PIN_FILE}"
: "${FOUNDRY_COMMIT:?ERROR: FOUNDRY_COMMIT is unset or empty in $PIN_FILE}"
: "${FOUNDRYUP_INSTALLER_COMMIT:?ERROR: FOUNDRYUP_INSTALLER_COMMIT is unset or empty in $PIN_FILE}"

# A short SHA or a tag would make the grep below match far too much -- reject both here.
if ! printf '%s' "$FOUNDRY_COMMIT" | grep -qE '^[0-9a-f]{40}$'; then
  echo "ERROR: FOUNDRY_COMMIT is not a full 40-character lowercase hex SHA." >&2
  echo "       got:  $FOUNDRY_COMMIT" >&2
  echo "       file: $ROOT/$PIN_FILE" >&2
  echo "       A short SHA or a tag is not a pin: it would match more than one commit." >&2
  exit 1
fi

if [ "${1:-}" = "--check-format" ]; then
  echo "PASS (format): $PIN_FILE is sourceable; FOUNDRY_VERSION=$FOUNDRY_VERSION;"
  echo "               FOUNDRY_COMMIT=$FOUNDRY_COMMIT (40 hex);"
  echo "               FOUNDRYUP_INSTALLER_COMMIT=$FOUNDRYUP_INSTALLER_COMMIT present."
  echo "               Binary assertion NOT run in this mode -- forge is not installed in CI."
  exit 0
fi

if [ $# -gt 0 ]; then
  echo "ERROR: unknown argument: $1" >&2
  echo "usage: $0 [--check-format]" >&2
  exit 2
fi

# --- binary assertion (local only) ----------------------------------------------------------
forge_out=""
forge_status=0
forge_out="$(forge --version 2>&1)" || forge_status=$?

if [ "$forge_status" -ne 0 ]; then
  echo "ERROR: could not run \`forge --version\` (exit status $forge_status)." >&2
  echo "       This is NOT a version mismatch -- forge is absent or failed to start." >&2
  echo "       output: ${forge_out:-<none>}" >&2
  echo "       Expected toolchain: $FOUNDRY_VERSION ($FOUNDRY_COMMIT), per $ROOT/$PIN_FILE" >&2
  exit 1
fi

if ! printf '%s\n' "$forge_out" | grep -qF "$FOUNDRY_COMMIT"; then
  echo "ERROR: the forge on this box is NOT the pinned toolchain." >&2
  echo "       EXPECTED commit: $FOUNDRY_COMMIT" >&2
  echo "       EXPECTED version: $FOUNDRY_VERSION" >&2
  echo "       ACTUAL \`forge --version\`:" >&2
  printf '         %s\n' "$forge_out" >&2
  echo "       pin file: $ROOT/$PIN_FILE" >&2
  echo "       Fix by installing the pin, not by editing it:" >&2
  echo "         foundryup --install ${FOUNDRY_VERSION#v}" >&2
  echo "       Editing the pin changes what every measurement in this repo is scoped to, and" >&2
  echo "       must match cfmm-vol-markets' own pin (their CI-05)." >&2
  exit 1
fi

echo "PASS: forge matches the pin -- $FOUNDRY_VERSION at commit $FOUNDRY_COMMIT"
