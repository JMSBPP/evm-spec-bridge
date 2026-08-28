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

- [x] **Phase 1: Repo Skeleton, Component Seams, CI Floor** - Seven Stack components build green on hosted CI with the cfmm seam enforced by a spec-less config, and a minimal container image publishes to GHCR
- [x] **Phase 2: Transport Spike (Throwaway)** - A green `forge test` proves `warp` can serve Foundry's alloy client on the consumer's pinned Foundry version, and the toolchain is pinned in a form that can fail
- [x] **Phase 3: Three-Outcome Protocol Core and Hex-ABI Envelope** - Success, rejection and transport failure become distinguishable by construction, byte-exact through Foundry's coercion
- [ ] **Phase 4: JSON-RPC Service Surface and Fault Taxonomy** - A strict, pure, namespaced method surface with fixture methods that exercise all three outcomes with zero domain code
- [ ] **Phase 5: Warm Server Hardening** - One warm process survives a full parallel fuzz run without leaking, wedging, or filing a spec bug as a transport failure
- [ ] **Phase 6: Harness Lifecycle and Ephemeral Endpoint** - The harness owns container start/ready/run/stop on a caller-supplied ephemeral port, and an oracle that never becomes ready aborts the run
- [ ] **Phase 7: Spec Wiring, Staleness and Vacuity Guards** - The answering process proves which spec commit it was built from, and a run where the oracle never succeeded fails loudly
- [ ] **Phase 8: Method Registry and Generated Solidity Interface** - The Solidity interface is generated from the Haskell method registry, committed, and CI goes red on drift
- [ ] **Phase 9: Generated Call Path — Encoder, Decoder, Call Site** - The whole Solidity call path is generated, with no path that returns without a verdict and no unchecked handshake
- [ ] **Phase 10: Consumption Packaging and Integration** - The consumer pulls the published image, pins this repo for the generated Solidity, and gets a green payload-free skeleton with no Haskell toolchain on their runner
- [ ] **Phase 11: cfmm Adapter — `VolOrder(T)` Codec and `volOrderToTokenId`** - The real domain method answers over the wire, with guard violations arriving as typed rejections (EXTERNALLY BLOCKED)

## Phase Details

### Phase 1: Repo Skeleton, Component Seams, CI Floor

**Goal**: The repository exists with its architectural seams already enforced by the compiler, and a hosted CI gate that goes red on anything that does not build. Retires the two carried infrastructure risks (hosted-CI billing, GHC-on-a-runner) before any design work is sunk.
**Depends on**: Nothing (first phase)
**Requirements**: CFMM-01, DIST-03, DIST-04
**Success Criteria** (what must be TRUE):

  1. A push opens a PR from `JMSBPP/evm-spec-bridge` to `d2p-finance/evm-spec-bridge` and CI runs on it; a direct push to the canonical repo is not the path any change takes
  2. CI builds every component that exists and fails the run if any does not compile, with actual cold and warm build times recorded (all current estimates are unmeasured). The Stackage snapshot matches the spec's (LTS 24.55), and the hpack-generated `.cabal` is gated against `package.yaml` drift the same way the generated Solidity is
  3. Seven components exist (`protocol`, `abi-codec`, `jsonrpc`, `registry`, `transport`, `codegen`, `cfmm-adapter`) and a **spec-less Stack config** builds the six core ones without the `cfmm-scratchpad` extra-dep — so a core component gaining a spec dependency fails to *resolve*, a hard error rather than an inferred signal. A **negative test** deliberately adds the forbidden edge and observes the guard fire
  4. A minimal multi-stage **container image is built and published to GHCR** from CI, proving GHC-in-a-container, cairo/pango resolution and the publish path while there is almost no code. This replaces the self-hosted-runner probe: the question becomes "can their runner run our image", answerable without owning the machine
  5. A `tasty` test scaffold runs in the gate, so later phases add cases rather than also wiring up a runner

**Plans**: 9 plans (sequential — execution is INLINE with the user, `parallelization: false`)

- [x] 01-01-PLAN.md — Toolchain ground truth and the `cfmm-scratchpad` compile probe (retires the compile-vs-resolve and hosted-CI billing risks first)
- [x] 01-02-PLAN.md — Seven component packages with the cfmm seam declared
- [x] 01-03-PLAN.md — Two Stack configs, one source tree; the seam expressed as a proposition
- [x] 01-04-PLAN.md — The negative test, and the meta-check that tests the test
- [x] 01-05-PLAN.md — `tasty` scaffold, hpack drift gate, `justfile`
- [x] 01-06-PLAN.md — Trivial executable and the multi-stage container image (cairo is build-time only)
- [x] 01-07-PLAN.md — CI gate: `seam` and `build` jobs on push AND pull_request, with measured build times
- [x] 01-08-PLAN.md — GHCR publish and the fork-PR permission asymmetry
- [x] 01-09-PLAN.md — DIST-03 made structural: branch protection, a refused push, the promotion PR, README

### Phase 2: Transport Spike (Throwaway)

**Goal**: Confirm that a Haskell **`warp`** server can be the thing on the other end of `vm.rpc`,
and pin the Foundry toolchain in a form that can go red. Deliberately smaller than it wants to be:
no registry, no codegen, no domain, no abstraction over an unproven mechanism. Everything built
here is discarded except the pin.
**Depends on**: Phase 1
**Requirements**: DIST-06

**AMENDED 2026-08-28 — three of the original four criteria were already satisfied before the phase
began, and the fourth named a file that cannot satisfy it.** The original criteria are preserved
below with their disposition, because deleting them would erase the record of what was checked.

**Success Criteria** (what must be TRUE):

  1. `forge test` passes calling `vm.rpc` against a stub **Haskell `warp`** server returning a
     hardcoded `"0x" <> hex(...)` payload, on the consumer's confirmed `forge --version`
     (`v1.5.1` / `b0a9dd9`). Every prior measurement was taken against a non-Haskell stub oracle
     in `/tmp/orctest` (`PITFALLS.md:7`); **warp has never been on the other end of an alloy call**

  2. The response `Content-Type` question is answered by observation, not by reading alloy source:
     identical bodies served as `application/json`, as `text/plain`, and with **no Content-Type at
     all**, recorded as a three-row table. Retires `ARCHITECTURE.md:612`, the last LOW-confidence
     transport item

  3. The Foundry version is pinned in a mechanism that **can fail** — a shell-sourceable
     `.github/foundry-version` carrying release tag, release commit and installer commit, and
     machine-readable by the Phase 8 header generator. The two sides assert different things, and
     each asserts only what it can actually see:

     - **Locally** (where `forge` exists): `forge --version | grep -qF "$FOUNDRY_COMMIT"` — the
       binary assertion, and the one that makes a measurement trustworthy. It runs before any
       measurement is recorded

     - **In CI** (where `forge` is deliberately NOT installed): well-formedness only — the file is
       shell-sourceable, all three values are present, and `FOUNDRY_COMMIT` is 40 hex characters.
       Installing forge purely to assert it is the forge just installed would be circular
     A drift check against the consumer's pin is deliberately NOT done here: their pin file is
     currently public only on `JMSBPP/cfmm-vol-markets@develop`, an unpromoted fork branch, and
     gating our build on it is Phase 10's concern, not the spike's.
     *Supersedes the original criterion 3, which required `foundry.toml` to pin the version.
     Measured on the pinned binary: `forge config --json` emits 111 keys and the only version-ish
     key is `evm_version` — the EVM hardfork. `foundry.toml` cannot pin a forge binary.*

  4. The hex-envelope claim is confirmed end-to-end against warp: a `0x`-prefixed even-length hex
     string survives Foundry's `json_value_to_token` coercion **byte-exact**. Everything from
     Phase 3 onward rests on this (`PITFALLS.md:82`) and it has never been tested against our stack

  5. The spike is deleted at phase end; only `.github/foundry-version` and the recorded
     measurements survive

**Criteria satisfied before this phase began — consumed, NOT re-derived:**

  - *Original criterion 2 (`try`/`catch` against the cheatcode address)* — **MEASURED**. The
    `catch` branch fires; errdata carries `CheatcodeError(string)` = `0xeeaa9e6f` and decodes
    non-empty. Non-empty data bearing the cheatcode's own selector rules out a caller-side
    `extcodesize` failure, so the result is conclusive. See PROJECT.md "Resolved since
    initialization". The low-level `address(vm).call` form remains the conservative default

  - *Original criterion 4 (return-path shape)* — **MEASURED** at `PITFALLS.md:103`: on
    `1.5.1-stable` the raw returndata is `abi.encode(<coerced value>)`, **not**
    `abi.encode(<bytes>)`. `master` wraps; 1.5.1 does not. Re-confirmed as a byproduct of
    criterion 1, since the test decodes the value anyway

  - *`vm.rpcJson` availability* — **MEASURED** absent at `PITFALLS.md:134-137`

**Plans**: 5 plans (sequential — execution is INLINE with the user, `parallelization: false`,
background agents forbidden)

- [x] 02-01-PLAN.md — The Foundry pin: `.github/foundry-version`, the assertion that can go red, and a negative test that makes it fire
- [x] 02-02-PLAN.md — The throwaway warp stub, as a self-contained Stack project so deletion is `rm -rf spike/`
- [x] 02-03-PLAN.md — Minimal forge project and the first green `vm.rpc` test — plus proof the green is not vacuous
- [x] 02-04-PLAN.md — Content-Type matrix (json / text-plain / absent) and the byte-exact hex-envelope round-trip
- [x] 02-05-PLAN.md — Summary, delete the spike, and update ROADMAP/REQUIREMENTS/STATE in this plan

**Note**: The consumer's pin is confirmed at `.github/foundry-version` (their CI-05, commit
`dddb26b`): `FOUNDRY_VERSION=v1.5.1`, `FOUNDRY_COMMIT=b0a9dd9ceda36f63e2326ce530c10e6916f4b8a2`.
This is byte-identical to the binary every measured finding is scoped to, so the "blocking input"
recorded in STATE.md is closed. **Mirror their pin idiom, not their install plumbing** — their
`flock`/stamp/per-pin-directory machinery exists for a *persistent* self-hosted runner and solves
a collision hosted ephemeral runners cannot have.

**Note**: The permanent version of criteria 1, 2 and 4 is **Phase 8 criterion 4** (the
Foundry-coercion conformance fixture). Do not build a standing CI lane here out of throwaway code.

### Phase 3: Three-Outcome Protocol Core and Hex-ABI Envelope

**Goal**: The Core Value becomes mechanical. Spec success, spec rejection and transport failure become three constructors no partial function can turn into one another, and the wire representation survives Foundry's value-dependent JSON-to-ABI coercion byte-exact. This is the phase that must not be rushed — every decision in it is rewrite-forcing if omitted.
**Depends on**: Phase 2
**Requirements**: PROTO-01, PROTO-02, PROTO-03, PROTO-04, PROTO-07, INTEG-02
**Success Criteria** (what must be TRUE):

  1. A Solidity test tells a spec rejection from a dead server by reading a tag byte, with no string matching on revert text anywhere in the path — a rejection never travels on the JSON-RPC `error` channel
  2. Boundary values spanning the measured coercion classes (zero, above 2^64, negative, empty,
     32-byte, odd-nibble) round-trip byte-exact **through a real `forge test`**, not merely through
     our own encoder/decoder pair.
     **AMENDED 2026-08-28:** the original required "a property test asserts the encoder never emits
     JSON `null` or a JSON number". That is replaced by a **type-level guarantee — a JSON number or
     `null` must be UNREPRESENTABLE in the result type**, evidenced by the type definition. A
     property test asserting a property the type already makes impossible is vacuous by
     construction, and a trivially-passing test is the artifact this project keeps removing.
     Arrays and the three-encoding comparison (hex / decimal string / raw number) are deliberately
     NOT here — they belong to Phase 8's coercion-conformance fixture (criterion 4)

  3. A test that points at a server which accepts and never answers goes **red**, not green — the 45s-hang-that-passes failure is impossible at the call site by construction, before any generator exists to enforce it
  4. Rejections carry a closed enumerated guard identity: adding a guard is a compile error at every site that consumes the type, and no free-text guard string is exposed for a consumer to start matching on
  5. Every response carries `protocolVersion`

**Plans**: 3/7 plans executed
background agents permitted on approval for mechanical work incl. code, checkpoints stay inline)

- [x] 03-01-PLAN.md — The three-outcome sum type, closed guard enum, `protocolVersion`; `web3-solidity` added to core and its build cost MEASURED
- [x] 03-02-PLAN.md — Type-level: a JSON number or `null` is UNREPRESENTABLE, evidenced by a compile-fail check
- [x] 03-03-PLAN.md — The hex-ABI envelope codec, `abi.encode(uint16 version, uint8 tag, bytes body)`
- [x] 03-04-PLAN.md — JSON-RPC channel discipline: a rejection can only be built as `Response`, never `ResponseError`
- [x] 03-05-PLAN.md — Forge project + the discrimination test: rejection vs dead server by tag byte, zero string matching
- [x] 03-06-PLAN.md — Boundary sweep through real `forge test`, six classes, hex only
- [x] 03-07-PLAN.md — Wedge fixture and call-site red; summary, deletion checks, and the ledger update in-plan

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

  1. The server binds loopback on a port supplied by its caller and refuses to start without one — no default port a leaked process could be found on. Under the container distribution this is a published port mapping, not a bare bind
  2. The harness publishes the endpoint as `EVM_SPEC_BRIDGE_URL`, consumed through the `evm_spec_bridge` alias, so call sites read as a name while the port stays ephemeral
  3. Readiness is polled with backoff against a deadline, checking the container is still running inside the loop; failure to become ready aborts the run with the container's logs attached, and no `sleep` appears anywhere in the lifecycle
  4. Teardown always runs — including when the suite fails — and a post-suite assertion confirms no server was left listening. `docker run --rm` bounds the process lifetime by construction, so teardown is a guarantee rather than a best effort — the single largest reason the container distribution was adopted

**Plans**: TBD

### Phase 7: Spec Wiring, Staleness and Vacuity Guards

**Goal**: Close the hole in the compile-time guarantee. A version pin describes a tree; only a compile-time stamp describes the process actually answering the test. This phase makes the three highest-value silent-false-green paths — a stale build, a leaked process from an earlier run, and a run in which the oracle never succeeded at all — into hard reds.
**Depends on**: Phase 6
**Requirements**: INTEG-01, INTEG-04, DIST-02, DIST-05
**Success Criteria** (what must be TRUE):

  1. `spec_health` reports the spec commit SHA the running binary was **built from**, stamped at compile time — rebuilding against a different spec commit changes the reported SHA without any source edit
  2. `spec_runStats` reports call counts and outcome tallies, and a run in which the oracle never returned a success fails loudly instead of passing silently
  3. A CI lane deliberately leaks a server and starts a second one, and the spec-SHA and ephemeral-port guards are observed to *fire* — the failure class that hosted ephemeral runners structurally cannot produce is produced on purpose. The container distribution narrows but does not remove this: `--rm` bounds a *cleanly-exiting* container, while a wedged or detached one can still linger, and an image tag can still be stale relative to the spec pin
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

  1. A consumer repo **pulls the published image** and pins this repo as a git submodule for the generated Solidity, starts the oracle, runs `forge test` against the health and fixture methods, and sees all three outcomes distinguished — with no domain code on either side and **no Haskell toolchain on their runner**
  2. At least one self-hosted-shaped CI job (a persistent-runner mimic) runs before integration is declared ready, covering the zombie-process and port-collision class that ephemeral hosted runners hide permanently — verifying the guards fire even though the container bounds most of the class
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
| 1. Repo Skeleton, Component Seams, CI Floor | 9/9 | Complete | 2026-08-28 |
| 2. Transport Spike (Throwaway) | 5/5 | Complete | 2026-08-28 |
| 3. Three-Outcome Protocol Core and Hex-ABI Envelope | 7/7 | Complete | 2026-08-28 |
| 4. JSON-RPC Service Surface and Fault Taxonomy | 0/TBD | In progress |  |
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

- **The domain seam is created in Phase 1 and not exercised until Phase 11.** One component
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

- **The container image is the distribution artifact** (decided during Phase 1 discussion). The
  bridge is built and published to GHCR by our gate; the consumer runs it rather than building it.
  This collapses three risks into one — toolchain provisioning on a runner we cannot inspect, the
  zombie/port-collision class on a *persistent* runner, and the consumer's build time, since
  `Chart-cairo` arrives through the spec *library* rather than only its executable. Phase 1 proves
  the image path while there is almost no code; Phase 6's lifecycle and Phase 10's packaging are
  written against it.

- **Execution is INLINE, not delegated to background agents** (decided during Phase 1 discussion,
  applies to every phase). Plans are executed in conversation with heavy user intervention:
  decision points are surfaced rather than silently resolved, and reasoning is explained as the
  work happens. The phases are explicitly a learning exercise for the user, not only a deliverable.
  Phase 1 commits directly to `develop` (the worktree-per-plan convention is suspended while
  execution is inline — see 01-CONTEXT.md).
  Planners must therefore prefer many small tasks over few large ones, place explicit checkpoints
  wherever a non-obvious choice is made, and never bundle independent decisions into one task.
  `plan_checker` stays disabled — the user is the check.
  **STRENGTHENED at Phase 2 (2026-08-28):** every decision must carry a **reference pointer** — a
  `file:line`, a source URL, or a measurement, never recall. **Background agents are
  forbidden by default and permitted only on EXPLICIT user approval, for MECHANICAL tasks —
  including authoring code chunks** (amended 2026-08-28); every `checkpoint:*` task stays inline
  with the user regardless, because delegation moves the typing and never the consent. Teaching
  is reported at PLAN BOUNDARIES rather than at each decision — batching applies to explanation,
  not to consent. **The
  executing skill owns execution AND the STATE.md / ROADMAP.md update, inline** — added because
  Phase 1's ledger was never updated (ROADMAP read `0/9` while nine plans sat committed; patched
  by hand in `41eb40c`). The global `CLAUDE.md` two-step reviewer gate is **deliberately overridden
  for this project by user decision — the user is the review**; no reviewer agents.

- **The JSON-RPC envelope comes from `json-rpc-1.1.2`, the HTTP transport is ours** (decided during
  Phase 2 discussion). `Network.JSONRPC.Data` supplies `Request`/`Response`/`ErrorObj`/`Id`/`Ver`
  and the standard `-32601`/`-32602`/`-32700` constructors; `Network.JSONRPC.Interface` is rejected
  because its only transports are TCP-over-conduit and cannot answer Foundry's HTTP POST. The
  package is in LTS 24.55, so no `extra-deps` entry is needed. **This supersedes PROJECT.md's
  "the envelope is hand-rolled" Key Decision**, which must be amended there.
