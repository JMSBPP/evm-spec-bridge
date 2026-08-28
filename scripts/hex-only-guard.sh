#!/usr/bin/env bash
# PROTO-04 type-level guard. Proves a JSON number and a raw Hex0x construction
# both FAIL TO COMPILE, in two distinguishable ways.
#
# Three stages (same shape as scripts/seam-negative-test.sh):
#   CONTROL  -- legal snippet MUST compile (else the harness is broken)
#   NEGATIVE -- raw constructor MUST fail with an unexported-constructor diagnostic
#   CONTRAST -- numeric literal MUST fail with `Num Hex0x`, NOT the NEGATIVE diagnostic
set -euo pipefail
STACK=${STACK:-stack}
FLAGS=${STACK_FLAGS:-}
ROOT=$(git rev-parse --show-toplevel)
CF="${ROOT}/components/abi-codec/compile-fail"

fail(){ echo "FAIL($1): $2" >&2; exit 1; }

compile() {
  # $1 = snippet path; prints exit code; leaves compiler output in $OUT
  set +e
  OUT=$($STACK $FLAGS ghc -- -fno-code -Wall \
    -package evm-spec-bridge-abi-codec -package aeson -package bytestring \
    "$1" 2>&1)
  RC=$?
  set -e
  echo "$RC"
}

# Register the local package before stack ghc can see it.
$STACK $FLAGS build 'evm-spec-bridge-abi-codec'

# --- CONTROL -------------------------------------------------------------
RC=$(compile "${CF}/Control.hs")
[ "$RC" -eq 0 ] || fail control "legal snippet did not compile — the harness is broken, not the tree"

# --- NEGATIVE ------------------------------------------------------------
set +e
OUT=$($STACK $FLAGS ghc -- -fno-code -Wall \
  -package evm-spec-bridge-abi-codec -package aeson -package bytestring \
  "${CF}/RawConstructor.hs" 2>&1)
RC=$?
set -e
[ "$RC" -ne 0 ] || fail negative "raw Hex0x construction compiled — export list is leaking"
echo "$OUT" | grep -q "Illegal term-level use of the type constructor" \
  || fail negative "expected unexported-constructor diagnostic (Illegal term-level use...)"

# --- CONTRAST ------------------------------------------------------------
set +e
OUT=$($STACK $FLAGS ghc -- -fno-code -Wall \
  -package evm-spec-bridge-abi-codec -package aeson -package bytestring \
  "${CF}/NumberBody.hs" 2>&1)
RC=$?
set -e
[ "$RC" -ne 0 ] || fail contrast "numeric literal at Hex0x compiled — Num instance is leaking"
echo "$OUT" | grep -q 'Num Hex0x' \
  || fail contrast "expected 'Num Hex0x' diagnostic"
echo "$OUT" | grep -q "Illegal term-level use of the type constructor" \
  && fail contrast "CONTRAST failure is indistinguishable from NEGATIVE — both name unexported Hex0x"

echo "PASS: hex-only guard fired in two distinguishable ways"
