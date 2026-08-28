#!/usr/bin/env bash
# ROADMAP criterion 3: wedged oracle must go red with test count > 0.
# Meta-level JSON reason reading here — NOT part of Discrimination.t.sol contract path.
set -euo pipefail

./scripts/foundry-pin.sh

count_tests() {
  python3 - <<'PY'
import json,sys
d=json.load(open("/tmp/ft.json"))
print(sum(len(s.get("test_results",[])) for s in d.values()))
PY
}

run_forge() {
  (
    cd solidity
    export EVM_SPEC_BRIDGE_URL=http://127.0.0.1:8899
    timeout 120 forge test --match-path test/WedgeRed.t.sol --json > /tmp/ft.json
  )
  echo "$?"
}

echo "CONTROL: success stub"
./scripts/run-with-stub.sh success 8899 "timeout 60 forge test --match-path test/WedgeRed.t.sol --json > /tmp/ft.json" || true
RC=$?
if [[ "$RC" -ne 0 ]]; then
  echo "CONTROL failed rc=$RC" >&2
  exit 1
fi
COUNT=$(count_tests)
[[ "$COUNT" -gt 0 ]] || { echo "CONTROL: zero tests" >&2; exit 1; }
echo "CONTROL ok count=$COUNT"

echo "NEGATIVE: wedge stub (~45s)"
START=$(date +%s)
( stack exec -- oracle-stub --mode wedge --port 8899 & echo $! > /tmp/stub.pid; sleep 2
  RC=$(run_forge)
  kill "$(cat /tmp/stub.pid)" 2>/dev/null || true
  echo "$RC"
) | tail -1 > /tmp/neg.rc
RC=$(cat /tmp/neg.rc)
ELAPSED=$(( $(date +%s) - START ))
COUNT=$(count_tests)
if [[ "$RC" -eq 0 || "$COUNT" -le 0 ]]; then
  echo "NEGATIVE failed rc=$RC count=$COUNT elapsed=${ELAPSED}s" >&2
  exit 1
fi
echo "NEGATIVE ok rc=$RC count=$COUNT elapsed=${ELAPSED}s"

echo "CONTRAST: no stub"
RC=$(run_forge)
COUNT=$(count_tests)
if [[ "$RC" -eq 0 || "$COUNT" -le 0 ]]; then
  echo "CONTRAST failed rc=$RC count=$COUNT" >&2
  exit 1
fi
echo "CONTRAST ok rc=$RC count=$COUNT"

echo "PASS: wedged oracle is red, in two distinguishable ways"
