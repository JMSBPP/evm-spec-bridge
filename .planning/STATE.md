# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-27)

**Core value:** A Foundry test can obtain the Haskell spec's answer for an arbitrary input during a live `forge test` run, and can tell spec success, spec rejection, and transport failure apart — never conflating them.
**Current focus:** Phase 1 — Repo Skeleton, Component Seams, CI Floor

## Current Position

Phase: 1 of 11 (Repo Skeleton, Component Seams, CI Floor)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-08-27 — Roadmap created; 41/41 v1 requirements mapped across 11 phases

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: —
- Trend: —

*Updated after each plan completion*

## Accumulated Context

### Decisions

Full log in PROJECT.md Key Decisions. Affecting current work:

- [Roadmap]: Transport spike (Phase 2) is throwaway and version-pinned; nothing of consequence is built on `vm.rpc` until a green `forge test` proves it against the consumer's exact pinned Foundry version
- [Roadmap]: `VolOrder(T)` codec sequenced last (Phase 11) so the consumer's open Phase 4 decision stalls nothing — Phases 1-10 are independent of it
- [Roadmap]: RPC-02 split — spec owns guard evaluation, bridge owns error classification and protocol well-formedness. PROJECT.md governs over ARCHITECTURE.md's contrary assumption (research disagreement D5)
- [Roadmap]: False-green killers (INTEG-01 spec SHA, INTEG-04 vacuity guard, DIST-05 leak lane) land in Phase 7, immediately after the lifecycle surfaces they depend on — not as end-of-project polish
- [Roadmap]: Foundry-coercion conformance fixture lands with the drift gate in Phase 8, so a toolchain bump goes red rather than silently reclassifying outcomes

### Pending Todos

None yet.

### Blockers/Concerns

- **OPEN (external)**: `VolOrder(T)` wire format is owned by the consumer's Phase 4, roughly three phases out on their side. Must not be pre-empted. Blocks Phase 11 only.
- **Phase 2 blocking input**: the consumer's exact pinned `forge --version` is unconfirmed. Every MEASURED research finding is scoped to `forge 1.5.1-stable`, and `master` vs 1.5.1 disagree on the return-path shape.
- **Phase 2 unverified item**: whether Solidity `try`/`catch` works against the cheatcode address. The consumer has volunteered to run this experiment and report gate evidence — consume their result, do not duplicate it.
- **Carried risk**: hosted CI has been billing-blocked elsewhere in this ecosystem (`tao-plank-vault`). Phase 1 must confirm hosted runners actually work.
- **Carried tension (D6)**: hosted-only CI is structurally incapable of detecting the zombie-process / port-collision class that will bite the consumer's persistent self-hosted runner. Probed in Phase 1, resolved in Phase 10.

## Session Continuity

Last session: 2026-08-27
Stopped at: ROADMAP.md and STATE.md written; REQUIREMENTS.md traceability populated
Resume file: None
