---
phase: 01-repo-skeleton-component-seams-ci-floor
status: complete
completed: 2026-08-28
plans: 9
requirements: [CFMM-01, DIST-03, DIST-04]
---

# Phase 1 Summary — Repo Skeleton, Component Seams, CI Floor

**All 9 plans executed inline. All 3 requirements met with evidence. Both carried infrastructure
risks retired.**

## Phase goal, against outcome

> The repository exists with its architectural seams already enforced by the compiler, and a
> hosted CI gate that goes red on anything that does not build.

Achieved. The seam is enforced by dependency *resolution* — a stronger mechanism than the compiler,
because it fails before compilation begins. The gate proved itself by catching a real type error on
its first run.

## Success criteria — verdict

| # | Criterion | Verdict | Evidence |
|---|---|---|---|
| 1 | PR path from fork; direct push not the path | **MET** | Direct push to canonical **refused** by branch protection; `main` still at 1 commit |
| 2 | CI builds every component, fails on non-compiling; measured times; LTS 24.55; hpack drift gated | **MET** | Run `33126990346` all green; seam 125 s / build 440 s measured |
| 3 | Seven components; spec-less config; negative test observes the guard fire | **MET** | `[S-4804]` names the offender; meta-check watched the test fail, then restored byte-identically |
| 4 | Container image built and published to GHCR | **MET** | 129 MB, `ghcr.io/jmsbpp/evm-spec-bridge:develop`, pulled anonymously with a verified-empty credential dir |
| 5 | `tasty` scaffold runs in the gate | **MET** | 01-05; runs in the `build` job |

## What was measured — this replaces every estimate in the planning tree

| Quantity | Value | Conditions |
|---|---|---|
| GHC | **9.10.3** | *inherited* from LTS 24.55 `resolver.compiler`, not chosen |
| Spec pin | `f2736e0`, canonical `d2p-finance` | renamed to `cfmm-vol-markets-spec` mid-phase |
| Spec cold compile | **281 s** local (12 cores), **302 s** hosted | 56 packages incl. `Chart-cairo` |
| Seam guard, warm | **303 ms** | `.stack-work` present |
| Seam guard, **cold** | **118 818 ms** | fresh checkout — **350x the warm figure** |
| `haskell-actions/setup@v2` | 106 s | paid by *both* jobs |
| cairo/pango apt | 14 s | **4.4%** of build cost, not the dominant term |
| seam job / build job | 125 s / 440 s | hosted `ubuntu-latest` |
| Image | 129 MB | `debian:bookworm-slim` + `libgmp10`, no cairo at runtime |

## Decisions that govern later phases

- **D1 `add-now`** — Phase 1 carries the spec extra-dep. Without it the seam guard is *vacuous*:
  `stack.yaml` and `stack-core.yaml` would be semantically identical.
- **Pin canonical, not the fork.** A published image must not depend on unreviewed code.
- **Worktree-per-plan suspended** while execution is inline; Phase 1 commits directly to `develop`.
- **The container image is the distribution artifact** — cairo is build-time only, proven by `ldd`.

## Corrections made during this phase

Nine instrument failures were found and recorded — cases where a check could not detect what it was
pointed at. The ones with lasting consequences:

1. **`stack build --dry-run` resolves a plan; it does not compile.** A `cfmm-adapter` type error
   survived four plans because every local check was a resolution check. CI's `build` job caught it
   on the gate's first run: `seam: success` beside `build: failure`. **Structural cause, not a slip.**
2. **Direct-import grep was the wrong instrument** for a transitive taint question (claimed 19
   modules affected; the true closure was 49 of 62). Corrected by VOL_MARKET_SPEC.
3. **"Cairo provisioning is zero" — retracted.** Absence of a failure on a host that has the headers
   is not evidence of absence of the dependency.
4. **A warm measurement generalised without its condition** (seam guard 0.34 s, actually 119 s cold).
   Forced the cache-before-seam ordering in `ci.yml`.
5. **`gh api` 404 meant *missing scope*, not missing package.** An authorization artefact wearing the
   costume of an existence claim; settled by a credential-free `docker pull`.

**Rules now in force:**
- **Exit code before greps.** Caught `--progress=plain` on the legacy builder and `set -o pipefail`
  under dash — both would have read as clean from greps alone.
- **A check whose scope you cannot widen beats a check you trust yourself to interpret narrowly.**
- Recording a limitation is not the same as being constrained by it.

## A research prediction that did NOT hold

GHCR packages were documented and researched as **private by default**, requiring an irreversible
manual visibility flip. They published **public**. Two anonymous pulls, credential directories
verified empty. The mechanism is **not known and has not been invented** — only the outcome is
recorded. This is the harmless direction: a predicted blocker failing to appear, rather than an
assumed-open path turning out closed.

## Cross-repo outcomes

- The spec package was **renamed** `cfmm-scratchpad` to `cfmm-vol-markets-spec` upstream, at this
  session's request. 76 references across 10 planning files updated.
- **Chart/cairo was split out of the spec library** upstream. Measured spike: 56 external packages
  to 1, no cairo.
- Upstream's Phase 6 packaging rationale was identified as **void as written** — cairo arrived
  through the library, not the executable.
- Finding with cross-repo consequences: **for a git source dependency, Stack builds all components
  of the package, including internal sublibraries** — so the core/plot split saves a git-extra-dep
  consumer nothing. It still pays off for package-database consumers.

## Carried forward to Phase 2

- **BLOCKING INPUT**: the consumer's exact pinned `forge --version` is still unconfirmed. Every
  MEASURED research finding is scoped to `forge 1.5.1-stable`.
- The consumer volunteered to run the `try`/`catch`-against-the-cheatcode-address experiment.
  **Consume their result; do not duplicate it.**
- `libcairo2-dev` can be removed from `ci.yml` **if** upstream's two-package restructure merges.
- The fork to upstream promotion PR is available but not yet opened; branch protection now requires
  `seam`, `build`, `image`.
