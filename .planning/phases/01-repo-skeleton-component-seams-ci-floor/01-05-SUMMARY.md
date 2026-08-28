---
phase: 01-repo-skeleton-component-seams-ci-floor
plan: 01-05
status: complete
completed: 2026-08-27
requirements-completed: [DIST-04]
duration: not-instrumented
---

> **BACK-FILLED 2026-08-28**, reconstructed from git history and PROBE-NOTES. This is NOT a contemporaneous record — the plan was executed inline with the user and no summary was written at the time. Measurements quoted here are sourced from the phase notebook; nothing is reconstructed from memory.

# 01-05 Summary — tasty scaffold, hpack drift gate, and one shared command surface

**`components/protocol/test/Main.hs` runs an explicit `tasty` runner, `scripts/hpack-drift.sh`
byte-diffs the generated `.cabal` files, and a `justfile` holds the strings the human and the gate
are supposed to share.**

## Performance

- **Duration:** not-instrumented (executed inline; no timing was captured)
- **Started / Completed:** not recorded
- **Commits:** 1 (`3a142dc`)

## Task commits

1. **tasty scaffold, hpack drift gate, justfile** — `3a142dc` (feat)

## What was established

- An **explicit** `defaultMain` runner rather than `tasty-discover`, so later phases add
  `testGroup`s instead of wiring up a runner.
- `scripts/hpack-drift.sh` runs the generator and then `git diff --exit-code` over the committed
  `.cabal` files, so sources and generated artifacts cannot silently disagree. This is the same
  shape the generated Solidity gets in Phase 8 — established now so both are one habit.
- The `justfile` exists so the local command and the CI command are literally the same string.

This commit also carries `stack.yaml.lock` and
`components/cfmm-adapter/evm-spec-bridge-cfmm-adapter.cabal`, which 01-03's plan had named. The
lock file records the spec commit and a pantry-tree sha256, which is what makes `hashFiles` a
complete CI cache key in 01-07.

## Deviation recorded later, not here — and it is this plan's

The `justfile` written here was **never executed during Phase 1**. `just` was not installed on the
machine; the absence was found in 02-01 while verifying a different recipe. Nothing in the gate
invokes `just` (CI calls `scripts/*.sh` directly), so no gate was weakened and no false claim was
recorded — but `just seam` and `just drift` were asserted from the file's syntax, not from a run.
Both were subsequently executed and passed, on 2026-08-28, after `just 1.52.0` was installed.

A second consequence surfaced in Phase 2: `scripts/hpack-drift.sh` globs `*.cabal` **repo-wide**,
which is wider than "the seven committed component files" and is what made the throwaway spike's
generated `.cabal` visible to this gate.

## Files created / modified

- `components/protocol/test/Main.hs`, `components/protocol/package.yaml` and its `.cabal`
- `scripts/hpack-drift.sh`
- `justfile`
- `stack.yaml.lock`, `components/cfmm-adapter/evm-spec-bridge-cfmm-adapter.cabal`

## Requirements

- **DIST-04** — advanced: a real test suite exists for the gate to run. The gate itself is 01-07.
