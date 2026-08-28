---
phase: 4
slug: json-rpc-service-surface-and-fault-taxonomy
status: draft
created: 2026-08-28
---

# Phase 4 — Research Notes

**Phase requirements:** PROTO-05, PROTO-06, PROTO-08, PROTO-09, PROTO-10, SRV-06, SRV-07

Written inline for planning — no researcher agent. Sources: Phase 3 code, `json-rpc-1.1.2`, ROADMAP,
CONTEXT D-01.

---

## What Phase 4 adds (vs Phase 3 stub)

Phase 3 proved the **wire contract** — three outcomes, hex envelope, channel discipline — via
`oracle-stub --mode` and dev methods `spec_probe` / `spec_boundary`. Phase 4 promotes that into a
**real service surface**: named fixture methods, strict request decoding, namespace enforcement, and
purity — still zero domain code.

| Layer | Phase 3 | Phase 4 |
|-------|---------|---------|
| Dispatch | `--mode` flag picks outcome for any method | Method name selects handler; `--mode` retained for legacy Phase 3 tests only |
| Methods | `spec_probe`, `spec_boundary` | `spec_health`, `spec_fixtureRejection`, `spec_fixtureTransportFault` (+ legacy dev methods) |
| Decode | Permissive `FromJSON` (`parseId` defaults unknown id to `0`) | Strict: unknown fields, bad shapes → typed fault |
| Location | All logic in `oracle-stub/app/Main.hs` | `registry` (dispatch) + `transport` (HTTP) + thin executable |

---

## Component split (planner discretion — settled here)

**Decision:** Evolve placeholders into real modules; keep `oracle-stub` as the runnable entrypoint.

1. **`Bridge.Registry`** — closed method enum, handler table, zero IO except via pure handler functions.
2. **`Bridge.Transport`** — warp `Application`, body read, batch/notification rejection, calls registry.
3. **`oracle-stub`** — CLI (`--port`, optional legacy `--mode` for Phase 3 recipes), wires transport.

Rationale: Phase 1 named these seams; stuffing another 200 lines into `Main.hs` would make Phase 5
hardening harder and contradict the component map in `stack-core.yaml`.

---

## JSON-RPC library facts (verified Phase 3)

From `Network.JSONRPC.Data` (`json-rpc-1.1.2`, LTS 24.55):

| Constructor | Code | Use in Phase 4 |
|-------------|------|----------------|
| `errorMethod` | -32601 | Unknown / non-`spec_*` method (PROTO-06) |
| `errorParams` | -32602 | Strict decode failures, bad params (PROTO-05) |
| `errorParse` | -32700 | Invalid JSON (PROTO-05) |

PROTO-08: **the `code` field is the stable identifier**; `message` is diagnostic only. Tests assert
on encoded JSON containing the numeric code, not message text (pattern from `jsonrpc/test/Main.hs`).

Optional: put a machine-readable `data` object with a bridge fault enum — only if it does not
duplicate JSON-RPC codes. Default: rely on `-32601/-32602/-32700` unless a param schema needs a
sub-code.

---

## Fixture method semantics (SRV-06, SRV-07)

| Method | Handler behaviour | Channel |
|--------|-------------------|---------|
| `spec_health` | `SpecSuccess` with **non-empty domain-shaped bytes** (32-byte sentinel, same shape boundary/success uses) | `result` hex envelope |
| `spec_fixtureRejection` | `SpecRejection` with fixed `GuardId` (e.g. `GuardStrikeOutOfRange`), no domain payload | `result` hex envelope |
| `spec_fixtureTransportFault` | `SpecTransportFault faultInternalError` — **in-envelope fault tag**, not JSON-RPC `error` | `result` hex envelope |

ROADMAP criterion 2 "protocol fault" means the **third outcome constructor** (`TAG_FAULT`), not a
JSON-RPC `error` response. JSON-RPC `error` is reserved for **request/shape faults** before an
outcome is produced (PROTO-02 preserved).

Legacy: `spec_probe` / `spec_boundary` stay mode-gated so `just discriminate`, `boundary-sweep`, and
`wedge-red` keep working without rewriting Phase 3 CI.

---

## Strict decode approach (PROTO-05)

Use aeson `withObject` + explicit field lists; **reject**:
- Top-level unknown keys on request object
- `params` not matching method schema (wrong arity, wrong types)
- Non-canonical id types where we define canonical (echo whatever valid id was sent; reject `null`
  id on requests that require one — notifications)

Do **not** silently default: delete `parseId` fallthrough that maps unknown values to `IdInt 0`.

---

## Purity (PROTO-10)

Handlers are `RpcContext -> Request -> Response` with **empty context** in Phase 4. No `IORef`, no
counters, no `--mode` affecting fixture methods. Legacy `--mode` only affects `spec_probe` /
`spec_boundary`.

Verification: property test — encode same request twice, assert `encode resp1 == encode resp2`.

---

## README (D-01)

Replace 12-line stub. Structure locked by user:
1. Mermaid/ASCII diagrams (flow, channels, method surface)
2. Bullet quick-scan (core value, fixtures, strict decode, run commands)
3. Human review gate in 04-06 verification

Document **`oracle-stub`** and existing `just` recipes that exercise Phase 4 methods.

---

## Risks / pitfalls

1. **Breaking Phase 3 CI** — any change to `spec_probe` behaviour or run-with-stub poll method breaks
   discrimination/boundary/wedge. Plans must run full Phase 3 recipes after 04-01.
2. **Conflating fault channels** — `spec_fixtureTransportFault` must use envelope tag `0x03`, not
   `protocolFault` JSON-RPC error (PITFALLS.md Pitfall 1).
3. **Vacuous id test** — id echo already partially tested in jsonrpc unit tests; Phase 4 extends to
   error paths and string ids from alloy.

---

## Artifacts this phase produces

| Symbol / path | Plan |
|---------------|------|
| `Bridge.Registry` dispatch | 04-01 |
| `Bridge.Transport.serve` | 04-01 |
| `spec_health` handler | 04-01 |
| `spec_fixtureRejection`, `spec_fixtureTransportFault` | 04-02 |
| `solidity/test/SpecFixtures.t.sol` | 04-02 |
| Strict request decoders | 04-03 |
| Namespace + batch/notification guards | 04-04 |
| Purity property test | 04-05 |
| `README.md` (D-01) | 04-06 |

---

*Phase: 04-json-rpc-service-surface-and-fault-taxonomy*
