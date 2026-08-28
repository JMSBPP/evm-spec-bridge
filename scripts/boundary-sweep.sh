#!/usr/bin/env bash
# ROADMAP criterion 2: keccak256 inside EVM vs cast keccak outside.
set -euo pipefail

./scripts/foundry-pin.sh

cleanup() {
  if [[ -n "${STUB_PID:-}" ]]; then
    kill "$STUB_PID" 2>/dev/null || true
    wait "$STUB_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

stack exec -- oracle-stub --mode boundary --port 8899 &
STUB_PID=$!

ready=0
for _ in $(seq 1 30); do
  if curl --fail --silent -X POST -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","id":0,"method":"spec_boundary","params":[0]}' \
    http://127.0.0.1:8899 >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.2
done
[[ "$ready" -eq 1 ]] || { echo "stub not ready" >&2; exit 1; }

echo "idx | envelope_nibbles | body_bytes | cast_keccak"
for i in 0 1 2 3 4; do
  result=$(curl -s -X POST -H 'Content-Type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"spec_boundary\",\"params\":[$i]}" \
    http://127.0.0.1:8899 | python3 -c "import json,sys;print(json.load(sys.stdin)['result'])")
  nibbles=$(( ${#result} - 2 ))
  case $i in
    0) body_hex=$(cast abi-encode "f(uint256)" 0) ;;
    1) body_hex=$(cast abi-encode "f(uint256)" 18446744073709551616) ;;
    2) body_hex=$(cast abi-encode "f(int256)" -5) ;;
    3) body_hex=0x ;;
    4) body_hex=$(python3 -c "print('0x'+'cd'*32)") ;;
  esac
  kh=$(cast keccak "$body_hex")
  echo "$i | $nibbles | $((${#body_hex} / 2 - 1)) | $kh"
done

(
  cd solidity
  export EVM_SPEC_BRIDGE_URL=http://127.0.0.1:8899
  forge test --match-path test/BoundarySweep.t.sol -vvvv
)
echo "PASS: boundary sweep — cast keccak and forge agree"
