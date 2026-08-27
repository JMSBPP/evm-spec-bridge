---
phase: 1
slug: repo-skeleton-component-seams-ci-floor
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-27
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

**Phase requirements:** CFMM-01, DIST-03, DIST-04

**Note on this phase's character.** Phase 1 delivers a skeleton, so most validation is
*structural* (does it build, does the guard fire, does the image publish) rather than
behavioural. The `tasty` suite exists to prove the harness runs, not to assert domain
behaviour — there is none yet. The single most important validation here is the **negative
test**: proof that the seam guard actually fires. A guard nobody has seen fire is a guard
being trusted, not verified.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `tasty` (Stack + hpack `tests:` stanza) — overrides the `hspec` recommendation in research/STACK.md |
| **Config file** | `package.yaml` per component; `stack.yaml` (full) and `stack-core.yaml` (spec-less) |
| **Quick run command** | `stack --stack-yaml stack-core.yaml build --dry-run` (~0.34 s, measured) |
| **Full suite command** | `stack build --test` |
| **Estimated runtime** | Guard: <1 s. Full build: UNMEASURED — measuring it is a Phase 1 deliverable |

---

## Sampling Rate

- **After every task commit:** Run the seam guard (`--dry-run`, sub-second — no excuse to skip)
- **After every plan wave:** Run `stack build --test`
- **Before `/gsd:verify-work`:** Full gate green on a pushed branch, image built
- **Max feedback latency:** <1 s for the guard; build time TBD and recorded as a deliverable

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Status |
|---------|------|------|-------------|-----------|-------------------|--------|
| Seven packages resolve | TBD | 1 | CFMM-01 | structural | `stack build --dry-run` exits 0 | ⬜ pending |
| Spec-less config excludes spec | TBD | 1 | CFMM-01 | structural | `stack --stack-yaml stack-core.yaml build --dry-run` exits 0 on a clean tree | ⬜ pending |
| **Seam guard fires (negative test)** | TBD | 1 | CFMM-01 | negative | Add `cfmm-vol-markets-spec` to a core package → guard exits **1** with `S-4804` | ⬜ pending |
| Guard names the offender | TBD | 1 | CFMM-01 | negative | Guard stderr contains the offending package name AND `stack-core.yaml` | ⬜ pending |
| hpack drift gate | TBD | 1 | DIST-04 | structural | `hpack` then `git diff --exit-code` exits 0 | ⬜ pending |
| tasty suite runs | TBD | 1 | DIST-04 | harness | `stack build --test` runs the suite and exits 0 | ⬜ pending |
| Gate triggers on push AND PR | TBD | 2 | DIST-04 | structural | workflow `on:` contains both `push` and `pull_request` | ⬜ pending |
| Image builds | TBD | 2 | DIST-04 | structural | `docker build` exits 0; final stage is `debian:bookworm-slim` | ⬜ pending |
| Image publishes on push only | TBD | 2 | DIST-04 | structural | push step guarded by `if: github.event_name == 'push'` | ⬜ pending |
| Image ref is lowercase | TBD | 2 | DIST-04 | structural | image ref contains no uppercase — `github.repository` is NOT used raw |  ⬜ pending |
| Build times recorded | TBD | 2 | DIST-04 | measurement | Job log contains cold and warm timings; numbers land in SUMMARY | ⬜ pending |
| Fork → PR path works | TBD | 2 | DIST-03 | structural | A PR from JMSBPP to d2p-finance runs the gate; no direct push to canonical | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `stack.yaml` — full config, snapshot LTS 24.55 by URL, `cfmm-vol-markets-spec` git extra-dep
- [ ] `stack-core.yaml` — spec-less config listing only the six core packages
- [ ] A `tests:` stanza with `tasty` in at least one package, so the harness exists from day one
- [ ] The negative-test script — must live **outside** `stack test` (a test of the build, run inside
      the build, never executes when the build breaks)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| GHCR package visibility | DIST-04 | A newly published GHCR package is **private by default**, and flipping it public is a one-time, irreversible manual UI action no workflow can perform | After the first successful publish, set the package to Public in GitHub's UI, then confirm `docker pull` works with no auth from a logged-out context |
| Canonical repo receives PRs only | DIST-03 | Enforcing it is a branch-protection setting, not a build artifact | Confirm `d2p-finance/evm-spec-bridge` `main` has no commits other than via PR |

---

## Known Validation Gaps

- **`cfmm-vol-markets-spec` resolution ≠ compilation.** The seam guard was verified with `--dry-run`,
  which proves the *build plan*, not that the spec compiles with cairo on a fresh runner. This is
  the highest-value thing to attempt early: if it fails, everything downstream is blocked, and
  Phase 1 is the cheapest place to find out.
- **`~/.stack` cache size vs the 10 GB Actions cap** — unmeasured. Print `du -sh` alongside the
  build times.
- **BuildKit `--mount=type=cache` surviving `cache-to: type=gha`** — MEDIUM confidence; do not
  depend on it.
- **Build times are LOW confidence by construction** — they are unmeasured because measuring them
  is the deliverable, not a research output.

---
*Validation strategy created: 2026-08-27*
