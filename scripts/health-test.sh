#!/usr/bin/env bash
# Smoke test: spec_health returns a 0x-prefixed hex result envelope.
set -euo pipefail

PORT=${1:-8899}

cleanup() {
  if [[ -n "${STUB_PID:-}" ]]; then
    kill "$STUB_PID" 2>/dev/null || true
    wait "$STUB_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

stack exec -- oracle-stub --mode success --port "$PORT" &
STUB_PID=$!

ready=0
for _ in $(seq 1 30); do
  if curl --fail --silent -X POST -H 'Content-Type: application/json' \
       --data '{"jsonrpc":"2.0","id":0,"method":"spec_health","params":[]}' \
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

resp=$(curl --fail --silent -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":0,"method":"spec_health","params":[]}' \
  "http://127.0.0.1:${PORT}")

echo "$resp" | grep -q '"result"' || { echo "missing result: $resp" >&2; exit 1; }
echo "$resp" | grep -q '0x' || { echo "missing 0x hex: $resp" >&2; exit 1; }
echo "spec_health ok"
