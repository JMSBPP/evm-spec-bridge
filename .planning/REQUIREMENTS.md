# Requirements: evm-spec-bridge

**Defined:** 2026-08-27
**Core Value:** A Foundry test can obtain the Haskell spec's answer for an arbitrary input during a live `forge test` run, and can tell spec success, spec rejection, and transport failure apart — never conflating them.

**Evidence note.** Requirements marked **[M]** are forced by *measured* behaviour — a stub JSON-RPC oracle probed with real `forge test` against `forge 1.5.1-stable` (`b0a9dd9`, solc 0.8.34). Requirements marked **[S]** are forced by reads of Foundry `master` source. These are not preferences and must not be relaxed without re-measuring. Everything measured is version-scoped; see DIST-06.

## v1 Requirements

### Protocol

- [ ] **PROTO-01**: The result is a Haskell sum type — success, rejection with guard, transport failure — with no partial function able to produce one outcome from another
- [ ] **PROTO-02** **[M]**: Spec rejection travels inside the JSON-RPC `result` as a tagged value; the `error` field is reserved for protocol and transport faults. *Measured: a JSON-RPC error object, HTTP 500, connection refusal and timeout all revert with the identical selector `CheatcodeError(string)` = `0xeeaa9e6f`, differing only in unstable English text*
- [ ] **PROTO-03** **[M]**: Every response result is a single even-length `0x` hex string carrying a tag byte plus a bridge-owned ABI encoding. *Measured: `vm.rpc` coerces JSON results value-dependently — the same record decoded as `tuple(string,string,string)` for `tokenId:"0"` and `tuple(string,string,uint256)` for `tokenId:"18446744073709551616"`; objects reorder alphabetically by key; `null` becomes 32 zero bytes*
- [ ] **PROTO-04**: All numeric and byte quantities are hex strings; JSON numbers are never used for domain values
- [ ] **PROTO-05**: Decoding is strict — unknown fields, out-of-range values and non-canonical encodings are typed protocol faults, never silently defaulted
- [ ] **PROTO-06**: Every method is namespaced `spec_*`; any other method returns JSON-RPC `-32601`
- [ ] **PROTO-07**: Every response carries a `protocolVersion` field
- [ ] **PROTO-08**: Protocol faults carry stable numeric error codes, not free text
- [ ] **PROTO-09**: The JSON-RPC `id` is echoed; notifications and unexpected batch shapes are rejected
- [ ] **PROTO-10**: Handlers are pure — a response is a function of the request alone, with no cross-request state. A tested, documented invariant, not an accident of the implementation

### Server

- [ ] **SRV-01** **[S]**: The server binds loopback HTTP on a caller-supplied ephemeral port, addressed as `http://127.0.0.1:PORT`. *`guess_local_url` recognises only `localhost`/`127.0.0.1`/`::1`; anything else honours `HTTP_PROXY`*
- [ ] **SRV-09**: The harness publishes the endpoint as `EVM_SPEC_BRIDGE_URL`, consumed through the `evm_spec_bridge` alias in `[rpc_endpoints]` via `${...}` interpolation — so call sites read as a name while the port stays ephemeral
- [ ] **SRV-02**: One warm process serves an entire `forge test` run — no per-case spawn
- [ ] **SRV-03**: Request handling is concurrency-safe — no global mutable state and no lock serializing spec evaluation, since `forge test` is parallel across logical cores by default
- [ ] **SRV-04**: Every handler has an exception firewall converting Haskell bottoms into typed internal-error responses, so a spec bug cannot present as a transport failure
- [ ] **SRV-05** **[S]**: Every handler is time-bounded and a timeout returns a typed response rather than dropping the connection. *Foundry hardcodes a 45s timeout for `vm.rpc`; `foundry.toml`'s `eth_rpc_timeout` does not reach it*
- [ ] **SRV-06**: `spec_health` returns the same tagged envelope a domain method returns, so a green health check proves domain payloads survive the trip
- [ ] **SRV-07**: `spec_fixtureRejection` and `spec_fixtureTransportFault` exercise the rejection and fault paths with no domain payload
- [ ] **SRV-08**: Lifecycle is owned by the harness — start, poll readiness with backoff and a deadline, run, stop — and failure to become ready aborts the run rather than proceeding

### Code Generation

- [ ] **GEN-01**: The Solidity interface is generated from the Haskell protocol types
- [ ] **GEN-02**: The generator emits the params encoder, since `vm.rpc` takes params as a JSON string the test would otherwise hand-build — moving the drift rather than removing it
- [ ] **GEN-03**: The generator emits the response decoder
- [ ] **GEN-04** **[M]**: The generator emits the call site including the transport-failure catcher, so asserting on success is structural rather than disciplinary. *Measured: a server that accepts and never answers costs 45.00s per call and the test PASSED, because the call site ignored `success` — at `fuzz.runs = 256`, 3.2 hours of green CI meaning nothing*
- [ ] **GEN-05**: Generated Solidity is committed, and CI fails on any diff after regeneration
- [ ] **GEN-06**: The generator is deterministic — identical input produces byte-identical output
- [ ] **GEN-07**: A runtime `protocolVersion` handshake exists, because generation alone cannot detect a server built from a different schema

### Integrity

- [ ] **INTEG-01**: The spec commit SHA is stamped into the binary at compile time and returned by `spec_health`, so the version claim describes the process answering rather than the tree on disk
- [ ] **INTEG-02**: Rejections carry a closed, enumerated guard identity — never a free-text string consumers would begin matching on
- [ ] **INTEG-03**: The response echoes a canonical digest of the decoded request, verified by the generated decoder, closing the misrouting and stale-response class a warm shared process makes possible
- [ ] **INTEG-04**: `spec_runStats` reports call counts and outcome tallies, so a run in which the oracle never succeeded fails loudly instead of passing silently
- [ ] **INTEG-05**: Transport failure always fails the consumer's test — the bridge ships no skip or degrade path

### cfmm Adapter

- [ ] **CFMM-01**: `cfmm-adapter` is a separate cabal component, and no core component `build-depends` on `cfmm-vol-markets-spec`
- [ ] **CFMM-02**: The adapter decodes the `VolOrder(T)` wire format into the spec's own types without modifying the spec's model
- [ ] **CFMM-03**: `spec_volOrderToTokenId` answers for an arbitrary `(VolOrder(T), poolId)` with `poolId` passed through untouched as a 64-bit value — masking and tickSpacing separation stay inside the spec
- [ ] **CFMM-04**: Guard-violating inputs return a typed rejection naming the guard, never a crash

### Distribution

- [ ] **DIST-01**: The bridge is consumable as a git submodule pinned by the consumer
- [ ] **DIST-02**: The bridge is the single authority on the spec version; the consumer drops its direct `spec/` pin
- [ ] **DIST-03**: Changes reach `d2p-finance/evm-spec-bridge` only via PR from the `JMSBPP` fork
- [ ] **DIST-04**: An own CI gate on hosted runners builds the library, the server and the generated Solidity
- [ ] **DIST-05**: A lifecycle lane deliberately leaks a server and starts a second, asserting the spec-SHA and ephemeral-port guards actually fire — since hosted runners are ephemeral and cannot produce that condition naturally
- [ ] **DIST-06**: This repo pins an exact Foundry version, published as part of the integration contract, so every measured transport finding is scoped to something enforceable

## v1.x Requirements

Deferred with explicit triggers, not vague intent.

| ID | Requirement | Trigger |
|----|-------------|---------|
| **LATER-01** | Golden-vector export CLI — dumps `(input, expected outcome)` pairs for offline replay with no live server | The GHC-on-self-hosted-runner question comes due, or CI cost bites |
| **LATER-02** | Structured per-request observability plus an end-of-run guard histogram | The first "why is my corpus empty" incident |
| **LATER-03** | Deterministic replay artifact — request/response pairs re-issuable without `forge` | The first fuzz failure that is painful to reproduce |
| **LATER-04** | Counterexample bundle — request, response, spec version, server version, seed | A failure that cannot be reproduced locally |
| **LATER-05** | `vm.rpcJson` + `vm.parseJson` decode path | The consumer's Foundry pin reaches v1.8.0+, or a coercion surprise appears |

## Out of Scope

| Feature | Reason |
|---------|--------|
| Spec-drives-EVM direction | Intended for v2 and named in the original design sketch, but no consumer exists. v1 ships the query direction only |
| Domain-agnostic core abstraction | "cfmm-first, generalize later" — an abstraction built for one real and one imagined consumer fits neither. CFMM-01's component seam is the entire generalize-later investment |
| Domain rejection on the JSON-RPC `error` channel | Fatal, not merely inelegant — Foundry maps it to the same untyped revert as a dead socket, destroying the core value |
| General-purpose EVM node proxy / forwarding `eth_*` | Turns a small pure oracle into an EVM implementation with a consensus surface, and invites Foundry's fork machinery to interact with it |
| Mutable oracle state or session handles | Breaks purity, and with it fuzz shrinking and counterexample replay — the same request would stop yielding the same answer |
| Lenient decoding | A silently-defaulted input means the spec answers a different question than the contract was asked, and the two agree by luck |
| Any skip or degrade path on transport failure | The exact failure this project exists to prevent |
| Routing spec rejection through `vm.assume` | Burns the shared 65536 reject budget and makes rejections invisible |
| Client-side retries around `vm.rpc` | On loopback to a local process a failure is a real bug; retry converts a reproducible fault into an intermittent one |
| Persistent on-disk answer cache | A cache surviving a spec version change serves pre-fix answers, and the differential test confirms the old bug |
| Server spawned per test or per fuzz case | Spawn cost across thousands of cases, plus port collisions under parallel execution |
| Auth, TLS, rate limiting, multi-tenancy | It binds loopback for the duration of one `forge test`; each addition creates failure modes that present as transport failure |
| WebSockets, subscriptions, streaming | `vm.rpc` is strictly request/response and there is no consumer for a push channel |
| `spec_batch` | Fuzzing supplies one input per run, so batch size is one. Revisit when a table-driven consumer exists |
| Hand-written Solidity mirrors of the Haskell types | Precisely the drift this project exists to eliminate |

## Traceability

Populated during roadmap creation (2026-08-27).

| Requirement | Phase | Status |
|-------------|-------|--------|
| **PROTO-01** | Phase 3 | Pending |
| **PROTO-02** | Phase 3 | Pending |
| **PROTO-03** | Phase 3 | Pending |
| **PROTO-04** | Phase 3 | Pending |
| **PROTO-05** | Phase 4 | Pending |
| **PROTO-06** | Phase 4 | Pending |
| **PROTO-07** | Phase 3 | Pending |
| **PROTO-08** | Phase 4 | Pending |
| **PROTO-09** | Phase 4 | Pending |
| **PROTO-10** | Phase 4 | Pending |
| **SRV-01** | Phase 6 | Pending |
| **SRV-02** | Phase 5 | Pending |
| **SRV-03** | Phase 5 | Pending |
| **SRV-04** | Phase 5 | Pending |
| **SRV-05** | Phase 5 | Pending |
| **SRV-06** | Phase 4 | Pending |
| **SRV-07** | Phase 4 | Pending |
| **SRV-08** | Phase 6 | Pending |
| **SRV-09** | Phase 6 | Pending |
| **GEN-01** | Phase 8 | Pending |
| **GEN-02** | Phase 9 | Pending |
| **GEN-03** | Phase 9 | Pending |
| **GEN-04** | Phase 9 | Pending |
| **GEN-05** | Phase 8 | Pending |
| **GEN-06** | Phase 8 | Pending |
| **GEN-07** | Phase 9 | Pending |
| **INTEG-01** | Phase 7 | Pending |
| **INTEG-02** | Phase 3 | Pending |
| **INTEG-03** | Phase 9 | Pending |
| **INTEG-04** | Phase 7 | Pending |
| **INTEG-05** | Phase 9 | Pending |
| **CFMM-01** | Phase 1 | Pending |
| **CFMM-02** | Phase 11 | Pending |
| **CFMM-03** | Phase 11 | Pending |
| **CFMM-04** | Phase 11 | Pending |
| **DIST-01** | Phase 10 | Pending |
| **DIST-02** | Phase 7 | Pending |
| **DIST-03** | Phase 1 | Pending |
| **DIST-04** | Phase 1 | Pending |
| **DIST-05** | Phase 7 | Pending |
| **DIST-06** | Phase 2 | Pending |

**Coverage:**
- v1 requirements: 41 total
- Mapped to phases: 41
- Unmapped: 0 ✓
- Duplicated across phases: 0 ✓

**By phase:**

| Phase | Requirements | Count |
|-------|--------------|-------|
| 1 — Repo Skeleton, Component Seams, CI Floor | CFMM-01, DIST-03, DIST-04 | 3 |
| 2 — Transport Spike (Throwaway) | DIST-06 | 1 |
| 3 — Three-Outcome Protocol Core and Hex-ABI Envelope | PROTO-01, PROTO-02, PROTO-03, PROTO-04, PROTO-07, INTEG-02 | 6 |
| 4 — JSON-RPC Service Surface and Fault Taxonomy | PROTO-05, PROTO-06, PROTO-08, PROTO-09, PROTO-10, SRV-06, SRV-07 | 7 |
| 5 — Warm Server Hardening | SRV-02, SRV-03, SRV-04, SRV-05 | 4 |
| 6 — Harness Lifecycle and Ephemeral Endpoint | SRV-01, SRV-08, SRV-09 | 3 |
| 7 — Spec Wiring, Staleness and Vacuity Guards | INTEG-01, INTEG-04, DIST-02, DIST-05 | 4 |
| 8 — Method Registry and Generated Solidity Interface | GEN-01, GEN-05, GEN-06 | 3 |
| 9 — Generated Call Path | GEN-02, GEN-03, GEN-04, GEN-07, INTEG-03, INTEG-05 | 6 |
| 10 — Consumption Packaging and Integration | DIST-01 | 1 |
| 11 — cfmm Adapter (externally blocked) | CFMM-02, CFMM-03, CFMM-04 | 3 |

**Sequencing note.** CFMM-02 (and CFMM-03, which rides on it) are externally blocked on the
consumer's Phase 4 `VolOrder(T)` wire-format decision and are deliberately sequenced last so the
blocker stalls nothing. DIST-02 has a consumer-side half (dropping their direct `spec/` pin) that
is coordination rather than a blocker — the bridge-side deliverable is the single-authority
override recipe and coherence check in Phase 7.

---
*Requirements defined: 2026-08-27*
*Traceability populated: 2026-08-27*
