# evm-spec-bridge

## What This Is

A Haskell library and JSON-RPC server that lets a Foundry test call a typed Haskell
specification as an oracle in the middle of a `forge test` run. The spec answers questions
about what a contract *should* do; the test compares that answer to what the contract
*did*; a divergence fails the build.

The protocol schema is expressed as Haskell types, and the Solidity-side interface is
generated from that same source — so the two sides cannot drift silently. A spec change
that breaks the wire contract fails to compile rather than failing a fuzz case at 3am.

Its first consumer is `cfmm-vol-markets`, which needs the Haskell spec's
`volOrderToTokenId` reachable from a Solidity differential test.

## Core Value

A Foundry test can obtain the Haskell spec's answer for an arbitrary input during a live
`forge test` run, and can tell **spec success**, **spec rejection**, and **transport
failure** apart — never conflating them.

If the three outcomes get conflated, a broken oracle masquerades as agreement and the
differential test is worse than useless: it is a green light that means nothing.

## Requirements

### Validated

(None yet — ship to validate)

### Active

All Active requirements are hypotheses until shipped and validated.

**Protocol core**

- [ ] Protocol methods, params and results are Haskell types; the JSON encoding is derived
      from them rather than hand-written
- [ ] The Solidity-side interface is generated from the same Haskell source, so a wire
      contract change breaks the build instead of drifting
- [ ] Spec success, spec rejection (carrying the rejecting guard), and transport failure
      are distinct constructors that cannot be conflated by construction
- [ ] The generated Solidity artifact is a library returning a tagged result struct — not a
      sentinel value and not a custom error, both of which conflate outcomes
- [ ] CI fails if the checked-in generated Solidity artifact is stale relative to the schema

**Server**

- [ ] A JSON-RPC server executable serves spec methods over a socket reachable by Foundry's
      `vm.rpc`, staying warm across test cases rather than spawning per case
- [ ] A payload-free health/echo method is exercisable end-to-end, proving the transport
      shape independently of any domain method
- [ ] An unreachable or non-responding server is reported as transport failure,
      distinguishably, rather than as a spec answer
- [ ] The health method reports the spec commit SHA the running binary was **built from**,
      stamped at compile time — so a stale build cannot misreport its version
- [ ] The server binds an ephemeral port supplied by its caller, so a leaked process from an
      earlier CI run cannot be reached by accident

**First demand — cfmm-vol-markets**

- [ ] The bridge decodes the `VolOrder(T)` wire format produced by Plank into the spec's
      own types, without modifying the spec's model
- [ ] `volOrderToTokenId` is callable through the bridge from outside the Haskell process
- [ ] Guard-violating inputs return a typed rejection, not a crash

**Distribution**

- [ ] The bridge is consumable as a git submodule pinned by `cfmm-vol-markets`
- [ ] Changes reach `d2p-finance/evm-spec-bridge` only via PR from the `JMSBPP` fork
- [ ] The repo has its own CI gate that builds the library, the server, and the generated
      Solidity interface

### Out of Scope

- **Spec-drives-EVM direction** — the bridge lowering typed Haskell transactions to
  JSON-RPC against anvil for real contract execution. Intended for v2 and named in the
  original design sketch, but there is no demand for it yet; v1 ships the query direction
  only. Recorded here so it is understood as deferred, not rejected.
- **Domain-agnostic abstraction** — v1 depends directly on `cfmm-vol-markets-spec` and
  knows about `VolOrder`. Extracting a reusable core is deferred until a second demand
  actually exists, per an explicit "cfmm-first, generalize later" decision.
- **Owning the transport decision for cfmm-vol-markets** — that repo's ROADMAP,
  REQUIREMENTS and PROJECT edits belong to the agent that owns them, through its own
  two-step review. This project does not edit the consumer's planning tree.
- **Non-Haskell broker process** — a Rust/Go/TS intermediary was considered and rejected;
  it adds a third language and a third build to the CI runner without a compensating
  benefit.
- **Being a competing candidate to `vm.ffi`** — the transport question is settled (see Key
  Decisions). The bridge is not built to win an evaluation.

## Context

**The consumer, and what it needs.** `cfmm-vol-markets` is running an 11-phase milestone
called "Haskell↔Plank Differential Conformance". Its core value: *a fuzzed input that
produces a different `tokenId` in Haskell than in Plank must fail the build.* Three of its
phases are precisely this project's delivery surface:

| Their phase | Owns | Their reqs |
|---|---|---|
| 5 — RPC Design & Protocol Skeleton | transport + responsibility split + payload-free skeleton | RPC-01/02/03 |
| 6 — Haskell Spec Oracle | spec decodes wire bytes, answers out-of-process | SPEC-01/02/03 |
| 7 — Solidity↔Spec Transport | `SpecHelper` gets the answer; rejection ≠ transport failure | XPORT-01/02 |

Their RPC-01/02/03 are this project's delivery contract. Their XPORT-02 — the three-way
outcome that must never be conflated — is a v1 design input, not an integration concern.

**A decision was taken out of their hands, deliberately.** Their Phase 5 was written as a
dedicated *interactive design phase* owning the `vm.ffi`-vs-JSON-RPC verdict, and their
STATE.md lists it under "Open by design — owned by phase planning, do not pre-resolve."
Their roadmap says: *"Do not short-circuit it by picking a transport and moving on."* The
user was shown this tension explicitly and chose JSON-RPC anyway, restructuring their
Phase 5 from *build the transport* into *consume this submodule*. That is a legitimate
call, but it means their planning tree is currently out of date with reality, and the
correction is theirs to make.

**Two agents, one ecosystem.** The agent owning the `cfmm-vol-markets` planning tree
(peer `1pnlxhor`) has been sent the full decision set and four questions that remain
genuinely theirs. It had not replied at the time this document was written. A third agent
(`emot4rxl`) is forking the GSD framework in `~/apps/custom_gsd` and gathering modification
demands from the same cfmm-vol-markets agent — a possible source of planning-layout churn
worth watching, not a dependency.

**Wire format is not ours to choose.** The `VolOrder(T)` serialization — Shock-style tagged
versus per-variant layout — is open and owned by the consumer's Phase 4. Pre-empting it
would repeat exactly the mistake just flagged about the transport. Codec design consumes
their decision rather than anticipating it.

## Constraints

- **Tech stack**: Haskell (library + JSON-RPC server executable) — the spec is Haskell and
  the bridge links it as a dependency, so a same-language boundary avoids a third build.
- **Dependencies**: depends on `d2p-finance/cfmm-vol-markets-spec`. The consumer therefore
  reaches that spec by two paths (its own `spec/` submodule and transitively through the
  bridge) — a topology that needs confirming against its build.
- **Compatibility**: must be reachable from Foundry's `vm.rpc(alias, method, params)`, which
  constrains the protocol to JSON-RPC methods Foundry can forward.
- **Distribution**: `d2p-finance/evm-spec-bridge` canonical, `JMSBPP/evm-spec-bridge` fork,
  changes reach canonical only via PR — the standing rule for every repo in this ecosystem.
- **Process**: every pre-commit artifact (spec, plan, sub-plan, roadmap, design doc) passes
  a parallel two-step review — Reality Checker plus one matched specialist — before it is
  written, committed, or executed.
- **Rejection travels in `result`, never in the JSON-RPC `error` field.** Foundry collapses
  connection-refused, HTTP non-200, malformed body, the 45s timeout *and* a JSON-RPC `error`
  object into a single untyped `CheatcodeError(string)` revert. A rejection sent as an
  `error` is indistinguishable from the server being down — the exact conflation this
  project exists to prevent. `error` is reserved for unknown-method/bad-params, which should
  revert. This is forced by Foundry's source, not a style preference, and cannot be
  retrofitted cheaply.
- **The result is `"0x" <> hex(abi_encode(...))`, always.** `vm.rpc` coerces the JSON result
  through `json_value_to_token`: objects become tuples in alphabetical key order, numbers
  round-trip through `f64`, `null` becomes 32 zero bytes. The only byte-exact branch is an
  even-nibble hex string.
- **`vm.rpcJson` is unavailable.** Merged 2026-06-05, present only from Foundry v1.8.0
  (published 2026-08-27); the consumer is on 1.5.1-stable. Target `vm.rpc`.
- **Handlers must be time-bounded.** `vm.rpc` hardcodes a 45s timeout, 8 retries and 800ms
  backoff via `ProviderBuilder::new`; `foundry.toml`'s `eth_rpc_timeout` and per-endpoint
  `retries` do NOT reach it. Retries fire only on 429/503, so connection-refused fails fast —
  but a hung handler costs the consumer 45s per call with no client-side remedy.
- **Every handler needs a Haskell exception firewall** (`try . evaluate . force`). Laziness
  lets a thunk throw during response serialization *after* the outcome was classified as
  success, killing the connection — so a genuine spec bug presents as transport failure.
- **CI**: this repo runs its own gate on hosted runners. This is a deliberate deviation from
  the consumer's "no local compilation, CI is the sole gate, dependencies left uninitialized"
  convention, chosen so a greenfield codebase can iterate.

**Risks carried, not resolved:**

- **`try`/`catch` on a cheatcode is the lowest-confidence remaining assumption.** The
  three-outcome distinction depends on converting a cheatcode revert into a value. Whether
  Solidity `try`/`catch` works against the cheatcode address (`extcodesize`) is unverified;
  the low-level `address(vm).call` form sidesteps it. This is the first thing the transport
  spike must prove.
- **Hosted CI has been blocked by GitHub billing** elsewhere in this ecosystem
  (`tao-plank-vault`). The chosen gate strategy assumes hosted runners work.
- **GHC/cabal on the consumer's self-hosted runner is unverified.** Confirmed on the dev
  machine (GHC 9.10.3, cabal 3.16.1.0), not on the runner. A long-lived service is strictly
  more demanding than a binary: the runner must build *and run* a Haskell process, with
  service-ready/test-start races, port collisions and teardown. Choosing hosted CI here
  defers this rather than retiring it.
- **Silent false-green is the characteristic failure mode of this project.** Several
  independent paths produce a green differential test that means nothing: the bridge built
  against a different spec commit than the consumer believes; a leaked server process on the
  consumer's *persistent* self-hosted runner answering a later run from an old commit; a
  decode failure defaulting to a pass; an unreachable oracle read as agreement. Every one is
  invisible in a passing build. The compile-time `specCommit` assertion and the tagged
  three-outcome struct exist specifically to convert these into hard reds.

**Resolved since initialization:**

- **`vm.rpc` arbitrary-method forwarding is VERIFIED from Foundry source.** `rpc_result`
  builds a provider and calls `raw_request` with no allowlist, no `eth_*` filter and no node
  handshake; the 3-arg form is `apply`, not `apply_stateful`, so it needs no fork, no anvil
  and no `[rpc_endpoints]` entry. `vm.rpc("http://127.0.0.1:PORT", "spec_health", "[]")`
  works in plain `forge test`. The transport decision stands.

- The consumer's planning agent put the Phase 5 override to its own user verbatim — including
  that it contradicted their standing "do not pre-resolve" instruction — and had it confirmed
  before acting. Their ROADMAP/REQUIREMENTS/PROJECT edits are in progress on their side.
- Their CI-01/CI-02 escalate from a Phase 11 concern to a **prerequisite for their Phase 5**:
  with a service transport, their payload-free skeleton cannot be gate-observable unless the
  runner can build and run the process.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Transport is JSON-RPC over `vm.rpc`, not `vm.ffi` | A warm service avoids per-case process spawn and generalizes to the whole spec surface. Taken by the user at this project's initialization, overriding the consumer's Phase 5 ownership after the tension was surfaced | — Pending |
| Enter `cfmm-vol-markets` as a submodule; their Phase 5 becomes a phase modification | Their Phase 5 is the reference for what this must deliver, not the phase that builds it. Keeps one implementation instead of two | — Pending |
| v1 is the query direction only; spec-drives-EVM deferred to v2 | It is what the only existing demand needs. The drive direction has no consumer yet | — Pending |
| Haskell library + JSON-RPC server exe (not a non-Haskell broker) | Same language as the spec it links; avoids a third build on the runner | — Pending |
| Bridge depends on `cfmm-vol-markets-spec` (not the reverse) | Simplest thing that works for the first demand; accepts that the bridge knows `VolOrder` and that decoupling is later work | — Pending |
| Protocol schema as Haskell types, Solidity interface generated from it | A hand-maintained wire contract on the Forge side drifts silently; generation turns drift into a compile error | — Pending |
| cfmm-first; generalize only on a second demand | Abstractions built for hypothetical consumers fit none of them | — Pending |
| Own CI gate on hosted runners | Lets a greenfield codebase iterate, unlike the consumer's no-local-build convention. Defers the self-hosted-runner toolchain question | — Pending |
| `d2p-finance` canonical, `JMSBPP` fork, PR-only | Standing ecosystem rule; no repo is exempt | — Pending |
| Do not edit the consumer's planning tree | Their ROADMAP/REQUIREMENTS/PROJECT changes go through their own two-step review. Cross-agent edits bypass that gate | — Pending |
| RPC-02 split: spec owns guard evaluation; bridge owns error classification and protocol well-formedness; codec generated from one schema | The test process owns no semantics — anything it evaluates is a re-implementation of the spec, which is the exact failure the consumer's milestone exists to kill. Domain validation IS guard evaluation and must not migrate into the bridge disguised as validation. Only the transport layer can tell "the spec said no" from "the service died" | — Pending |
| Generated Solidity artifact is a library returning a tagged struct | A sentinel collides with legitimate values the moment the spec can return one; a custom error makes spec-rejection indistinguishable from a genuine revert, forces try/catch, and destroys the guard identity the consumer's Phase 9 needs. Only the tagged struct carries the discriminant explicitly | — Pending |
| The RPC result is one hex-encoded ABI blob, not a JSON object | Keeps the Solidity interface stable regardless of how `vm.rpc` surfaces results, and avoids leaning on `vm.parseJson` for anything load-bearing | — Pending |
| The bridge is the single authority on the spec version; the consumer drops its direct `spec/` pin | One path beats two paths plus a checker. Agreed with the consumer's planning agent | — Pending |
| `specCommit` is stamped at compile time and asserted by the consumer's test — mandatory regardless of topology | A pin describes the tree, not the process answering the test. A stale build, a cached artifact, or a leaked process on a persistent runner can all answer from a different commit than the pin claims. Compile-time stamping is the only version claim that cannot lie | — Pending |
| The wiring probe collapses into the health method | One mechanism, no second thing to drift. Unreachable surfaces as transport-failure from the same call, so the consumer's Phase 1 skip predicate is the one Phase 7 keeps | — Pending |
| **OPEN — `VolOrder(T)` wire format** | Shock-style tagged vs per-variant, owned by the consumer's Phase 4. The codec consumes their decision rather than anticipating it | — Pending |

---
*Last updated: 2026-08-27 after initialization*
