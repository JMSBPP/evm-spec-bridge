#!/usr/bin/env bash
# Start relayd + fake-hevm-echo, run forge hevm.call smoke, reap both.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOCK="${RELAY_SOCK:-/tmp/fh-relay-hevm-call.sock}"
export RELAY_SOCK="$SOCK"

cleanup() {
  if [[ -n "${ECHO_PID:-}" ]]; then
    kill "$ECHO_PID" 2>/dev/null || true
    wait "$ECHO_PID" 2>/dev/null || true
  fi
  if [[ -n "${RELAYD_PID:-}" ]]; then
    kill "$RELAYD_PID" 2>/dev/null || true
    wait "$RELAYD_PID" 2>/dev/null || true
  fi
  rm -f "$SOCK" "${SOCK}.ctl"
}
trap cleanup EXIT

cd "$ROOT"

# Ensure relay / relayd / fake-hevm-echo are on PATH for vm.ffi.
stack build evm-spec-bridge-relay:exe:relay evm-spec-bridge-relay:exe:relayd evm-spec-bridge-relay:exe:fake-hevm-echo --fast
BIN="$(stack path --local-install-root)/bin"
export PATH="$BIN:$PATH"

rm -f "$SOCK" "${SOCK}.ctl"
stack exec -- relayd --sock "$SOCK" &
RELAYD_PID=$!

# Wait for control sock
ready=0
for _ in $(seq 1 50); do
  if [[ -S "${SOCK}.ctl" ]]; then
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "$ready" -ne 1 ]]; then
  echo "ERROR: relayd control sock not ready at ${SOCK}.ctl" >&2
  exit 1
fi

stack exec -- fake-hevm-echo --sock "$SOCK" &
ECHO_PID=$!

# Brief settle so FakeHevm dials data plane
sleep 0.3

./scripts/foundry-pin.sh
(
  cd solidity
  FOUNDRY_PROFILE=hevm forge test --match-path test/HevmCall.t.sol -vv
)
