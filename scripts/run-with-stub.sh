#!/usr/bin/env bash
# Start oracle-stub, poll until ready, run CMD from solidity/, reap stub.
set -euo pipefail

MODE=${1:?mode required}
PORT=${2:?port required}
CMD=${3:?command required}

cleanup() {
  if [[ -n "${STUB_PID:-}" ]]; then
    kill "$STUB_PID" 2>/dev/null || true
    wait "$STUB_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

stack exec -- oracle-stub --mode "$MODE" --port "$PORT" &
STUB_PID=$!

ready=0
for _ in $(seq 1 30); do
  if curl --fail --silent "http://127.0.0.1:${PORT}" >/dev/null 2>&1 || \
     curl --fail --silent -X POST -H 'Content-Type: application/json' \
       --data '{"jsonrpc":"2.0","id":0,"method":"spec_probe","params":[]}' \
       "http://127.0.0.1:${PORT}" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.2
done

if [[ "$ready" -ne 1 ]]; then
  echo "ERROR: stub not ready on port ${PORT}" >&2
  exit 1
fi

(
  cd solidity
  export EVM_SPEC_BRIDGE_URL="http://127.0.0.1:${PORT}"
  bash -lc "$CMD"
)
RC=$?
exit "$RC"
