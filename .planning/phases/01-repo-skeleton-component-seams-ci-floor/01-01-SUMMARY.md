---
phase: 01-repo-skeleton-component-seams-ci-floor
plan: 01-01
status: complete
completed: 2026-08-27
requirements: [CFMM-01, DIST-04]
---

# 01-01 Summary — Toolchain ground truth, spec compile probe, hosted-CI smoke

## What was established

Both of the phase's carried infrastructure risks are retired with evidence, before any repository
structure existed.

| Question | Answer | Evidence |
|---|---|---|
| Which GHC? | `9.10.3` — **inherited** from LTS 24.55, not chosen | `resolver.compiler` in the snapshot; spec pins the same URL byte-for-byte |
| Which spec commit? | `f2736e0` on **canonical** `d2p-finance` | `git ls-remote`; verified package name and deps at that tree |
| Does the spec *compile*? | **Yes** — exit 0, **281 s** cold | `set -o pipefail`, scratch `STACK_ROOT` |
| Do hosted Actions *execute*? | **Yes** — conclusion `success` | run `33125024351`; 87 GB free on `/` |

## Decisions

- **D1: `add-now`.** The `cfmm-vol-markets-spec` extra-dep is carried by Phase 1. Without it the
  seam guard is vacuous — `stack.yaml` and `stack-core.yaml` would be semantically identical and
  the negative test would go red for any unresolvable name rather than because of the seam.
- **Pin canonical, not the fork.** Plan text named the JMSBPP fork; PROJECT.md makes
  `d2p-finance` the dependency. A published image must not depend on unreviewed code.
- **Worktree-per-plan suspended** while execution is inline (recorded in CONTEXT.md).

## Deviations from the plan as written

1. **Task 4's premise was stale on arrival.** It teaches that cairo is a package-level dep the
   library inherits — true at `93fe3acf`, false at our pin. Recorded rather than repeated.
2. **The package was renamed mid-execution.** Upstream merged `cfmm-scratchpad` →
   `cfmm-vol-markets-spec` in response to a request from this session. 76 references across 10
   planning files updated; RESEARCH.md kept its original measurements under a correction banner,
   because rewriting a record of what was measured would falsify it.
3. **`develop` was pushed during Task 7**, not left for later — deleting the throwaway branch would
   otherwise have orphaned 12 commits on the remote.

## Corrections made to this session's own claims

- **Direct-import grep was the wrong instrument.** Claimed `VolOrder`/`NId` were Chart-free; they
  were tainted transitively (49 of 62 modules, not 19). `NId` was two hops from cairo.
- **"Cairo provisioning is zero" — retracted.** `gtk2hs-buildtools` and `Chart-cairo` build on the
  git-extra-dep path and need cairo dev headers. The build succeeded only because this host has
  them. `libcairo2-dev` stays in 01-06/01-07.

## Measured, for downstream plans to quote

- Cold spec build: **281 s** (`f2736e0`), 301 s (`5d1fb16`) — 12 cores at `-j4`, host, cold root
- `STACK_ROOT` after: **229 MB**; 56 packages built, including `Chart-cairo` **in both variants**
- Hosted runner: `ubuntu-latest`, 145 GB disk, **87 GB free**

## Finding with cross-repo consequences

For a **git source dependency, Stack builds all components of the package, including internal
sublibraries.** The upstream core/plot split therefore saves a git-extra-dep consumer nothing —
independently confirmed upstream via `stack build --dry-run`, which shows Chart in the *plan*.
The split still pays off for package-database consumers. Recorded; `subdirs:`-based fixes are an
untested hypothesis and nothing here depends on them.

## Requirements

- **CFMM-01** — partially advanced: the spec dependency is chosen and proven compilable. The seam
  itself is built in 01-02 → 01-04.
- **DIST-04** — partially advanced: hosted CI proven to execute. The gate is built in 01-07.
