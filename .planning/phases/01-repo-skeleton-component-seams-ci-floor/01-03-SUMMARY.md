---
phase: 01-repo-skeleton-component-seams-ci-floor
plan: 01-03
status: complete
completed: 2026-08-27
requirements-completed: [CFMM-01]
duration: not-instrumented
---

> **BACK-FILLED 2026-08-28**, reconstructed from git history and PROBE-NOTES. This is NOT a contemporaneous record — the plan was executed inline with the user and no summary was written at the time. Measurements quoted here are sourced from the phase notebook; nothing is reconstructed from memory.

# 01-03 Summary — Two Stack configs; the seam becomes a proposition the build system decides

**`stack.yaml` is the real build; `stack-core.yaml` is the guard, and its *absence* of the spec
extra-dep is the entire mechanism.**

## Performance

- **Duration:** not-instrumented (executed inline; no timing was captured)
- **Started / Completed:** not recorded
- **Commits:** 1 (`aa6057b`)

## Task commits

1. **Stack configs + spec-less seam guard; measured warm vs cold** — `aa6057b` (feat)

## What was established

Stack constructs a build plan from `snapshot ∪ extra-deps ∪ packages`. A package naming a
dependency outside that set fails at plan construction — structurally, before compilation, with no
opt-out. `stack-core.yaml` lists the six core packages with `extra-deps: []`; `stack.yaml` adds
`components/cfmm-adapter` and the pinned spec git extra-dep.

## Measured — both directions, `stack --stack-yaml stack-core.yaml build --dry-run`

| Case | Tree state | exit | time |
|---|---|---|---|
| positive control (clean) | warm | 0 | **303–326 ms** |
| negative (protocol gains the spec) | warm | **1** | **302 ms** |
| negative (protocol gains the spec) | **cold scratch copy** | 1 | **118 818 ms** |

The guard names all three things needed to act on it — the offending package, the unresolvable
dependency, and the config file — under `[S-4804]`.

### The cold number is a finding, not noise

RESEARCH.md measured 0.34 s and 01-07's fail-fast rationale rested on it. That is a **warm**
figure. Every CI run starts from a fresh checkout, where the same command takes 119 s — **350x**.

**Action handed to 01-07:** the cache restore must run BEFORE the seam job, and the rationale must
state warm-vs-cold rather than quoting 0.34 s unqualified. This is the same shape as the phase's
other corrections: a real measurement, taken under conditions that differ from where it will be
applied, generalised without stating the condition.

## Deviation from the plan as written

The plan's `files_modified` named `stack.yaml.lock` and all seven `.cabal` files. `aa6057b`
committed `stack.yaml`, `stack-core.yaml` and **six** `.cabal` files; `stack.yaml.lock` and
`components/cfmm-adapter/evm-spec-bridge-cfmm-adapter.cabal` arrived one plan later, in 01-05's
`3a142dc`. Recorded rather than smoothed over — the lock file is the CI cache key input, and where
it landed matters for reading the cache-key history.

## Files created

- `stack.yaml`, `stack-core.yaml`
- six generated `.cabal` files under `components/`

## Requirements

- **CFMM-01** — the mechanism now exists. It has not yet been *seen* to fire; that is 01-04.
