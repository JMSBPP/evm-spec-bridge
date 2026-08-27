#!/usr/bin/env bash
# CFMM-01 seam guard. Asserts: the six core components are satisfiable from the
# snapshot alone -- i.e. none of them depends on cfmm-vol-markets-spec.
#
# This is a PLANNING check, not a compile. `--dry-run` stops after Stack
# constructs the build plan, so a violation is caught before any module is
# compiled. That is why the guard is cheap enough to run first.
#
# TIMING (measured 2026-08-27): ~0.3s warm; ~119s on a COLD tree with no
# .stack-work. CI starts cold -- restore the cache before this runs, or the
# "fail fast" property does not hold.
set -euo pipefail
STACK=${STACK:-stack}
exec $STACK ${STACK_FLAGS:-} --stack-yaml stack-core.yaml build --dry-run
