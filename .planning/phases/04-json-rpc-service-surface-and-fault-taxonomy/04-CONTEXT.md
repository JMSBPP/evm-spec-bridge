# Phase 4: JSON-RPC Service Surface and Fault Taxonomy — Context

**Gathered:** 2026-08-28
**Status:** Ready for planning (partial — service decisions still open)

<domain>
## Phase Boundary

Deliver a strict, pure, namespaced JSON-RPC server surface with fixture methods
(`spec_health`, `spec_fixtureRejection`, `spec_fixtureTransportFault`) that exercise
all three outcomes end-to-end with **zero domain code**. Close PROTO-05, PROTO-06,
PROTO-08, PROTO-09, PROTO-10, SRV-06, SRV-07.

Also refresh `README.md` so a human reviewer can grasp the service surface at a glance
when the phase lands — diagrams first, bullets after, concise prose throughout.

Out of scope: warm-process hardening (Phase 5), harness lifecycle (Phase 6), codegen
(Phase 8+), cfmm domain (Phase 11).
</domain>

<decisions>
## Implementation Decisions

### Documentation deliverable (user-requested)
- **D-01:** Phase 4 MUST update `README.md` before close-out. Structure:
  1. **Diagrams lead** — at minimum: request/response flow (forge → JSON-RPC → envelope →
     hex returndata), three-outcome channel map (`result` vs `error`), and the `spec_*`
     method surface (health + fixtures). Mermaid or ASCII; prefer what renders on GitHub
     without extra tooling.
  2. **Bullet points follow** — quick-scan facts: core value, fixture methods, strict-decode
     rules, how to run locally (`stack` / `just` / forge against stub), link to `.planning/`.
  3. **Concise** — replace the current 12-line stub; target readable in under 2 minutes.
  4. **Code review gate (replaces manual README review)** — after push, run
     `$gsd-code-review 4` (or Bugbot on `origin/develop...HEAD`). Reviewer inspects
     README structure (diagrams-first, run commands), registry/transport dispatch, and
     strict-decode paths. Findings land in `04-REVIEW.md`; criterion 6 passes when
     Critical/Warning findings are resolved or accepted.
  — **Reversibility:** reversible — README can be edited anytime; no wire contract.

### the agent's Discretion
- Exact diagram count and layout (one combined vs. two focused diagrams).
- Whether README documents `oracle-stub` vs. the new server executable — planner picks
  based on what Phase 4 actually ships, but the doc must match runnable reality.
- Wording and section titles.

</decisions>

<canonical_refs>
## Canonical References

### Phase goal and requirements
- `.planning/ROADMAP.md` — Phase 4 success criteria (including README criterion)
- `.planning/REQUIREMENTS.md` — PROTO-05/06/08/09/10, SRV-06/07
- `.planning/PROJECT.md` — core value statement (reuse in README lede)

### Prior phase outputs Phase 4 builds on
- `components/jsonrpc/src/Bridge/JsonRpc.hs` — channel discipline (PROTO-02)
- `components/abi-codec/src/Bridge/AbiCodec/Envelope.hs` — hex envelope
- `components/oracle-stub/app/Main.hs` — existing warp stub (may extend or supersede)
- `solidity/test/Discrimination.t.sol` — pattern for Solidity-side CI assertions

### Research / pitfalls
- `.planning/research/PITFALLS.md` — why rejections cannot use JSON-RPC `error` channel

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Bridge.JsonRpc.outcomeResponse` / `protocolFault` — already split result vs error paths.
- `oracle-stub` — warp server with mode flags; Phase 4 likely evolves this into named methods.
- Phase 3 forge tests — discrimination/boundary patterns reusable for fixture method CI.

### Integration Points
- New method dispatch layer sits between warp `Application` and `JsonRpc` + envelope encode.
- README should reflect whatever executable and `just` recipes Phase 4 adds.

</code_context>

<specifics>
## Specific Ideas

User (2026-08-28): include README update in this phase — concise description **leading
with diagrams**, bullet points after, for clear human review when Phase 4 lands.

Suggested README diagram topics (planner may refine):
1. **End-to-end path:** `forge test` → `vm.rpc` → HTTP JSON-RPC → handler → envelope → `0x…` returndata → Solidity decode by tag byte.
2. **Outcome channels:** success/rejection in `result` (hex envelope); transport/protocol fault in `error` (stable code).
3. **Method surface:** `spec_health`, `spec_fixtureRejection`, `spec_fixtureTransportFault`; `-32601` for non-`spec_*`.

</specifics>

<deferred>
## Deferred Ideas

None captured yet — gray-area discussion (registry shape, server component split) still open.

</deferred>

---

*Phase: 04-json-rpc-service-surface-and-fault-taxonomy*
*Context gathered: 2026-08-28*
