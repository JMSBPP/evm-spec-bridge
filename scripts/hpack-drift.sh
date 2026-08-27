#!/usr/bin/env bash
# The generated .cabal files are COMMITTED so consumers can build without hpack.
# A committed generated artifact goes stale silently -- this makes that a hard red.
#
# Two checks, because `git diff` only sees TRACKED files: a NEW component whose
# .cabal is never staged would otherwise pass this gate forever.
set -euo pipefail
STACK=${STACK:-stack}
$STACK ${STACK_FLAGS:-} build --dry-run >/dev/null 2>&1 || true   # regenerates .cabal via hpack
git diff --exit-code -- '**/*.cabal'
if [ -n "$(git status --porcelain -- '*.cabal')" ]; then
  echo "ERROR: untracked or unstaged .cabal files -- generated artifacts must be committed" >&2
  git status --porcelain -- '*.cabal' >&2
  exit 1
fi
echo "PASS: committed .cabal files match package.yaml"
