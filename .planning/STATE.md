---
gsd_state_version: 1.0
milestone: v1.5
milestone_name: milestone
status: Ready to discuss
stopped_at: Phase 3 context gathered
last_updated: "2026-08-28T15:11:31.406Z"
last_activity: 2026-08-28 — Phase 2 complete (5/5). `vm.rpc` reaches a Haskell warp server, measured. Content-Type not enforced; hex envelope byte-exact on both the 20-byte and 32-byte branches
progress:
  total_phases: 11
  completed_phases: 2
  total_plans: 14
  completed_plans: 16
  percent: 18
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-27)

**Core value:** A Foundry test can obtain the Haskell spec's answer for an arbitrary input during a live `forge test` run, and can tell spec success, spec rejection, and transport failure apart — never conflating them.
**Current focus:** Phase 3 — Three-Outcome Protocol Core and Hex-ABI Envelope

## Current Position

Phase: 3 of 11 (Three-Outcome Protocol Core and Hex-ABI Envelope)
Plan: 1 of 7 in current phase (03-01 COMPLETE — summary written, pushed at 5cedec5)
Status: In progress — next is 03-02 (type-level: JSON number/null unrepresentable)
Last activity: 2026-08-28 — 03-01 complete. Three-outcome sum type + closed guard enum built; `web3-solidity` added to abi-codec and its cold-build cost MEASURED (+589 s CPU, +85%); seam negative test fires unmodified with a third-party dep in core

Progress: [██░░░░░░░░] 18%

## Performance Metrics

**Velocity:**
- Total plans completed: 9
- Average duration: — (inline execution; per-plan wall time not instrumented)
- Total execution time: — (one session)

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 — Repo Skeleton, Component Seams, CI Floor | 9/9 | 1 session | — |
| 2 — Transport Spike (Throwaway) | 5/5 | 1 session | — |
| 3 — Three-Outcome Protocol Core | 1/7 | in progress | — |

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

### Phase 3 decisions (locked)

- Envelope layout is `abi.encode(uint16 protocolVersion, uint8 tag, bytes body)` — version FIRST so a mismatch is caught where the payload is read. Tag values: `0x01` success, `0x02` rejection, `0x03` fault; **`0x00` RESERVED** because `PITFALLS.md:164` measured JSON `null` → 32 zero bytes with `success == true`, so a zero tag would decode as a valid success. `protocolVersion = 1`.
- Guard enum is BRIDGE-owned, named cfmm constructors, in core `protocol`. It cannot be derived from the spec's type — that is a package dependency from a core component and fails to RESOLVE under `stack-core.yaml`. INTEG-02's compile error lands in `cfmm-adapter`'s exhaustive mapping (Phase 11).
- ABI encoding from **`web3-solidity-1.1.0.0`** in **`abi-codec`** (NOT `protocol`, which imports only `Data.Word`). Never the `web3` meta-package. Snapshot-resident; no extra-dep.
- Forge project is PERMANENT at `solidity/` (03-05 creates it; `spike/` was deleted in 02-05).
- Stub oracle is a real package `components/oracle-stub`, in both `stack.yaml` and `stack-core.yaml`.

### Pending Todos

None yet.

### Blockers/Concerns

- **OPEN (external)**: `VolOrder(T)` wire format is owned by the consumer's Phase 4, roughly three phases out on their side. Must not be pre-empted. Blocks Phase 11 only.
- **CLOSED (Phase 2 discussion)**: the consumer's Foundry pin is confirmed at their `.github/foundry-version` (CI-05, commit `dddb26b`) — `v1.5.1` / `b0a9dd9ceda36f63e2326ce530c10e6916f4b8a2`, byte-identical to the binary every measured finding is scoped to. The return-path shape resolves to 1.5.1's: unwrapped (`PITFALLS.md:103`).
- **CLOSED**: Solidity `try`/`catch` against the cheatcode address — MEASURED, `0xeeaa9e6f` with non-empty errdata. Consumed, not re-derived.
- **CLOSED (Phase 2)**: alloy does NOT enforce a response `Content-Type`. Measured three rows — `application/json`, `text/plain`, header absent — over a byte-identical body; all exit 0. `ARCHITECTURE.md:612` RETIRED.
- **NEW (Phase 3 input), SCOPED**: on the **untyped** path — `abi.decode(vm.parseJson(...))` and raw `vm.rpc` returndata — array signedness is NOT observable: `int256[]` and `uint256[]` have identical ABI layouts, so a wrong-branch decode CANNOT revert. **We are on that path.** REFUTED on forge-std's typed array cheatcodes, which fail loudly on a negative. Signedness must be asserted by our schema. Lands on Phase 8/9 codegen.
- **NEW**: a measurement is scoped to its CODE PATH as much as its version — `vm.rpc` and `vm.parseJson` disagree on identical JSON because `convert_to_bytes` runs on the rpc path only. Label every coercion row.
- **NEW (03-01)**: `scale-1.1.0.0` + `bitvec` — the Substrate SCALE codec — arrive transitively via `web3-crypto`, which `web3-solidity` needs unconditionally. We avoided the `web3-polkadot` PACKAGE, not its codec. Pure Haskell, no native deps; container check still holds.
- **NEW (03-01)**: `web3-solidity` costs **+589 s CPU (+85%)**, +28 packages. Measured under exhausted swap, so NOT comparable to Phase 1's 427 s. If Phase 8 wants a smaller footprint, hand-rolling the three encodings removes 8 packages.
- **STANDING RULE (4 occurrences)**: acceptance criteria must test PROPERTIES, not source text. Anchor greps to syntax prose cannot contain (`'^name ='`, not `'^name'`). Never write a criterion whose only failure mode is someone mentioning the thing.
- **OWED**: `gams-evm-transport` is waiting on arrays and signed values measured on the `vm.rpc` path (Phase 3 criterion 2).
- **DEFERRED to Phase 6**: `guess_local_url`/`HTTP_PROXY` trap is `[S]` source-derived, never measured — the same provenance that produced the `vm.rpcJson` error.
- **RETIRED (Phase 1)**: hosted-CI billing risk — hosted Actions execute; run `33125024351` green, 87 GB free.
- **OPEN (Phase 1 gap, found 2026-08-28)**: `just` is NOT installed on this box, so every `just`-based acceptance criterion in Phase 1 was unverifiable and unflagged. `01-06-PLAN.md:480/:485` required `image` and `image-run` recipes that the `justfile` does not contain. CI does not depend on `just` (its two `ci.yml` mentions are prose in comments), so no gate is red — but the criteria were never met. Not fixed inside Phase 2.
- **RULE (from 02-01-T6)**: every `gh` command in this repo must pass `--repo JMSBPP/evm-spec-bridge`. Bare `gh` resolves to canonical `d2p-finance`, which has no runs by design, and returns `[]` — indistinguishable from "CI did not run".
- **RETIRED (Phase 1)**: GHC-on-a-runner risk — cold hosted build 302 s; image builds and publishes.
- **Carried tension (D6)**: hosted-only CI is structurally incapable of detecting the zombie-process / port-collision class that will bite the consumer's persistent self-hosted runner. Probed in Phase 1, resolved in Phase 10.

## Session Continuity

Last session: 2026-08-28T15:11:31.403Z
Stopped at: Phase 3 context gathered
Resume file: .planning/phases/03-three-outcome-protocol-core-and-hex-abi-envelope/03-CONTEXT.md
