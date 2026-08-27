# Roadmap: evm-spec-bridge

## Overview

The journey runs from an empty repo to a warm Haskell JSON-RPC oracle that a `forge test` can
interrogate mid-run and whose three outcomes — spec success, spec rejection, transport failure —
cannot be confused. The order is dictated by two forces. First, the **unproven mechanism gets
attacked before anything is built on it**: a throwaway transport spike proves `vm.rpc` reaches a
non-Ethereum service against the consumer's *pinned* Foundry version, because every measured
finding in the research set is version-scoped. Second, the **retrofit-expensive and
false-green-killing decisions land as early as their dependencies allow**: the rejection channel,
the hex-ABI envelope shape, the closed guard enum, the exception firewall, the compile-time spec
SHA, the vacuity guard and the leaked-server lane are all near-zero cost early and rewrite-forcing
late. The generated Solidity pipeline — this project's stated differentiator, and the part with no
prior art anywhere — comes only once real methods exist to generate from. The `cfmm` domain work
comes dead last, because its wire format is owned by the consumer's still-open Phase 4 and
guessing through that blocker would repeat exactly the mistake this project already flagged.

Phases 1-10 are entirely independent of the consumer's open `VolOrder(T)` decision. That is
deliberate: it is what makes the pressure to guess evaporate.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Repo Skeleton, Component Seams, CI Floor** - Cabal component boundaries (including the untouched cfmm seam) build green on hosted CI, reachable only by PR from the fork
- [ ] **Phase 2: Transport Spike (Throwaway)** - A green `forge test` proves `vm.rpc` reaches a Haskell service against the consumer's exact pinned Foundry version
- [ ] **Phase 3: Three-Outcome Protocol Core and Hex-ABI Envelope** - Success, rejection and transport failure become distinguishable by construction, byte-exact through Foundry's coercion
- [ ] **Phase 4: JSON-RPC Service Surface and Fault Taxonomy** - A strict, pure, namespaced method surface with fixture methods that exercise all three outcomes with zero domain code
- [ ] **Phase 5: Warm Server Hardening** - One warm process survives a full parallel fuzz run without leaking, wedging, or filing a spec bug as a transport failure
- [ ] **Phase 6: Harness Lifecycle and Ephemeral Endpoint** - The harness owns start/ready/run/stop on a caller-supplied ephemeral port, and a server that never becomes ready aborts the run
- [ ] **Phase 7: Spec Wiring, Staleness and Vacuity Guards** - The answering process proves which spec commit it was built from, and a run where the oracle never succeeded fails loudly
- [ ] **Phase 8: Method Registry and Generated Solidity Interface** - The Solidity interface is generated from the Haskell method registry, committed, and CI goes red on drift
- [ ] **Phase 9: Generated Call Path — Encoder, Decoder, Call Site** - The whole Solidity call path is generated, with no path that returns without a verdict and no unchecked handshake
- [ ] **Phase 10: Consumption Packaging and Integration** - The consumer can pin the bridge as a submodule and get a green payload-free skeleton in its own CI
- [ ] **Phase 11: cfmm Adapter — `VolOrder(T)` Codec and `volOrderToTokenId`** - The real domain method answers over the wire, with guard violations arriving as typed rejections (EXTERNALLY BLOCKED)

## Phase Details

### Phase 1: Repo Skeleton, Component Seams, CI Floor
**Goal**: The repository exists with its architectural seams already enforced by the compiler, and a hosted CI gate that goes red on anything that does not build. Retires the two carried infrastructure risks (hosted-CI billing, GHC-on-a-runner) before any design work is sunk.
**Depends on**: Nothing (first phase)
**Requirements**: CFMM-01, DIST-03, DIST-04
**Success Criteria** (what must be TRUE):
  1. A push opens a PR from `JMSBPP/evm-spec-bridge` to `d2p-finance/evm-spec-bridge` and CI runs on it; a direct push to the canonical repo is not the path any change takes
  2. CI builds every cabal component that exists and fails the run if any does not compile, with actual cold and warm build times recorded (all current estimates are unmeasured)
  3. A `cfmm-adapter` component stanza exists and no core component `build-depends` on `cfmm-vol-markets-spec` — verified by a build that fails if that edge is added
  4. A throwaway probe job has answered whether GHC/cabal can build *and run* a trivial Haskell binary on the consumer's self-hosted runner, and the answer is recorded as evidence rather than assumption
**Plans**: TBD

### Phase 2: Transport Spike (Throwaway)
**Goal**: Prove the one mechanism the entire Core Value rests on — that `vm.rpc` forwards an arbitrary `spec_*` method to a plain Haskell HTTP service and that a cheatcode revert can be converted into a value — against the Foundry version the consumer actually pins. Deliberately smaller than it wants to be: no registry, no codegen, no domain, no abstraction around an unproven mechanism. Everything built here is discarded.
**Depends on**: Phase 1
**Requirements**: DIST-06
**Success Criteria** (what must be TRUE):
  1. `forge test` passes calling `vm.rpc` against a stub Haskell server returning a hardcoded `"0x" <> hex(...)` payload, on the consumer's confirmed `forge --version` — not on `master`, not on whatever is installed by default
  2. It is known and written down whether Solidity `try`/`catch` works against the cheatcode address or whether the low-level `address(vm).call` form is required — the project's lowest-confidence carried assumption is retired by running code, not by reading source
  3. `foundry.toml` pins an exact Foundry version, and that version string is available to be stamped into later generated artifacts
  4. The pinned version's return-path shape is recorded: whether it wraps the coerced payload as `abi.encode(bytes)` or returns it unwrapped, since `master` and `1.5.1-stable` disagree and the Solidity decode path is a function of that answer
**Plans**: TBD

**Note**: The consumer has volunteered to run the `try`/`catch` experiment and report gate evidence. Scope this spike to what *this* repo must prove and consume their result rather than duplicating it.

### Phase 3: Three-Outcome Protocol Core and Hex-ABI Envelope
**Goal**: The Core Value becomes mechanical. Spec success, spec rejection and transport failure become three constructors no partial function can turn into one another, and the wire representation survives Foundry's value-dependent JSON-to-ABI coercion byte-exact. This is the phase that must not be rushed — every decision in it is rewrite-forcing if omitted.
**Depends on**: Phase 2
**Requirements**: PROTO-01, PROTO-02, PROTO-03, PROTO-04, PROTO-07, INTEG-02
**Success Criteria** (what must be TRUE):
  1. A Solidity test tells a spec rejection from a dead server by reading a tag byte, with no string matching on revert text anywhere in the path — a rejection never travels on the JSON-RPC `error` channel
  2. Boundary values spanning the measured coercion classes (zero, above 2^64, negative, empty, 32-byte, odd-nibble) round-trip byte-exact, and a property test asserts the encoder never emits JSON `null` or a JSON number for a domain value
  3. A test that points at a server which accepts and never answers goes **red**, not green — the 45s-hang-that-passes failure is impossible at the call site by construction, before any generator exists to enforce it
  4. Rejections carry a closed enumerated guard identity: adding a guard is a compile error at every site that consumes the type, and no free-text guard string is exposed for a consumer to start matching on
  5. Every response carries `protocolVersion`
**Plans**: TBD

### Phase 4: JSON-RPC Service Surface and Fault Taxonomy
**Goal**: A strict, pure, namespaced JSON-RPC surface exists with fixture methods that exercise all three outcomes end-to-end using no domain code — so that a later domain failure is unambiguously a domain failure.
**Depends on**: Phase 3
**Requirements**: PROTO-05, PROTO-06, PROTO-08, PROTO-09, PROTO-10, SRV-06, SRV-07
**Success Criteria** (what must be TRUE):
  1. `spec_health` returns the *same* tagged envelope shape a domain method returns, so a green health check proves domain payloads survive the trip rather than proving only that the socket is open
  2. `spec_fixtureRejection` and `spec_fixtureTransportFault` produce a real rejection and a real protocol fault with no domain payload, and both are asserted from Solidity in CI
  3. An unknown or non-`spec_*` method returns JSON-RPC `-32601`, and an unknown field, out-of-range value or non-canonical encoding returns a typed fault with a stable numeric code — never a silently defaulted value
  4. The `id` is echoed on every response, and a notification or unexpected batch shape is rejected rather than answered
  5. The same request issued twice returns the same bytes, with no cross-request state — a documented, tested invariant
**Plans**: TBD

### Phase 5: Warm Server Hardening
**Goal**: The warm process — the entire justification for choosing JSON-RPC over `vm.ffi` — survives a full parallel fuzz run. Warmth is what makes cross-case contamination, space leaks and hung handlers possible, and these are invisible at `curl` scale and fatal at fuzz scale.
**Depends on**: Phase 4
**Requirements**: SRV-02, SRV-03, SRV-04, SRV-05
**Success Criteria** (what must be TRUE):
  1. One process serves an entire `forge test` run with no per-case spawn, and a soak of at least 5,000 sequential requests plus a concurrent burst shows identical-input determinism, order-independence and bounded RSS
  2. A deliberately partial value inside a handler produces a *typed* response, not an HTTP 500 — a spec bug can no longer present itself as a transport failure
  3. A handler that would exceed its own deadline returns a typed fault well inside Foundry's hardcoded 45s window instead of dropping the connection, so a wedged oracle costs seconds rather than 45s per fuzz case
  4. Concurrent requests from parallel test contracts are served correctly with no lock serializing spec evaluation and no global mutable state in the answer path
**Plans**: TBD

### Phase 6: Harness Lifecycle and Ephemeral Endpoint
**Goal**: Starting, addressing, waiting for and stopping the oracle is owned by the harness and is deterministic. A server that never becomes ready aborts the run rather than letting the suite proceed against nothing.
**Depends on**: Phase 5
**Requirements**: SRV-01, SRV-08, SRV-09
**Success Criteria** (what must be TRUE):
  1. The server binds loopback on a port supplied by its caller and refuses to start without one — no default port a leaked process could be found on
  2. The harness publishes the endpoint as `EVM_SPEC_BRIDGE_URL`, consumed through the `evm_spec_bridge` alias, so call sites read as a name while the port stays ephemeral
  3. Readiness is polled with backoff against a deadline, checking the process is still alive inside the loop; failure to become ready aborts the run with the server's logs attached, and no `sleep` appears anywhere in the lifecycle
  4. Teardown always runs — including when the suite fails — and a post-suite assertion confirms no server was left listening
**Plans**: TBD

### Phase 7: Spec Wiring, Staleness and Vacuity Guards
**Goal**: Close the hole in the compile-time guarantee. A version pin describes a tree; only a compile-time stamp describes the process actually answering the test. This phase makes the three highest-value silent-false-green paths — a stale build, a leaked process from an earlier run, and a run in which the oracle never succeeded at all — into hard reds.
**Depends on**: Phase 6
**Requirements**: INTEG-01, INTEG-04, DIST-02, DIST-05
**Success Criteria** (what must be TRUE):
  1. `spec_health` reports the spec commit SHA the running binary was **built from**, stamped at compile time — rebuilding against a different spec commit changes the reported SHA without any source edit
  2. `spec_runStats` reports call counts and outcome tallies, and a run in which the oracle never returned a success fails loudly instead of passing silently
  3. A CI lane deliberately leaks a server and starts a second one, and the spec-SHA and ephemeral-port guards are observed to *fire* — the failure class that hosted ephemeral runners structurally cannot produce is produced on purpose
  4. There is exactly one spec checkout in an integration build: the bridge is the single authority on the spec version, with a documented override recipe and a coherence check that goes red if two checkouts appear
**Plans**: TBD

### Phase 8: Method Registry and Generated Solidity Interface
**Goal**: The project's stated differentiator arrives — the Solidity side is generated from the Haskell protocol types, so a wire-contract change breaks the build instead of drifting. Structure is justified by real methods now rather than speculation.
**Depends on**: Phase 7
**Requirements**: GEN-01, GEN-05, GEN-06
**Success Criteria** (what must be TRUE):
  1. Editing a Haskell protocol type and regenerating produces a different `.sol` file; CI fails on any diff between the committed artifact and a fresh regeneration
  2. Running the generator twice produces byte-identical output, and the committed artifact carries an `AUTOGENERATED — DO NOT EDIT` header naming the pinned Foundry version and the schema it came from
  3. A field *rename* with no type change is caught — the case where alphabetical tuple coercion reorders fields and the stale committed `.sol` still compiles
  4. A Foundry-coercion conformance fixture in CI goes red when the toolchain changes coercion behaviour, so a version bump cannot silently reclassify outcomes behind a green build
**Plans**: TBD

**Research flag**: The Haskell-type to Solidity-type mapping has no prior art in any ecosystem. Consider `/gsd:research-phase` before planning; `aeson-typescript` is the nearest structural analogue.

### Phase 9: Generated Call Path — Encoder, Decoder, Call Site
**Goal**: Generation covers the whole path, not just the interface. A hand-built params JSON string or a hand-written decode moves the drift rather than removing it; a hand-written call site makes asserting on success a matter of discipline rather than structure.
**Depends on**: Phase 8
**Requirements**: GEN-02, GEN-03, GEN-04, GEN-07, INTEG-03, INTEG-05
**Success Criteria** (what must be TRUE):
  1. A test calls a spec method without ever hand-writing a params JSON string or a response decode — both are generated from the same schema as the interface
  2. The generated call site has no path that returns without producing a verdict or reverting; deleting the success check is not something a call site author can do, because they do not write one
  3. A transport failure fails the consumer's test unconditionally — there is no skip, no degrade, and no branch that treats an unreachable oracle as agreement
  4. A server built from a different schema is caught at runtime by the `protocolVersion`/schema-digest handshake, not merely assumed away by codegen
  5. The response echoes a canonical digest of the decoded request, verified by the generated decoder, so a misrouted or stale response from a warm shared process is detected rather than compared
**Plans**: TBD

### Phase 10: Consumption Packaging and Integration
**Goal**: The consumer can pin this repo, run a payload-free skeleton, and get a green result that means something — with the diagnosis surface still inside this repo rather than inside their CI. Resolves the hosted-vs-self-hosted CI tension instead of deferring it further.
**Depends on**: Phase 9
**Requirements**: DIST-01
**Success Criteria** (what must be TRUE):
  1. A consumer repo pinning this bridge as a git submodule can start the server, run `forge test` against the health and fixture methods, and see all three outcomes distinguished — with no domain code on either side
  2. At least one self-hosted-shaped CI job (or a container mimicking a persistent runner) runs before integration is declared ready, covering the zombie-process and port-collision class that ephemeral hosted runners hide permanently
  3. The README states honestly what the compile-time guarantee does and does not cover, and the harness script is documented well enough that the consumer does not reinvent lifecycle handling
**Plans**: TBD

### Phase 11: cfmm Adapter — `VolOrder(T)` Codec and `volOrderToTokenId`
**Goal**: The real domain method answers over the wire. The adapter decodes wire bytes into the spec's own types, calls the spec, and **maps** the spec's guard result — it does not evaluate guards. Placed last precisely so its external blocker cannot stall anything else.
**Depends on**: Phase 10, and externally on the consumer's Phase 4 `VolOrder(T)` wire-format decision
**Requirements**: CFMM-02, CFMM-03, CFMM-04
**Success Criteria** (what must be TRUE):
  1. `spec_volOrderToTokenId` answers for an arbitrary `(VolOrder(T), poolId)` from a Solidity test, with `poolId` passed through untouched as a 64-bit value — masking and tickSpacing separation stay inside the spec
  2. A fixture input known to violate a guard returns a typed rejection naming that guard, with zero `HTTP error 500` anywhere in the trace
  3. The wire decode lives behind a single plug-in seam (one module) such that swapping Shock-style tagged for per-variant layout is a same-day change, and no core component gained a dependency on the spec
  4. The bridge contains no re-implementation or re-evaluation of any guard — guard semantics are read out of the spec's own result and mapped, and this is verifiable by inspection of a single mapping function
**Plans**: TBD

**EXTERNALLY BLOCKED**: The `VolOrder(T)` serialization is owned by the consumer's Phase 4 and must not be pre-empted. If a placeholder becomes unavoidable before then, record it in PROJECT.md Key Decisions as `PROVISIONAL — reverts to open if not confirmed by <date>` with a real date and escalate to the user, rather than letting a defensible default become the decision by inertia.

**Research flag**: Cannot be planned until the consumer's Phase 4 lands. Plan the seam now, the codec later.

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Repo Skeleton, Component Seams, CI Floor | 0/TBD | Not started | - |
| 2. Transport Spike (Throwaway) | 0/TBD | Not started | - |
| 3. Three-Outcome Protocol Core and Hex-ABI Envelope | 0/TBD | Not started | - |
| 4. JSON-RPC Service Surface and Fault Taxonomy | 0/TBD | Not started | - |
| 5. Warm Server Hardening | 0/TBD | Not started | - |
| 6. Harness Lifecycle and Ephemeral Endpoint | 0/TBD | Not started | - |
| 7. Spec Wiring, Staleness and Vacuity Guards | 0/TBD | Not started | - |
| 8. Method Registry and Generated Solidity Interface | 0/TBD | Not started | - |
| 9. Generated Call Path — Encoder, Decoder, Call Site | 0/TBD | Not started | - |
| 10. Consumption Packaging and Integration | 0/TBD | Not started | - |
| 11. cfmm Adapter — VolOrder(T) Codec and volOrderToTokenId | 0/TBD | Not started | - |

## Sequencing Rationale

- **The unproven assumption is attacked before anything is built on it.** Phase 2 is throwaway by
  design. If `vm.rpc` fails against the consumer's pinned version, only the wai/warp layer is
  discarded — the protocol types, IR, renderer, codecs and test stack are unaffected, because the
  JSON-RPC envelope is hand-rolled and transport-agnostic.
- **Retrofit-expensive decisions land earliest.** The rejection channel, envelope shape, closed
  guard enum, purity contract, method namespacing and `protocolVersion` are near-zero cost in
  Phases 3-4 and rewrite-forcing if omitted. Generation is the fourth such decision: retrofitting
  it over a hand-written interface means rewriting the interface and every call site.
- **False-green killers land as early as their dependencies allow, not as polish.** The
  wedged-oracle red lands in Phase 3 by hand before Phase 9 makes it structural (GEN-04); the
  compile-time spec SHA (INTEG-01), vacuity guard (INTEG-04) and deliberate-leak lane (DIST-05)
  land in Phase 7, immediately after the lifecycle and health surfaces they need.
- **Every measured finding is version-scoped to `forge 1.5.1-stable`.** DIST-06 pins Foundry in
  Phase 2; the coercion-conformance fixture lands in Phase 8 alongside the drift gate, so a
  toolchain bump goes red rather than silently reclassifying outcomes.
- **The Core Value is proven with fixtures before the domain exists.** Phase 4's fixture methods
  exercise the three-outcome classifier end-to-end in CI with no cfmm code, so a Phase 11 failure
  is unambiguously a domain failure.
- **External blockers are pushed last.** Phases 1-10 are independent of the consumer's open
  `VolOrder(T)` decision. That is a large, valuable slice, and building it is what makes the
  pressure to guess through the blocker evaporate.
- **The domain seam is created in Phase 1 and not exercised until Phase 11.** One cabal component
  boundary, enforced by the compiler. That is the entire "generalize later" investment.

## Governing Decisions Applied

- **RPC-02 split** — the spec owns guard evaluation; the bridge owns error classification and
  protocol well-formedness. PROJECT.md governs. ARCHITECTURE.md's assumption that the bridge owns
  guard evaluation (recorded as disagreement D5) is superseded and must not widen Phase 11.
- **`vm.rpc`, not `vm.rpcJson`** — `rpcJson` ships only from Foundry v1.8.0 and reverts as an
  unknown cheatcode wrapped in the same `CheatcodeError(string)` as a transport failure. Deferred
  to LATER-05.
- **Hosted CI for Phases 1-9, self-hosted-shaped job before integration** — the recorded tension
  (D6) is resolved at Phase 10, and probed cheaply in Phase 1.
