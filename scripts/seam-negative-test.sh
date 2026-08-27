#!/usr/bin/env bash
# Proves the seam guard ACTUALLY FIRES. A guard nobody has seen fail is a guard
# being trusted, not verified.
#
# Three stages, because "the build broke" is not the same as "the guard fired":
#   CONTROL  -- clean tree must RESOLVE      (else the guard is broken, not the tree)
#   NEGATIVE -- injected edge must FAIL with S-4804 naming the offender
#   CONTRAST -- the same package IS resolvable under the FULL stack.yaml
#               (proves the failure is about the SEAM, not a bad package name)
#
# Runs in a scratch copy. Never mutates the working tree -- a test of the build
# that leaves the build broken is worse than no test.
set -euo pipefail
STACK=${STACK:-stack}
FLAGS=${STACK_FLAGS:-}
VICTIM=${VICTIM:-components/protocol/package.yaml}
SPEC=cfmm-vol-markets-spec

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
cp -r components stack.yaml stack-core.yaml "$SCRATCH/"
cd "$SCRATCH"

fail(){ echo "FAIL($1): $2" >&2; exit 1; }

# --- CONTROL -------------------------------------------------------------
$STACK $FLAGS --stack-yaml stack-core.yaml build --dry-run >/dev/null 2>&1 \
  || fail control "clean tree does not resolve under stack-core.yaml -- the guard is broken, or the tree is"

# --- inject --------------------------------------------------------------
sed -i "s/^- base >= 4.7 && < 5$/- base >= 4.7 \&\& < 5\n- $SPEC/" "$VICTIM"
grep -q "$SPEC" "$VICTIM" \
  || fail inject "injection did not take -- NEGATIVE would pass for the wrong reason"

# --- NEGATIVE ------------------------------------------------------------
set +e
OUT=$($STACK $FLAGS --stack-yaml stack-core.yaml build --dry-run 2>&1); RC=$?
set -e
[ "$RC" -ne 0 ] || fail negative "guard did NOT fire on an injected spec dependency"
grep -q 'S-4804'                 <<<"$OUT" || fail negative "no S-4804 in output"
grep -q "$SPEC"                  <<<"$OUT" || fail negative "output does not name the offending dependency"
grep -q 'stack-core.yaml'        <<<"$OUT" || fail negative "output does not name stack-core.yaml"

# --- CONTRAST ------------------------------------------------------------
$STACK $FLAGS --stack-yaml stack.yaml build --dry-run >/dev/null 2>&1 \
  || fail contrast "the SAME tree fails under the full config too -- the failure is not about the seam"

echo "PASS: control resolved, guard fired with S-4804 naming the offender, contrast confirms it is the seam"
