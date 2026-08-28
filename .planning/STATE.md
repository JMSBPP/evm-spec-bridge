# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-27)

**Core value:** A Foundry test can obtain the Haskell spec's answer for an arbitrary input during a live `forge test` run, and can tell spec success, spec rejection, and transport failure apart — never conflating them.
**Current focus:** Phase 2 — Transport Spike (Throwaway)

## Current Position

Phase: 2 of 11 (Transport Spike — Throwaway)
Plan: 0 of 5 in current phase
Status: Planned — 5 plans, ready to execute
Last activity: 2026-08-28 — Phase 2 planned (5 plans, 26 tasks); criterion 3 corrected to match what each side can assert

Progress: [█░░░░░░░░░] 9%

## Performance Metrics

**Velocity:**
- Total plans completed: 9
- Average duration: — (inline execution; per-plan wall time not instrumented)
- Total execution time: — (one session)

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 — Repo Skeleton, Component Seams, CI Floor | 9/9 | 1 session | — |

**Measured CI cost (replaces all estimates):**
- seam job 125 s · build job 440 s · cold spec compile 302 s hosted / 281 s local
- Seam guard: 303 ms warm, **118 818 ms cold** — the cache must be restored before the seam job

**Recent Trend:**
- Last 5 plans: 01-05 … 01-09, all complete
- Trend: steady; one type error escaped four plans and was caught by CI's build job

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
- **CLOSED (Phase 2 discussion)**: the consumer's Foundry pin is confirmed at their `.github/foundry-version` (CI-05, commit `dddb26b`) — `v1.5.1` / `b0a9dd9ceda36f63e2326ce530c10e6916f4b8a2`, byte-identical to the binary every measured finding is scoped to. The return-path shape resolves to 1.5.1's: unwrapped (`PITFALLS.md:103`).
- **CLOSED**: Solidity `try`/`catch` against the cheatcode address — MEASURED, `0xeeaa9e6f` with non-empty errdata. Consumed, not re-derived.
- **OPEN (Phase 2)**: whether alloy enforces a response `Content-Type` (`ARCHITECTURE.md:612`, LOW confidence). The last unverified transport item; probed as a three-row matrix.
- **DEFERRED to Phase 6**: `guess_local_url`/`HTTP_PROXY` trap is `[S]` source-derived, never measured — the same provenance that produced the `vm.rpcJson` error.
- **RETIRED (Phase 1)**: hosted-CI billing risk — hosted Actions execute; run `33125024351` green, 87 GB free.
- **RETIRED (Phase 1)**: GHC-on-a-runner risk — cold hosted build 302 s; image builds and publishes.
- **Carried tension (D6)**: hosted-only CI is structurally incapable of detecting the zombie-process / port-collision class that will bite the consumer's persistent self-hosted runner. Probed in Phase 1, resolved in Phase 10.

## Session Continuity

Last session: 2026-08-28
Stopped at: Phase 2 planned (5440de2); ready for /gsd:execute-phase 2
Resume file: .planning/phases/02-transport-spike-throwaway/02-01-PLAN.md
