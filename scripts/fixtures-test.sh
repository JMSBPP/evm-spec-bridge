#!/usr/bin/env bash
set -euo pipefail

./scripts/foundry-pin.sh
./scripts/run-with-stub.sh success 8899 \
  "forge test --match-path test/SpecFixtures.t.sol -vvvv"
