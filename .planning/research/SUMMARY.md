# Project Research Summary

**Project:** evm-spec-bridge
**Domain:** Executable-specification-as-test-oracle — a warm Haskell JSON-RPC service consumed by Foundry `forge test` via `vm.rpc`, with the Solidity interface generated from the Haskell protocol types
**Researched:** 2026-08-27
**Confidence:** MEDIUM-HIGH overall (HIGH on the transport mechanics, which are both source-read and empirically measured; MEDIUM on CI/lifecycle; LOW on anything downstream of the consumer's still-open `VolOrder(T)` decision)

---

## Executive Summary

This is a **cross-language differential-testing oracle**, and the closest thing to prior art that actually exists is `kore-rpc` + `pyk` (K framework): a warm Haskell process exposing a formal semantics over JSON-RPC, driven by a client in another language. That precedent independently arrived at the same central design this project is forced into — **the outcome tag rides inside the successful `result`, and the JSON-RPC `error` channel is reserved for "the oracle did not answer."** The rest of the landscape (EELS/`execution-spec-tests`, Certora, Kontrol/halmos/hevm, `beacon-fuzz`) is either offline-fixture generation or reinterpretation, neither of which is what this project is. There is no prior art for `vm.rpc` against a non-Ethereum JSON-RPC service; that path is genuinely novel, and it is now **verified from Foundry source and reproduced against a live stub oracle**: `rpc_result` calls `provider.raw_request(method, params)` with no allowlist, no `eth_*` filter, no node handshake, and the 3-arg overload is stateless (`apply`, not `apply_stateful`), so it needs no fork, no anvil and no `[rpc_endpoints]` entry.

The recommended build is small and deliberately boring: **GHC 9.10.3 + cabal + `warp`/`wai` + `aeson-2.2.5.0`, a hand-rolled ~150-line JSON-RPC envelope, an explicit Solidity-type IR with a pure renderer, and `hspec`/`QuickCheck`/`hspec-golden`.** Every JSON-RPC library on Hackage was evaluated and every one has a disqualifying defect — dead (`json-rpc-server`, 2017), client-only (`jsonrpc-tinyclient`), wrong transport (`json-rpc`, `jsonrpc-conduit`), or unmaintained-and-drags-servant (`servant-jsonrpc`, last touched 2024-09-28). Decisively, **every library owns the `error` channel**, which is the one abstraction this project must control. No Haskell-to-Solidity code generator exists in any ecosystem; `aeson-typescript` is the structural precedent to read before writing one. The load-bearing wire decision is that **every method returns a single `"0x" <> hex(abi_encode(tag, version, body))` string** — the only branch of Foundry's `json_value_to_token` coercion that is total and value-independent.

The characteristic failure mode is **silent false-green**, and the research found more paths to it than PROJECT.md listed. Measured, on `forge 1.5.1-stable`: a wedged oracle costs 45 seconds per fuzz case and *the test still passes* if the call site ignores the return value (3.2 hours of green CI at the default `fuzz.runs = 256`); a JSON object result decodes "successfully" as `bytes` of a bogus length — no revert, pure garbage compared against the contract's answer; a `null` result (which is what aeson emits for a `Maybe`) becomes 32 zero bytes with `success == true`, so the natural Haskell idiom for "guard violated" produces a successful RPC returning zero. Mitigation is structural, not disciplinary: a three-constructor Solidity `Outcome` enum reached only through a generated call site that cannot return without producing a verdict; `Maybe` banned from protocol types with a property test asserting the encoder never emits `null`; a per-request server-side deadline of 2-5 s well under Foundry's hardcoded 45 s; a `try . evaluate . force` firewall in every handler; and a compile-time spec-commit stamp asserted over the wire, because a pin describes the tree, not the process answering the test.

---

## Convergent Findings — the strongest signal in the research set

Four dimensions researched independently, from different angles (Hackage/library survey, prior-art landscape, Foundry source architecture, and live empirical probes). Where they converged, the finding should be treated as settled and used as a roadmap constraint, not re-litigated during planning.

| # | Finding | Reached independently by | Why the convergence matters |
|---|---|---|---|
| **C1** | **The JSON-RPC `error` channel conflates spec rejection with transport failure.** Rejection MUST ride in `result` as a tagged union; `error` is reserved for unknown-method / bad-params / internal fault | STACK (Finding 2, from `fork.rs`) - FEATURES (F3+F4+F5, plus AF-1 as an explicit anti-feature) - ARCHITECTURE (Constraint 3 + Anti-Pattern 1) - PITFALLS (**Pitfall 1, MEASURED** — all four failure classes return selector `0xeeaa9e6f`, differing only in prose) | Four independent derivations, **plus external precedent**: `kore-rpc` put its `reason` tag inside the success payload for the same reason without knowing about this project. This is the project's Core Value made mechanical. It is also the one thing that **cannot be retrofitted cheaply** — changing the outcome channel changes every response shape and every consumer decoder |
| **C2** | **The result must be a single hex-ABI blob**, `"0x" <> hex(abi_encode(...))`, never a JSON object, number, bare string or `null` | ARCHITECTURE (Constraint 1 — the only byte-exact, total branch of `json_value_to_token`) - PITFALLS (**Pitfalls 2, 3, 5, all MEASURED** — magnitude-dependent `string`/`uint256` coercion, alphabetical tuple ordering, silent-garbage `bytes` decode, `null` to zero) - FEATURES (TS-14 hex-string encoding; F7) | Two source-reads and four live measurements agree. **STACK dissents and is the outlier** — see Disagreements. The measured evidence wins |
| **C3** | **The spec commit SHA must be stamped at compile time and asserted over the wire.** A pin describes the tree; only a compile-time stamp describes the process answering the test | PROJECT.md (existing requirement) - ARCHITECTURE (Pattern 3 protocol-version handshake + Anti-Pattern 6 "trusting codegen alone" + the submodule-diamond analysis) - PITFALLS (Pitfall 8 schema digest; **Pitfall 13** — the diamond produces false divergence *or* false agreement) - FEATURES (TS-12, "warm processes go stale") | Three researchers independently identified that codegen's compile-time guarantee **has a hole**: it couples the `.sol` to the registry *at a commit*, and nothing compile-time-checks that the running server binary is that commit. A stale background process on a persistent runner defeats it entirely. Two extra bytes per response and one `require` closes it |
| **C4** | **Harness owns the process lifecycle, with readiness polling — never `sleep`, never `setUp()`/`vm.ffi`** | FEATURES (TS-10; `pyk`'s `KoreServer` context-manager precedent, polling `ConnectionRefusedError` on a 0.1 s loop) - ARCHITECTURE (Pattern 4 + the concrete finding that `setUp()` runs before *every test function* and there is no `tearDown`) - PITFALLS (Pitfall 11 — five distinct failure modes, each a flaky red or a silent green) | Independent agreement including an external implementation (`pyk`) that already made and documented these choices |
| **C5** | **Handlers must be pure, stateless, forced to NF under a catch, and time-bounded** | FEATURES (TS-7, TS-8, TS-9; AF-3 sessions as anti-feature) - ARCHITECTURE (Anti-Pattern 8; alloy retries on 429/503 so a request can legitimately be replayed) - PITFALLS (Pitfalls 6, 9, 10 — bottoms escape as HTTP 500 i.e. *transport failure*, space leaks appear exactly at fuzz scale) - PROJECT.md (the `try . evaluate . force` constraint) | Laziness is the Haskell-specific trap nobody outside this research set would flag: a thunk throwing during serialization, *after* the outcome was classified `Ok`, files a genuine spec bug under "infrastructure" |
| **C6** | **Phase 1 must be a throwaway transport spike, before any Haskell of consequence** | STACK ("everything else in this stack is contingent on that returning") - ARCHITECTURE (build order 0 to 1, "only a green test proves it") - FEATURES (gaps section 7: the `try`/`catch` mechanic "is the single mechanic the Core Value rests on and it should be proven by an end-to-end spike before any other work") - PITFALLS (the whole Phase-1 column of the pitfall-to-phase map) | Unanimous, and it aligns with PROJECT.md's own lowest-confidence carried risk |

---

## Disagreements and Contradictions — not smoothed over

### D1 — `vm.rpcJson` vs `vm.rpc`: STACK is wrong, and it is wrong at HIGH confidence

STACK's headline recommendation table says **"Foundry cheatcode: `vm.rpcJson`, not `vm.rpc` — HIGH"**, and its "What NOT to Use" table lists `vm.rpc` as a thing to avoid. Its suggested Phase-1 spike is written against `vm.rpcJson`.

This is refuted by two other dimensions:

- ARCHITECTURE grepped `cheatcodes.json` at tags: `rpcJson` absent in v1.6.0 and v1.7.0, present only from **v1.8.0, published 2026-08-27 — the same day as this research**. The local `forge` is `1.5.1-stable` and the checked-out forge-std `Vm.sol` has no `rpcJson` declaration.
- PITFALLS **measured** the call: `[Revert] unknown cheatcode with selector 0x273b74f8` — itself wrapped in `CheatcodeError(string)`, i.e. **indistinguishable from a transport failure by selector**. Pitfall 4 in its entirety.

**Root cause of the error, worth internalising:** STACK read Foundry's `master` and the published cheatcode reference at getfoundry.sh, both of which track master, not the shipped release. Researching the docs and researching the installed binary gave different answers, and the difference was invisible until someone ran it.

**Resolution: target `vm.rpc` with the hex-ABI envelope.** It works on every Foundry that has ever had `vm.rpc`, costs nothing extra, and the protocol wants a versioned binary envelope anyway. PROJECT.md's constraint already says this; the roadmap should treat STACK's Transport-Constraint Findings 1 and 4 as **superseded**, while its library/version/CI findings remain sound.

### D2 — Retry behaviour on a down server: STACK overstates the cost

STACK Finding 3 concludes "a down server can cost minutes of CI time per test case" from `max_retry: 8` + `initial_backoff: 800ms`. ARCHITECTURE read alloy's `TransportErrorKind::is_retry_err` and found retries fire **only** on HTTP 429, HTTP 503, `MissingBatchResponse` and `BackendGone` — **connection-refused is not retried and fails fast**. PITFALLS measured exactly that (a closed port errors immediately). PROJECT.md already records the corrected version.

**Resolution:** ARCHITECTURE + PITFALLS win. Down-server feedback is fast; the *slow* failure is the 45 s hang of an accepting-but-not-responding server (Pitfall 6), which is a different and more dangerous thing.

### D3 — Hand-rolled envelope vs the architecture's component seam: **compatible, in fact complementary**

The emphasis flagged this as a possible conflict. It is not one. STACK recommends writing the JSON-RPC 2.0 envelope by hand (~150 lines: `Request`, `Response`, `ErrorObject`, `id`/`jsonrpc` handling, batch rejection). ARCHITECTURE proposes a `jsonrpc-codec` library component sitting between `server-transport` and `method-registry`, with responsibility "JSON-RPC 2.0 request parse / response build."

**`jsonrpc-codec` is precisely where the hand-rolled envelope lives.** The seam is a cabal component boundary; the envelope is its implementation. They reinforce each other twice over:

1. STACK's own contingency analysis says that if the transport spike fails and the project falls back to `vm.ffi` over stdio, "because the JSON-RPC envelope is hand-rolled and transport-agnostic, that swap is contained" — which is exactly the property ARCHITECTURE's transport-to-codec seam is designed to give.
2. ARCHITECTURE's component table marks `jsonrpc-codec` as knowing nothing about cfmm and nothing about HTTP. A library (`servant-jsonrpc`) would couple the envelope to HTTP *and* seize the `error` channel, breaking both the seam and C1.

One small note for the planner: STACK suggests deriving the envelope's aeson instances generically, while ARCHITECTURE's table says "Aeson + derived instances" for `jsonrpc-codec` but STACK's JSON section argues hand-written codecs for **wire-contract** types. Reconcile as: **hand-written for anything the Solidity generator must agree with; `Generic` for the JSON-RPC envelope's own plumbing fields and for internal/diagnostic types.** The envelope is not part of the generated Solidity contract, so generic deriving there is safe.

### D4 — Concurrency: table stakes or non-bottleneck?

FEATURES makes concurrency-safe handling a MEDIUM-complexity table stake (TS-6), citing `forge test -j` defaulting to logical cores. ARCHITECTURE lists concurrency under "Non-bottleneck — do not build a connection-pooling or worker-queue architecture for load that will not arrive," since `vm.rpc` is synchronous per thread.

**Both are right and the resolution is free:** requests *are* concurrent across test contracts, but purity (C5) delivers thread-safety with no locking, no pooling and no queue. The actionable items are narrow — `-threaded -rtsopts "-with-rtsopts=-N"`, no `MVar`/`IORef` in the answer path, non-blocking logging — plus the soak test PITFALLS specifies (at least 5,000 requests, identical-input determinism, order-independence, bounded RSS). Do not build worker infrastructure.

### D5 — RPC-02 responsibility split: the architecture doc's assumption contradicts a settled PROJECT.md decision

ARCHITECTURE Open Question 4 states it "assumes the bridge owns wire decode, **guard evaluation**, and error classification," and flags this as an assumption. PROJECT.md's Key Decisions already settles it the other way: *"spec owns guard evaluation; bridge owns error classification and protocol well-formedness,"* with the explicit rationale that *"domain validation IS guard evaluation and must not migrate into the bridge disguised as validation."*

**Resolution: PROJECT.md governs.** The `cfmm-adapter` decodes wire bytes into the spec's own types, calls into the spec, and **maps the spec's guard result** into `Rejected guardId`. It must not re-implement or re-evaluate guards. This narrows Phase 6 relative to what ARCHITECTURE sized. The roadmapper should treat ARCHITECTURE's "Phases 2 and 6 shrink substantially if the split lands on dumb transport" as partially already true.

### D6 — Hosted-only CI: PITFALLS directly challenges a Key Decision

PROJECT.md decided hosted runners, to let a greenfield codebase iterate and to defer the self-hosted GHC question. PITFALLS 11 argues this does not merely *defer* the risk — **it makes this repo's CI structurally incapable of detecting the zombie-process, port-collision and stale-server failure class**, because hosted runners are ephemeral and hide it permanently. That class is precisely what will bite the consumer's *persistent* self-hosted runner. PITFALLS 12 additionally calls the deferral "the single largest schedule risk in the plan" and prices a throwaway probe job at ten minutes.

**Not resolved by research.** Recorded as a live tension for the roadmapper: recommendation is to keep hosted CI for Phases 0-4 and add at least one self-hosted-shaped job (or a container mimicking a persistent runner) **before** consumer integration, plus a throwaway GHC-on-the-runner probe as early as Phase 0.

---

## Provenance: what is measured, what is source-read, what is judgement

The roadmap must not treat these as one epistemic class.

| Class | What it covers | How to treat it |
|---|---|---|
| **[MEASURED] — `forge 1.5.1-stable`, commit `b0a9dd9`, solc 0.8.34** | Three-way outcome flattening onto selector `0xeeaa9e6f`; alphabetical tuple ordering; magnitude-dependent `string`/`uint256` coercion; `null` to 32 zero bytes; typed-interface revert vs silent-garbage decode; `vm.rpcJson` absent; 45.00 s hang **with a passing test**; connection-refused fails fast | Facts. Do not re-derive. **But version-scoped — see below** |
| **[SOURCE] — Foundry `master` + alloy `main`** | `rpc_result` has no allowlist and no handshake; 3-arg form is stateless `apply`; `rpc_endpoint` accepts any `http*` string; `json_value_to_token` called with `defs = None`; `REQUEST_TIMEOUT = 45s`, `max_retry: 8`, `initial_backoff: 800`; `is_retry_err` list; `guess_local_url` = `localhost`/`127.0.0.1`/`::1` only; `CheatcodeError(string)` encoding; `rpcJson` version matrix | Reliable, but **describes master, not the shipped binary**. D1 is exactly what happens when this distinction is dropped |
| **[VERIFIED-LIVE] — Hackage / Stackage / GitHub API, 2026-08-27** | Package versions, upload timestamps, dependency lists, `tested-with` and `base` bounds; LTS 24.56 = GHC 9.10.3 + aeson 2.2.5.0; `ubuntu-24.04` preinstalls GHC 9.14.1 / cabal 3.18.1.0; `haskell-actions/setup` v2.11.0 | Reliable. The strongest part of STACK |
| **[JUDGEMENT]** | Hand-roll vs depend on `jsonrpc-0.2.0.0`; hspec over tasty; QuickCheck over hedgehog; IR+renderer over TemplateHaskell; cabal over stack; the suggested phase structure; the MVP / v1.x split | Opinionated recommendations. Reversible; do not spend planning time defending them |
| **[UNMEASURED ESTIMATE]** | All CI build times (8-15 min cold, 1-3 min warm, 1-3 min ghcup install) | Explicitly labelled LOW by the researcher. **Record actuals in the first CI run** |

### Version-scoping — the flag the roadmapper most needs

**Every MEASURED finding is specific to `forge 1.5.1-stable`, and the consumer's pinned Foundry version is not confirmed anywhere in the research set.** PROJECT.md asserts the consumer is on 1.5.1-stable; that assertion is unverified against the consumer's actual `foundry.toml` / lockfile.

This is not cosmetic. **`master` and `1.5.1-stable` disagree on the return-path shape:** master wraps the coerced payload as `DynSolValue::Bytes(payload).abi_encode()` (so Solidity does `abi.decode(ret, (bytes))` then decodes the envelope), while 1.5.1 does **not** wrap it. ARCHITECTURE's `SpecOracle.sol` sketch is written against the master shape; PITFALLS measured the 1.5.1 shape. **The Solidity decode path is a function of the consumer's pinned version.** Additionally, v1.8.0 shipped on 2026-08-27, so a consumer who upgrades gains `rpcJson` and may change coercion behaviour.

**Action for the roadmap:** confirming the consumer's exact pinned `forge --version` is a **Phase 1 blocking input**, not a Phase 7 integration detail. Phase 1 must run its probes against *that* version, pin it in this repo's `foundry.toml`, record it in the generated Solidity header comment, and add a Foundry-coercion conformance fixture to CI so a toolchain bump goes red rather than silently reclassifying outcomes.

---

## Key Findings

### Recommended Stack

Minimal, boring, and chosen against two explicit criteria: **build weight** (the consumer's runner toolchain is unverified) and **control of the `error` channel** (C1). No framework, no library that owns an abstraction this project must own. The full Hackage JSON-RPC survey concluded that hand-rolling ~150 lines of envelope beats every available package; `jsonrpc-0.2.0.0` (3 deps, uploaded 2026-02-16, transport-agnostic) is the design reference to read first and a defensible dependency if its API leaves the `result` field under your control — but this decision is small, reversible, and must not block the transport spike.

**Core technologies:**
- **GHC 9.10.3 + cabal-install 3.18.1.0** — anchor of Stackage LTS 24.56, so maximal library compatibility, and the version most likely to already exist on an unverified self-hosted runner. **Do not use the preinstalled GHC 9.14.1** on `ubuntu-24.04`: `base-4.22` exceeds `jsonrpc`'s bound and servant's tested range, trading correctness for about two minutes
- **`warp` 3.4.15 + `wai` 3.2.5 + `http-types` 0.12.6** — a JSON-RPC server has exactly one HTTP route (`POST /`); dispatch is on the JSON `method` field, so a router is the one thing frameworks give you and the one thing this does not need. Every alternative (`servant-server`, `scotty`) is warp plus more. `setInstallShutdownHandler` / `setGracefulShutdownTimeout` give the deterministic SIGTERM handling the warm-service requirement needs
- **`aeson-2.2.5.0` — pinned, not latest.** Hackage's latest is 2.3.1.0, but LTS 24.56 *and* nightly-2026-08-26 both still ship 2.2.5.0, and `jsonrpc`/`servant-jsonrpc`/`deriving-aeson`/`scotty` all bound below 2.3. Hand-written codecs for wire types (the generator must agree with them, and the wire format is the consumer's to choose); `Generic` for internal and diagnostic types
- **Explicit `SolType` IR + pure renderer for codegen** — **no Haskell-to-Solidity generator exists anywhere** (HIGH confidence on the negative). `aeson-typescript` is the structural precedent; `web3-solidity` is the opposite direction and caps GHC at 9.10. An IR is a *value*, so it is QuickCheck-able and golden-testable, and it is the only place Solidity-specific knowledge (bit widths, `memory`/`calldata`, ABI packing) can live — a generic traversal of `VolOrder` cannot know a field should be `uint128`
- **`hspec` 2.11.17 + `QuickCheck` 2.18.0.0 + `hspec-golden` 0.2.2.0 + `hspec-wai` 0.12.1** — one dependency instead of tasty's four; `hspec-wai` exercises the `Application` without binding a socket; `hspec-golden` is the mechanism that makes "drift becomes a compile error" real
- **`cabal.project.freeze` — non-negotiable.** For a spec oracle, reproducibility is the product, not a convenience

### Expected Features

**Must have (table stakes — absent means unusable, or worse, silently wrong):**
- **Three-outcome result algebra as a Haskell sum type** (`SpecOk a | SpecRejected Guard | TransportFailed Reason`) with no partial function able to produce one from another. Non-`Maybe`, non-`Either String`; `Guard` a **closed enum**, not `String`
- **Rejection rides in the JSON-RPC `result`, never in `error`** (C1) — a constraint, not code, and the one thing that cannot be retrofitted
- **Generated Solidity transport-failure catcher** — the `vm.rpc` call behind a low-level `address(vm).call` (or an external call boundary), converting the cheatcode revert into a value. This must be *shipped generated*, not left to the consumer; it is the one component whose drift produces a false **pass** rather than a compile error
- **Payload-free health method returning the exact envelope shape a domain method returns**, carrying the spec commit SHA and protocol version — plus fixture methods that deliberately produce a rejection and a protocol error, so the Solidity three-way classifier is exercised in CI without any domain logic
- **Warm long-lived server, one per `forge test` run**, harness-owned lifecycle with readiness polling and always-run teardown
- **Pure, stateless, concurrency-safe handling** with a `try . evaluate . force` exception firewall and a per-request server-side deadline (2-5 s, well under Foundry's 45 s)
- **Hex-string wire encoding for all quantities, strict decode** — reject unknown fields, out-of-range, non-canonical; a decode failure is a typed protocol fault that fails the test
- **Numeric error taxonomy** for the `error` channel (kore-rpc shape: small positive integers for domain-protocol faults, -32000 to -32099 for server faults, standard codes for JSON-RPC-level faults)
- **JSON-RPC `id` correlation and shape validation**; namespace every method `spec_*` and return -32601 loudly for everything else

**Should have (the actual differentiators):**
- **Solidity interface + params encoder + response decoder generated from the Haskell protocol types.** The stated differentiator, with in-ecosystem precedent (Foundry generates its own `Vm` interface from one `sol!` block — and its drift error message is a live demonstration of what generating only one side costs). **Must include the params encoder**: `vm.rpc` takes `params` as a JSON *string* the test builds, so a generated interface with hand-built params has moved the drift, not removed it
- **CI drift gate** — regenerate and `git diff --exit-code`. Cheap, and it is what makes generation real rather than aspirational
- **Typed guard identity in rejections** — distinguishes "rejected by the tick-spacing guard" from "rejected for some reason," which is what tells a correct rejection from a decoder bug
- **Input digest echoed in the response** — three lines now, a protocol change later; closes the whole misrouting/stale-response/wrong-server class that a warm shared process creates

**Defer (v1.x / v2+):**
- Full replay transcript, counterexample bundle, structured observability + guard histogram, and the **vacuity guard / oracle-call accounting** (assert the oracle was consulted N times and produced at least one `ok`; modelled on Certora's `--rule_sanity`). This is the direct antidote to "a green light that means nothing" and should be pulled forward if it is cheap
- **Golden-vector export (`fill`/`consume` shape)** — directly de-risks the self-hosted-GHC question by letting a runner without a Haskell toolchain consume vectors. Strong v1.x candidate
- `vm.rpcJson` decode path — revisit only if the consumer moves to Foundry v1.8.0 or later, and gate it behind a **capability probe** in CI, never a version-string comparison
- `spec_batch` — fuzzing gives one input per run, so batch size is one today
- Spec-drives-EVM direction; domain-agnostic core

**Explicit anti-features (build none of these):** rejection as a JSON-RPC `error`; a general-purpose `eth_*` node proxy; mutable session state; lenient decoding; a skip/degrade path on unreachable oracle (`vm.skip` on transport failure is the exact failure the project exists to prevent); routing rejections through `vm.assume` (burns the shared 65,536 reject budget and makes rejections invisible); client-side retries on loopback; a persistent on-disk answer cache; per-case server spawn; auth/TLS/multi-tenancy; WebSockets; hand-written Solidity mirrors.

### Architecture Approach

A layered Haskell service with **one domain seam enforced by cabal, not by discipline**. Everything above the seam (`protocol`, `abi-codec`, `jsonrpc-codec`, `method-registry`, `server-transport`, `solidity-codegen`) must not list `cfmm-vol-markets-spec` in its `build-depends`, so an accidental domain import is a compile error. The executable is the composition root. That single cabal stanza boundary *is* the entire "generalize later" investment — it costs nothing now and is genuinely painful to retrofit, which is what makes it compatible with PROJECT.md's "cfmm-first" decision rather than a violation of it.

**Major components:**
1. **`protocol`** — the `Outcome` ADT, `ProtocolVersion`, tag constants, envelope layout. Pure types, no deps, no domain knowledge
2. **`abi-codec`** — Solidity-ABI encode/decode in Haskell plus hex wrapping. The encode direction is all v1 strictly needs; decode is required for `VolOrder` bytes
3. **`jsonrpc-codec`** — the hand-rolled JSON-RPC 2.0 envelope (D3). Transport-agnostic by construction, which is what makes a `vm.ffi` fallback containable
4. **`method-registry`** — typed `Method` values carrying wire name, param/result types, Solidity signature and handler. **The single source of truth, and the one artifact codegen reads.** Adding a method is one value
5. **`server-transport`** — warp/wai, binds `127.0.0.1` (never `0.0.0.0` — alloy's `guess_local_url` only treats `localhost`/`127.0.0.1`/`::1` as local, and only local URLs get `no_proxy`, so a proxied runner would route loopback traffic off-box), **always HTTP 200**, registry miss becomes a JSON-RPC `error`
6. **`solidity-codegen` (exe)** — deterministic traversal of the registry emitting `ISpecOracle.sol` + `PROTOCOL_VERSION`. Sorted output, no timestamps/SHAs in the file, fail loudly on an unmapped type
7. **`cfmm-adapter`** — the only component that knows about cfmm. Decodes `VolOrder(T)` wire bytes into the spec's types, calls `volOrderToTokenId`, maps the spec's guard result to `Rejected guardId` (it does **not** evaluate guards — see D5)
8. **`SpecOracle.sol`** (hand-written, ~80 lines) + **`ISpecOracle.sol`** (generated, **committed**) — the generated `.sol` must be checked in, because the consumer compiles Solidity with no Haskell toolchain

**Submodule topology — a concrete recommendation that resolves a real hazard:** do **not** vendor `cfmm-vol-markets-spec` as a git submodule of the bridge. Depend on it via `cabal.project`'s `source-repository-package` pinned to a full 40-char SHA, overridable by the consumer's CI writing a `cabal.project.local` that points at *their own* `spec/` checkout. That makes the diamond's version skew impossible by construction for integration builds rather than by vigilance, and it eliminates the recursive `git submodule update --init` failure outright.

### Critical Pitfalls

1. **All three outcomes already arrive on one channel [MEASURED].** JSON-RPC error object, HTTP 500, connection refused and the 45 s timeout all return `success == false` with selector `0xeeaa9e6f`, differing only in an English message produced by three upstreams (`reqwest`, `alloy`, `fmt_err!`) none of which treat it as API surface. **Avoid:** rejection in `result` as a tagged sum; `success == false` means transport failure unconditionally, no string parsing. **Never** build a string-matching classifier over the revert message — a Foundry bump silently reclassifies rejections and the differential test goes green
2. **The JSON-to-ABI coercion is value-dependent [MEASURED].** The same record shape produced `tuple(string,string,string)` for `tokenId = "0"` and `tuple(string,string,uint256)` for `tokenId = "18446744073709551616"` — **the ABI type changed because the number got bigger.** Under fuzzing, `abi.decode` works on some inputs and reverts on others with a bare unmessaged `EvmError: Revert`. **Avoid:** single even-length `0x` hex string carrying a bridge-produced ABI payload — the only total, value-independent coercion branch. (Two encoder traps to test: odd-length hex is silently left-padded with a zero nibble; exactly 39 nibbles after `0x` is a hard "cannot parse as address" error)
3. **`bytes memory b = vm.rpc(...)` can return silent garbage [MEASURED].** A JSON object result decodes "successfully" as `bytes` with a bogus length taken from the tuple's first head word — no revert, no warning, and the differential test compares the contract against nonsense. **Avoid:** the generator emits a low-level `address(vm).call(abi.encodeWithSignature("rpc(string,string,string)", ...))` call site, never the typed `Vm` interface, plus a length assertion
4. **`null` is not a rejection — it is `0`, and `0` may be a legal answer [MEASURED].** `Maybe` is the Haskell reflex for partiality; aeson writes it as `null`; Foundry coerces `null` to 32 zero bytes with `success == true`. Three lossy hops, no compile error at any of them, ending in a green test comparing zero to zero. **Avoid:** ban `Maybe` from protocol types (not from the spec) and add a property test asserting the encoder **never emits `null`** for arbitrary inputs
5. **A wedged oracle costs 45 s per case and the test still passes [MEASURED].** `[PASS] test_hang() (gas: 4012) ... finished in 45.00s` — because the call site ignored the return value. At `fuzz.runs = 256` that is **3.2 hours of green CI**, and on a self-hosted runner with no job timeout it is an indefinitely occupied runner. **Avoid:** a generated call site with no path that returns without producing a verdict or reverting; a 2-5 s server-side deadline; CI `timeout-minutes`; and a **wall-clock budget assertion** — a suite that suddenly takes 40x longer is a wedged oracle even when green
6. **Bottoms escape as HTTP 500, i.e. as transport failure.** The bridge deliberately does not modify the spec's model, so it inherits the spec's `error`/`head`/`fromJust`/incomplete-pattern partiality. The thunk blows up during response encoding, Warp's `defaultOnExceptionResponse` returns a 500, and a guard violation is reported as a broken bridge. **Avoid:** `try (evaluate (force answer))` inside the handler with `NFData` on the result type, catching at least `ErrorCall`, `ArithException`, `PatternMatchFail`, `ArrayException`, mapped to a **typed rejection**; `responseLBS` only, never `responseStream`; `setOnExceptionResponse` emitting a well-formed JSON-RPC error object
7. **Building against a contract two other agents are still negotiating.** The failure mode is not "we build the wrong thing" — it is that **the bridge ships a defensible default and the default becomes the decision by inertia**, repeating exactly the transport-decision tension PROJECT.md flagged as a mistake. **Avoid:** sequence around it, do not guess through it. Everything through the codegen phase is independent of both open decisions (RPC-02 split, `VolOrder(T)` layout). If a placeholder is unavoidable, record it in Key Decisions as `PROVISIONAL — reverts to open if not confirmed by <date>` with a real date, and escalate to the user rather than deciding unilaterally

---

## Implications for Roadmap

Based on the combined research, and reconciled against PROJECT.md's settled Key Decisions.

### Phase 0: Repo skeleton, toolchain, and CI floor
**Rationale:** PROJECT.md carries two unretired infrastructure risks — hosted CI has been billing-blocked elsewhere in this ecosystem, and GHC/cabal on the consumer's self-hosted runner is unverified. PITFALLS calls the latter *"the single largest schedule risk in the plan"* and prices the fix at ten minutes. Retiring both before any design work is sunk is the cheapest risk reduction available.
**Delivers:** cabal project with the component boundaries from ARCHITECTURE (including the empty `adapter-cfmm` stanza, so the seam exists from day one); committed `cabal.project.freeze`; hosted CI building a hello-world exe with the cabal-store cache keyed on `plan.json` + GHC version + spec SHA; **a throwaway probe job that builds and *runs* a trivial Haskell binary on the consumer's self-hosted runner**; recorded actual build times (all current estimates are explicitly unmeasured).
**Uses:** GHC 9.10.3, cabal, `haskell-actions/setup` v2.11.0, `actions/cache` split restore/save.
**Avoids:** Pitfall 12 (cache-that-does-not-cache from mtime invalidation; submodule-driven cache staleness; GHC OOM on an under-provisioned runner).

### Phase 1: Transport spike — throwaway, version-pinned
**Rationale:** Unanimous across all four research dimensions (C6). Source reading says `vm.rpc` forwards arbitrary methods to any endpoint; only a green `forge test` proves it. Deliberately smaller than it wants to be: no registry, no codegen, no domain, no abstraction around an unproven mechanism. **Blocking input: the consumer's exact pinned `forge --version`** — every measured finding is version-scoped and master vs 1.5.1 disagree on the return-path shape.
**Delivers:** a stub warp server returning a hardcoded `"0x" <> hex(abi_encode(tag, version, body))`; one Solidity test calling `vm.rpc` through a low-level `address(vm).call` under `with-spec-server.sh`; **empirical answers to four open questions** — (a) does `try`/`catch` work against the cheatcode address or is the low-level form required (PROJECT.md's own lowest-confidence assumption), (b) does the pinned version wrap the payload as `abi.encode(bytes)` or not, (c) a `vm.rpcJson` capability probe recording it as absent with the version checked, (d) does alloy enforce a response `Content-Type`. Pins the Foundry version in `foundry.toml` and records it for later stamping into the generated header.
**Addresses:** TS-4 (re-scoped from "prove the transport shape" to "prove the transport works at all").
**Avoids:** Pitfall 4; the whole class of discovering-in-Phase-7 what should be known in Phase 1.

### Phase 2: Three-outcome protocol core + Solidity runtime
**Rationale:** This delivers the Core Value with **no domain code involved**, which means the three-outcome guarantee is tested against a rejection you construct rather than one you have to reach through the domain. It is also where C1 and C2 become mechanical, and both are the retrofit-expensive decisions. ARCHITECTURE's note stands: this is the phase that must not be rushed.
**Delivers:** the `Outcome` sum type (closed `Guard` enum, no `Maybe`, `NFData`); the hex-ABI envelope with `PROTOCOL_VERSION`; `abi-codec`; `jsonrpc-codec` (the hand-rolled envelope, D3) with the numeric error taxonomy; `SpecOracle.sol` with a three-constructor enum forcing call sites through a switch; **three fixture methods — ok / deliberate rejection / deliberate protocol error** — plus a health method returning the *same envelope shape* a domain method returns; a test that kills the server mid-suite and asserts the suite goes **red**; a property test that the encoder never emits `null`; boundary-value tests spanning the coercion classes (below and above 2^64, negative, zero, empty, 32-byte).
**Implements:** `protocol`, `abi-codec`, `jsonrpc-codec`, `SpecOracle.sol`.
**Avoids:** Pitfalls 1, 2, 3, 5, 7 — and note that Pitfall 7's fix (health returns the real envelope shape, plus a rejection fixture) is *the cheapest possible insurance against Pitfall 1 regressing*.

### Phase 3: Warm server hardening + harness lifecycle
**Rationale:** The warm service is the entire justification for choosing JSON-RPC over `vm.ffi`, and warmth is exactly what makes cross-case contamination, space leaks and zombie processes possible — failure modes `vm.ffi` would have been immune to by construction. These are invisible at `curl` scale and fatal at fuzz scale.
**Delivers:** `-threaded -rtsopts "-with-rtsopts=-N"`; per-request deadline (2-5 s) returning a *typed* fault, not a dropped connection; the `try . evaluate . force` firewall plus `setOnExceptionResponse`; loopback-only bind as a **required, not defaulted** argument; ephemeral port supplied by the caller and published via env var (`vm.envOr("SPEC_ORACLE_URL", ...)`); `with-spec-server.sh` with bounded readiness polling that checks the PID inside the loop, `trap`-based teardown, always-uploaded server logs, and a post-suite liveness assertion; a **soak test** (at least 5,000 sequential requests plus a concurrent burst, asserting identical-input determinism, order-independence and bounded RSS).
**Addresses:** TS-5, TS-6, TS-7, TS-8, TS-9, TS-10.
**Avoids:** Pitfalls 6, 9, 10, 11; the security items (loopback bind, bounded request body, truncated guard text).

### Phase 4: Method registry + Solidity codegen + drift gate
**Rationale:** Structure is now justified by real methods rather than speculation — ARCHITECTURE is explicit that a registry abstraction in Phase 1 would be speculative structure around an unproven mechanism. This is the phase that delivers PROJECT.md's stated differentiator, and it is the phase with **no prior art anywhere**.
**Delivers:** typed `Method` values (wire name, param/result types, Solidity signature, handler) with the fixture methods migrated onto them; the `SolType` IR + deterministic pure renderer; `ISpecOracle.sol` generated **and committed** with an `AUTOGENERATED — DO NOT EDIT` header and the pinned Foundry version recorded; the generated **params encoder and response decoder**, not just the interface; the generated low-level call site with no unasserted path; `PROTOCOL_VERSION` and a **schema digest** (hash over ordered field names and types) emitted into both sides and returned by health; golden test locally plus `git diff --exit-code` in CI; a **Foundry-coercion conformance fixture** that goes red when the toolchain changes coercion.
**Uses:** `hspec-golden`, `Data.Text` rendering (reach for `prettyprinter` only if nesting gets painful).
**Avoids:** Pitfalls 2 (generator emits the decoder), 3 (generator emits the low-level call site), 8 (stale artifact — including the subtle accelerant that under alphabetical-tuple coercion a *rename* reorders fields with no type change, and the committed `.sol` still compiles).

### Phase 5: Spec dependency wiring + compile-time SHA stamp
**Rationale:** Independent of the wire format, so it can land before the adapter. C3 says this is where the compile-time guarantee's hole gets closed, and PROJECT.md already makes the compile-time `specCommit` stamp mandatory regardless of topology.
**Delivers:** `cabal.project` `source-repository-package` pin by full 40-char SHA (**not** a git submodule — kills the recursive-init hazard outright); the `cabal.project.local` override recipe for the consumer's CI so integration builds have exactly one spec checkout; the spec commit SHA **stamped into the binary at compile time** and returned by health; `git submodule status --recursive` in CI output; the one-line coherence check for when the override is not in play.
**Avoids:** Pitfall 13 (the diamond producing false divergence — engineers "fixing" Plank to match the wrong spec — or the worse half, false agreement); Anti-Pattern 6 (over-trusting codegen).

### Phase 6: `cfmm-adapter` — `VolOrder(T)` codec and `volOrderToTokenId`
**Rationale:** **Externally blocked** on the consumer's open Phase 4 wire-format decision. Placed last precisely so the blocker cannot stall anything else — everything above is independent of it. Per D5, this phase is narrower than ARCHITECTURE sized it: the adapter decodes wire bytes into the spec's own types and **maps** the spec's guard result; it does not evaluate guards.
**Delivers:** the `VolOrder(T)` decoder behind a single plug-in seam (one module, one class) so either layout is a same-day change; `spec_volOrderToTokenId`; guard-result to `Rejected guardId` mapping; a fixture input known to violate a guard, verified to produce a typed rejection and **zero `HTTP error 500`** in any trace.
**Avoids:** Pitfall 14 (the provisional codec becoming permanent by inertia — recovery cost is HIGH and includes a trust cost with the consumer's agent); Pitfall 9's verification half.

### Phase 7: Consumption packaging and integration
**Rationale:** Needs a real method to demonstrate. Also the point at which the hosted-CI tension (D6) must be resolved rather than deferred.
**Delivers:** submodule docs, remappings, hardened `with-spec-server.sh`, consumer-side integration notes, README stating honestly what the compile-time guarantee does and does not cover; **at least one self-hosted-shaped CI job** (or a container mimicking a persistent runner) before declaring integration ready; the explicit question to the consumer's agent about collapsing the diamond, with the failure mode attached.
**Avoids:** Pitfall 11's self-hosted-only class, which hosted CI is structurally incapable of detecting.

### Phase Ordering Rationale

- **Risk retired per unit of work, with external blockers pushed last.** Phases 0-5 are entirely independent of both open decisions (RPC-02 responsibility split, `VolOrder(T)` layout). That is a large, valuable slice, and building it is what makes Pitfall 14's "guess through the blocker" pressure evaporate. This is the single strongest sequencing argument in the research set and it appears in three of the four documents.
- **The unproven assumption is attacked before anything is built on it.** Phase 1 is deliberately throwaway. If `vm.rpc` fails against the consumer's pinned version, the Haskell library, IR, renderer, codecs and test stack are all unaffected — only the wai/warp layer is discarded for a stdio responder under `vm.ffi`, and that swap is contained *because* the envelope is hand-rolled and transport-agnostic (D3).
- **The retrofit-expensive decisions land earliest.** Rejection-channel (C1), envelope shape (C2), `Guard`-as-closed-enum, purity contract, input digest echo, method namespacing and a `protocolVersion` field are all near-zero cost in Phase 2 and are **rewrite-forcing** if omitted. The generation pipeline is the fourth: retrofitting generation over a hand-written interface means rewriting the interface and every call site.
- **The Core Value is proven with a stub before the domain exists.** Phase 2's three fixture methods mean the three-outcome classifier is exercised end-to-end in CI with no cfmm code, so a Phase 6 failure is unambiguously a domain failure.
- **The bridge proves all three outcomes in its own repo before the consumer ever integrates** — otherwise the first end-to-end test of the transport happens in the consumer's CI, where the diagnosis surface is worst.
- **The domain seam is created in Phase 0 and never exercised until Phase 6.** One cabal stanza boundary, enforced by the compiler. That is the whole "generalize later" investment and it is compatible with, not a violation of, the cfmm-first decision.

### Research Flags

**Phases likely needing `/gsd:research-phase` during planning:**
- **Phase 1** — not a documentation gap but an *empirical* one. Four questions can only be answered by running code against the consumer's pinned Foundry version, and the return-path shape differs between `master` and `1.5.1-stable`. Plan it as a spike with explicit falsification criteria, not as a build task
- **Phase 4** — the Haskell-type to Solidity-type mapping has **no prior art in any ecosystem**. `aeson-typescript` is the nearest structural analogue and should be read before a line is written. The IR's coverage of bit widths, data location and ABI packing is where the real design work is
- **Phase 6** — externally blocked, and the `VolOrder(T)` decode is where the genuine domain complexity lives. Cannot be planned until the consumer's Phase 4 lands; plan the *seam* now and the *codec* later
- **Phase 7** (lighter) — the CI shape for a self-hosted-mimicking job is not settled by this research, and the Docker-container option was costed only sketchily (GitHub service containers cannot use locally-built images, which forces a publish-then-consume job pair)

**Phases with standard, well-documented patterns (skip research-phase):**
- **Phase 0** — Haskell CI on GitHub Actions is well documented; STACK supplies a concrete workflow, the cabal-store caching idiom keyed on `plan.json`, and the specific mtime and submodule-SHA cache traps
- **Phase 2** — unusually well specified by the research already. The envelope layout, the Solidity helper sketch, the fixture-method set and the boundary-value test list are all written down; this is execution, not discovery
- **Phase 3** — warp lifecycle, RTS flags, readiness polling and soak testing are established practice, and `pyk`'s `KoreServer` is a concrete reference implementation of the lifecycle
- **Phase 5** — cabal `source-repository-package` and `cabal.project.local` overrides are ordinary cabal usage; only the `gitrev`-style compile-time SHA embedding mechanism is unresearched, and it is minor (TH vs build-time env var vs custom-setup)

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | **MEDIUM** | Package versions, upload dates, dependency bounds, Stackage snapshots and runner-image contents were all queried live and are HIGH. The library *recommendation* is a well-argued judgement call (MEDIUM by the researcher's own labelling). **But the headline cheatcode recommendation (`vm.rpcJson`) is refuted by measurement (D1), and the retry-cost analysis is overstated (D2)** — which caps the section's confidence. Build-time estimates are explicitly unmeasured |
| Features | **HIGH** | Foundry mechanics read from source and corroborated by PITFALLS' independent measurements. The prior-art analysis is unusually strong: `kore-rpc`'s API doc and `pyk`'s client source were read directly, and `kore-rpc` independently arrived at this project's central design decision. The broader landscape (Certora, EELS, `beacon-fuzz`) is search-verified only and is labelled MEDIUM in place |
| Architecture | **HIGH** for transport mechanics; **MEDIUM** for CI/lifecycle/topology | The `vm.rpc` transport claims were read from Foundry `master` *and* checked against local `forge 1.5.1-stable` and forge-std `Vm.sol`, with a version matrix across v1.6/v1.7/v1.8 tags. CI lifecycle and submodule topology rest on general practice and GitHub docs with **no direct prior art for this exact shape**. One stated assumption (RPC-02 split) contradicts a settled PROJECT.md decision and is superseded — see D5 |
| Pitfalls | **HIGH** | The strongest document in the set. Seven distinct behaviours were **empirically reproduced** against a stub JSON-RPC oracle on `forge 1.5.1-stable` commit `b0a9dd9` — including the finding that master and 1.5.1 disagree on the return-path shape, which no amount of source-reading would have surfaced. Haskell-runtime and CI findings are docs plus upstream issue threads (MEDIUM) and are labelled as such |

**Overall confidence:** **MEDIUM-HIGH.** The mechanism the entire project rests on is verified from two independent directions, and the two design decisions that cannot be retrofitted are settled by convergent evidence. Confidence is held below HIGH by three things: the consumer's pinned Foundry version is unconfirmed (and every measured fact is version-scoped), the `try`/`catch`-vs-low-level-call question is unresolved, and two decisions this project depends on are owned by another agent who had not replied.

### Gaps to Address

- **The consumer's pinned Foundry version is unconfirmed.** PROJECT.md asserts 1.5.1-stable; nothing verified it against their `foundry.toml`. Master and 1.5.1 **disagree on whether the payload is wrapped in `abi.encode(bytes)`**, which changes the Solidity decode path. *Handle:* make this a blocking input to Phase 1; pin it in this repo's `foundry.toml`, stamp it into the generated header, and add the coercion conformance fixture so a bump goes red
- **`try`/`catch` against the cheatcode address (`extcodesize`) is unverified.** PROJECT.md names this the lowest-confidence remaining assumption; the low-level `address(vm).call` form sidesteps it and is the recommendation either way. *Handle:* a ten-minute Phase 1 experiment; if it fails, the low-level form is already the plan
- **RPC-02 responsibility split.** Settled in PROJECT.md (spec owns guard evaluation; bridge owns error classification and protocol well-formedness), but ARCHITECTURE was written against a different reading. *Handle:* the roadmapper should treat PROJECT.md as governing and size Phase 6 accordingly — the adapter maps guard results, it does not evaluate guards
- **`VolOrder(T)` wire format** — owned by the consumer's Phase 4, unanswered. *Handle:* Phase 6 is last; build the seam (one module, one class) in Phase 4 so either layout is a same-day change; if a placeholder becomes necessary, mark it `PROVISIONAL` with a real date and escalate to the user rather than deciding unilaterally
- **Hosted-only CI cannot detect the failure class the consumer will actually hit** (D6). *Handle:* keep hosted for Phases 0-4; add a self-hosted-shaped job before Phase 7; run the throwaway GHC-on-the-runner probe in Phase 0
- **All CI build times are estimates.** *Handle:* record actuals in the first CI run. If cold build materially exceeds 15 minutes, dependency footprint is the lever — which is a further argument for the hand-rolled envelope and warp-over-servant
- **`jsonrpc-0.2.0.0`'s actual API was never read** (Haddocks unreachable); the assessment rests on its `.cabal` file. *Handle:* read the source before depending on it; the decision is small and reversible and must not block Phase 1
- **IPC transport is plausible but unverified** — `rpc_endpoint` accepts a file path, but nobody confirmed `ProviderBuilder::new` handles a bare filesystem path. *Handle:* treat HTTP on loopback as the supported path; do not design around IPC
- **`gitrev`-style compile-time SHA embedding mechanism** is unresearched (TH vs build-time env var vs custom-setup). Minor; resolve during Phase 5 planning
- **The base-to-GHC version mapping** used in STACK is from training data, not independently re-verified (though corroborated by `jsonrpc`'s `tested-with` plus `base` bound pairing)

---

## Sources

### Primary — measured (HIGHEST confidence)
- Live `forge test` probes against a stub JSON-RPC oracle, **`forge 1.5.1-stable` / commit `b0a9dd9`, solc 0.8.34, 2026-08-27**. Reproduced: three-way outcome flattening onto `0xeeaa9e6f`; alphabetical tuple ordering; magnitude-dependent `string`/`uint256` coercion; `null` to 32 zero bytes; typed-interface revert vs silent-garbage decode; `vm.rpcJson` absent; 45.00 s hang with a **passing** test; connection-refused failing fast
- `cast sig "CheatcodeError(string)"` gives `0xeeaa9e6f`
- Local `forge --version` gives `1.5.1-stable`; local `forge-std/src/Vm.sol` — `rpc` declared, `rpcJson` absent

### Primary — read from source (HIGH confidence)
- `foundry-rs/foundry@master` — `crates/cheatcodes/src/evm/fork.rs` (`rpc_result`, `rpc_call`, `rpc_json_call`, `convert_to_bytes`, `refresh_active_fork_state`), `src/json.rs` (`json_value_to_token`), `src/inspector.rs`, `src/error.rs`, `src/config.rs`, `assets/cheatcodes.json`, `docs/dev/cheatcodes.md`
- `foundry-rs/foundry@master` — `crates/common/src/provider/mod.rs` (`max_retry: 8`, `initial_backoff: 800`, `is_local`/`no_proxy`), `crates/common/src/constants.rs` (`REQUEST_TIMEOUT = 45s`), `crates/config/src/endpoints.rs`
- `alloy-rs/alloy@main` — `crates/transport/src/error.rs` (`is_retry_err`), `crates/transport/src/utils.rs` (`guess_local_url`)
- Cheatcode version matrix from `assets/cheatcodes.json` at tags v1.6.0 / v1.7.0 / v1.8.0; foundry PR #15076 merged 2026-06-05; v1.8.0 published 2026-08-27
- `runtimeverification/haskell-backend` — `docs/2022-07-18-JSON-RPC-Server-API.md`; `runtimeverification/k` — `pyk/src/pyk/kore/rpc.py`

### Primary — queried live (HIGH confidence)
- Hackage package pages and `.cabal` files: `jsonrpc`, `json-rpc`, `jsonrpc-conduit`, `servant-jsonrpc(-server)`, `jsonrpc-tinyclient`, `json-rpc-server`, `mcp-server`, `aeson`, `warp`, `wai`, `scotty`, `servant`, `hspec`, `tasty`, `QuickCheck`, `hedgehog`, `autodocodec`, `aeson-typescript`, `deriving-aeson`, `web3-solidity`, `prettyprinter`
- Stackage `lts-24.56` and `nightly-2026-08-26` (both pin `aeson-2.2.5.0`; `jsonrpc` and `servant-jsonrpc` absent from both)
- `actions/runner-images` `Ubuntu2404-Readme.md`; `haskell-actions/setup` releases (v2.11.0, 2026-04-15); `bitnomial/servant-jsonrpc` (`pushed_at: 2024-09-28`); `codedownio/aeson-typescript` (`pushed_at: 2026-04-21`)

### Secondary — official documentation (MEDIUM confidence)
- Foundry cheatcode reference for `rpc`/`rpcJson` (**note: documents master, not the shipped release — this is the source of D1**); `forge test -j/--threads`; fuzz testing (`max_test_rejects`, `--fuzz-seed`); `vm.assume`; "`setUp()` runs before each test"
- Warp `Network.Wai.Handler.Warp` docs (`defaultOnExceptionResponse` gives 500); servant issues #1192 and #1022
- Certora `--rule_sanity` vacuity check; `ethereum/execution-apis` (OpenRPC); `ethereum/hive` `rpc-compat`; `ethereum/execution-specs` (EELS); Kontrol; `argotorg/hevm`; `quickcheck-state-machine`
- GitHub docs on containerized services; community discussion #9053 and `docker/build-push-action` #1015 (locally-built images unusable as service containers)
- raehik, "Caching Stack and Cabal Haskell builds on GitHub Actions" — the mtime-based cache-miss trap

### Tertiary — search-verified, single-source (LOW confidence, flagged in place)
- `beacon-fuzz` (Sigma Prime) — its handling of "spec rejected vs implementation errored" could not be confirmed
- foundry issues #8287 (`vm.rpc` fixed-bytes encoding), #4091 / #1202 (`max_test_rejects`), #6509 (ffi criticism)
- Negative claim: **no Haskell-to-Solidity code generator exists** — Hackage search plus targeted web search, near-misses (`abi-to-sol`, `abi-codegen`, `stack-packer`, `eip712-codegen`, `web3-solidity`) inspected individually. HIGH confidence on the negative despite being search-derived
- Negative claim: **no prior art for `vm.rpc`/`vm.rpcJson` against a non-Ethereum JSON-RPC service** — superseded in practice by the measurements above

### Project context
- `.planning/PROJECT.md` — Core Value, Key Decisions, carried risks, scope boundaries. Governs where research and PROJECT.md disagree (see D5)

---
*Research completed: 2026-08-27*
*Ready for roadmap: yes*
