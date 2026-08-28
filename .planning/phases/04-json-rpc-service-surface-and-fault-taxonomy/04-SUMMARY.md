# Phase 4 Summary — JSON-RPC Service Surface and Fault Taxonomy

**Completed:** 2026-08-28  
**Plans:** 6/6 executed inline

## What Phase 4 proved

- **`spec_health`** returns the same hex envelope shape domain methods will use (32-byte sentinel, tag `0x01`, `protocolVersion` in word 0).
- **`spec_fixtureRejection`** and **`spec_fixtureTransportFault`** exercise rejection and in-envelope fault paths with zero domain code — asserted from Solidity (`SpecFixtures.t.sol`).
- **Strict JSON-RPC surface:** unknown fields, batch arrays, null/missing `id` → typed faults with stable codes (`-32602`, `-32700`); non-`spec_*` → `-32601`.
- **Id echo** on success and error paths; **handler purity** documented and tested (repeat request → same bytes).
- **Component split:** `Bridge.Registry` (dispatch), `Bridge.Transport` (HTTP + strict parse), thin `oracle-stub` CLI.
- **README (D-01):** diagrams-first human-facing doc.

## What Phase 4 did NOT prove

- Warm-process hardening (SRV-02–05) — Phase 5
- Harness lifecycle / ephemeral port (SRV-08, SRV-09) — Phase 6
- Spec SHA in health (INTEG-01) — later phase
- Domain methods — Phase 11+
- 45s wedge **cost** bound — still Phase 5 SRV-04 (outcome bound exists from Phase 3)

## Requirement traceability

| ID | Status | Evidence |
|----|--------|----------|
| SRV-06 | Met | `spec_health` + registry tests + `just health` |
| SRV-07 | Met | `SpecFixtures.t.sol` + `just fixtures` |
| PROTO-05 | Met | `Bridge.Transport.parseRequest` + transport tests |
| PROTO-06 | Met | `spec_*` prefix guard + namespace test |
| PROTO-08 | Met | fault code assertions in transport/jsonrpc tests |
| PROTO-09 | Met | batch/notification/id tests in transport-test |
| PROTO-10 | Met | INVARIANT haddock + repeat-request tests |

## Test counts (post-phase)

- Haskell: protocol 1, abi-codec 9, jsonrpc 6, registry 6, transport 9
- Solidity: SpecFixtures 2; Phase 3 recipes unchanged

## Phase 3 regression

All Phase 3 `just` recipes pass against refactored stub.
