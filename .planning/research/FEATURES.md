# Feature Research

**Domain:** Executable-specification-as-test-oracle / cross-language differential-testing bridge
(Haskell spec ⟶ JSON-RPC ⟶ Foundry `forge test`)
**Researched:** 2026-08-27
**Confidence:** HIGH on Foundry mechanics (read from `foundry-rs/foundry` master source), HIGH on
kore-rpc prior art (read from `runtimeverification/haskell-backend` + `pyk` source), MEDIUM on the
broader landscape (search-verified, not source-verified).

---

## 0. Why this section exists before the feature tables

Every feature below is downstream of one question: **what can Foundry's `vm.rpc` actually observe?**
The answer was read from Foundry's source, not assumed, and it inverts the naive design.

### Verified Foundry mechanics (HIGH confidence — `crates/cheatcodes/`, master)

| # | Fact | Source | Consequence for features |
|---|---|---|---|
| F1 | `function rpc(string urlOrAlias, string method, string params) external returns (bytes)` and `function rpcJson(...) returns (string)` both exist, both `safety = safe` | `assets/cheatcodes.json` | 3-arg form is the call shape. `rpcJson` gives raw JSON as a `string`. |
| F2 | The 3-arg `rpc_1` / `rpcJson_1` are implemented via `fn apply` (stateless), **not** `apply_stateful` — they do **not** require an active fork and do not touch fork state | `evm/fork.rs:245-271` | Oracle works in a plain non-fork `forge test`. No anvil needed. |
| F3 | `rpc_result` = `ProviderBuilder::<AnyNetwork>::new(url).build()` then `raw_request(...)`, with `.map_err(|err| fmt_err!("{method:?}: {err}"))` | `evm/fork.rs:599-604` | **A JSON-RPC `error` object and a refused TCP connection produce the same `Err`.** |
| F4 | A cheatcode `Err` becomes `InstructionResult::Revert` with output `err.abi_encode()` | `inspector.rs:1443-1453` | Transport failure = an ordinary EVM revert in the current frame. Catchable only across an external call boundary. |
| F5 | `Error::abi_encode()` → `Vm::CheatcodeError { message: String }` | `error.rs:137-142` | Recovered revert data is an **untyped free-text string**. Classification by string-matching an unstable message is the only option if you rely on it. |
| F6 | A fresh provider is built **per call**; no retry, no backoff, no fork RPC cache involvement, and no timeout configured at the call site | `evm/fork.rs:599-604` | Expect one TCP connection per oracle call. A hung spec computation hangs `forge test` indefinitely unless the **server** imposes a timeout. |
| F7 | `rpc_call` runs the JSON result through `json_value_to_token` + `convert_to_bytes` and returns `DynSolValue::Bytes(payload).abi_encode()` | `evm/fork.rs:535-546` | A JSON **string** result decodes cleanly to `bytes`. A JSON **object** result goes through heuristic tuple coercion (cf. foundry issue #8287). Flat hex-string results are the safe shape. |
| F8 | `rpc_endpoint(url_or_alias)` resolves: config alias → builtin chain name → literal `http*`/`ws*` URL → existing file path (IPC); aliases and literals both support `${ENV_VAR}` interpolation | `config.rs:196-215`, `config/src/endpoints.rs` | No `foundry.toml` edit is strictly required; a dynamically-allocated port can be published via env var. |
| F9 | `forge test -j / --threads <N>`, `0` = number of logical cores | `forge test` reference | **Concurrent requests from multiple test threads are the default**, not an edge case. |
| F10 | `--fuzz-seed` reproduces a run; counterexamples persist to `~/.foundry/cache/fuzz/failures` and are **replayed before new campaigns** | Foundry replay-testing docs | The oracle must be deterministic *across runs and across days*, or persisted counterexamples produce phantom regressions. |
| F11 | `fuzz.max_test_rejects` defaults to **65536**; exceeding it fails the test with "the `vm.assume` cheatcode rejected too many inputs" | Foundry fuzz docs + issue #4091 | Routing spec rejections through `vm.assume` burns a shared budget and can fail the run for the wrong reason. |
| F12 | Foundry's own `Vm` interface is declared once in a Rust `sol!` block, from which the Rust bindings, dispatch `match`, and JSON spec are generated; drift produces the runtime error *"unknown cheatcode with selector …; you may have a mismatch between the `Vm` interface (likely in `forge-std`) and the `forge` version"* | `docs/dev/cheatcodes.md`, `inspector.rs:1281-1291` | Direct in-ecosystem precedent for the generated-interface requirement — **and** a demonstration of what drift costs when generation stops at one side. |

**The single most load-bearing consequence (F3 + F4 + F5):** if the Haskell server returns a domain
rejection as a JSON-RPC `error` object, Foundry collapses it into exactly the same untyped
`CheatcodeError(string)` revert as a dead socket. The project's Core Value — three outcomes that
cannot be conflated — is *unachievable* under that design. **Spec rejection must travel inside the
JSON-RPC `result` as a tagged union. The `error` channel is reserved for genuine protocol faults,
which are correctly indistinguishable from transport faults because from the test's perspective they
are the same class: "the oracle did not answer."**

This is not a stylistic preference. It is forced by Foundry's source.

---

## 1. Prior art actually examined

| System | Architecture | Verified? | What it contributes |
|---|---|---|---|
| **`kore-rpc` / `kore-rpc-booster` (K framework Haskell backend) + `pyk` client** | Warm **Haskell** process exposing a formal semantics over **JSON-RPC**, driven by a client in another language (Python) | HIGH — read `docs/2022-07-18-JSON-RPC-Server-API.md` and `pyk/src/pyk/kore/rpc.py` | The closest structural analogue that exists. See §1.1. |
| **Foundry `Vm` cheatcode interface** | Single-source-of-truth interface definition, generated bindings + generated JSON spec | HIGH — `docs/dev/cheatcodes.md` | Precedent for generated cross-language interface, and its failure mode when only one side is generated. |
| **`ethereum/execution-apis`** | JSON-RPC surface defined in **OpenRPC**; validated against the OpenRPC metaschema at build time; `speccheck` (part of `rpctestgen`) validates test cases against the spec; `hive`'s `rpc-compat` simulator runs the resulting `>>`/`<<` request/response vectors against every client | MEDIUM (search-verified across repo + hive) | Schema-first JSON-RPC with machine-checked conformance is the ecosystem norm, not an innovation. Also: their vector format is a literal request/response transcript — the simplest possible replay artifact. |
| **`ethereum/execution-specs` (EELS) + `execution-spec-tests`** | Python executable spec used as a **fixture generator** — `fill` produces JSON fixtures from the reference spec, `consume` runs them against clients. (Note: `execution-spec-tests` has been archived and merged into `execution-specs`.) | MEDIUM | The **offline-vector architecture**, the main alternative to a live oracle. Slower feedback, but zero runtime coupling. Worth having as a fallback mode, not as the primary. |
| **Kontrol / KEVM, `halmos`, `hevm`** | **Reinterpreters** — they re-execute the same Solidity test under a different (symbolic) semantics | MEDIUM (Kontrol/halmos), MEDIUM (hevm: Haskell EVM, now `argotorg/hevm`, supports `hevm test` on Foundry projects) | These are *not* oracles and are not competitors. They replace the executor; this project leaves the real EVM in place and calls out. Useful only as a contrast: the oracle approach keeps concrete execution and real gas/ABI behaviour. |
| **Certora Prover** | Separate spec language (CVL) + prover, with an explicit `--rule_sanity` **vacuity check**: it re-runs each rule with asserts turned into requires plus `assert false`, to detect rules that pass only because their preconditions are contradictory | MEDIUM (docs.certora.com) | The canonical treatment of "a green light that means nothing." Directly motivates feature D-6. |
| **`beacon-fuzz` (Sigma Prime)** | Differential fuzzer comparing pyspec, ZRNT and Lighthouse on the same SSZ input, via **in-process embedding** orchestrated in C++ — not RPC | MEDIUM | Confirms the differential pattern; also a warning that embedding the reference spec in-process couples build systems, which is exactly what a JSON-RPC boundary avoids. |
| **`quickcheck-state-machine` / model-based PBT** | The model is executed **alongside** the SUT; every command is run against both and results checked for agreement; pre/postconditions on the model constrain generation | MEDIUM (hackage + repo) | The conceptual parent. Key transferable idea: the model *also* gates which inputs are meaningful — the analogue of the spec's guards. |

### 1.1 What `kore-rpc` + `pyk` specifically teach (highest-value prior art)

Read directly from the API doc and client source:

- **Outcome is a tag inside a successful response, not an error.** `execute` returns HTTP/JSON-RPC
  success carrying `"reason": "stuck" | "depth-bound" | "timeout" | "aborted" | "cut-point-rule" |
  "terminal-rule" | "vacuous" | "branching"`. The `error` channel is reserved for *definition-level*
  faults. This is exactly the split forced on this project by F3/F4/F5 — and kore-rpc arrived at it
  independently.
- **A tri-state is modelled explicitly and its collapse is documented as a deliberate loss.**
  `implies` returns `status: valid | invalid | indeterminate`. `pyk` collapses `indeterminate` to
  `valid = False` and its source carries a comment explaining exactly why and under what conditions
  the third state can reach the client. That is what honest three-outcome handling looks like: the
  collapse is a named, commented, conditional decision — not an accident.
- **A stable numeric error taxonomy.** `1 Could not parse pattern`, `2 Could not verify pattern`,
  `3 Could not find module`, `4 Implication check error`, `5 Smt solver error`, `6 Aborted`,
  `7 Multiple states`, `8 Invalid module`, `9 Duplicate module name`, plus `-32001` (cancel in batch),
  `-32002` (runtime error), `-32003` (unsupported option), `-32601` (not implemented) — with the
  explicit annotation that `-32002`'s `data` "is not expected to be processed by a client (other than
  including it in a bug report)."
- **Optional per-step logs in the response** — which rewrite rules fired. The direct analogue of
  "which guard rejected this input."
- **A bug-report bundle for deterministic replay.** `pyk`'s `BugReport` writes every request and
  every response to numbered JSON files alongside `definition.kore`, `server_version.txt` and
  `server_instance.json`. A failure ships as a self-contained, re-runnable tarball.
- **Client-owned server lifecycle.** `KoreServer` is a Python context manager: `Popen` the binary
  with `GHCRTS=-N<threads>`, discover the bound port from the OS by PID, drain stdout/stderr on
  daemon threads into the logger, and on `close()` send `SIGINT`/`terminate()` then `wait()` and join
  the readers.
- **Readiness by polling, not by sleeping.** `SingleSocketTransport._create_connection` retries
  `ConnectionRefusedError` on a 0.1s loop until a deadline, then raises `Connection timed out`.
- **`cancel`, and an explicit statement that cancel is unsupported in batch mode** — batching and
  cancellation interact badly, and they documented it rather than hiding it.

---

## 2. Feature Landscape

### Table Stakes (absent → the tool is unusable, or worse, silently wrong)

| # | Feature | Why Expected | Complexity | Notes |
|---|---|---|---|---|
| **TS-1** | **Three-outcome result algebra as a Haskell sum type** — `SpecOk a \| SpecRejected Guard \| TransportFailed Reason`, with no partial functions that can produce one from another | The stated Core Value. Any collapse turns the differential test into a meaningless green | MEDIUM | Make it non-`Maybe`, non-`Either String`. `Guard` must be a closed enum, not `String`. Model the collapse point explicitly if one is ever needed (kore-rpc/`pyk` precedent) |
| **TS-2** | **Rejection rides in the JSON-RPC `result`, never in `error`** — success envelope carries `{"outcome":"ok"\|"rejected", ...}` | Forced by F3/F4/F5: Foundry cannot distinguish an `error` object from a dead socket | LOW (a constraint, not code) | Depends on TS-1. Reserve `error` for parse/validation/internal faults, which legitimately belong in the same bucket as transport failure |
| **TS-3** | **Solidity-side transport-failure catcher** — the `vm.rpc` call sits behind an external call boundary (`this.f(...)` or a helper contract) wrapped in `try/catch`, converting the cheatcode revert into a value | F4: a failed cheatcode reverts the current frame. Without an external boundary the test just dies with an unclassified message | MEDIUM | This is the piece teams forget. It **must** be generated/shipped, not left to the consumer. `catch (bytes memory)` on `Vm.CheatcodeError(string)` |
| **TS-4** | **Payload-free health/echo method** exercisable end-to-end (`spec_health`, `spec_echo`) | Proves the transport shape independently of any domain method; first thing to run in CI and first thing to check when a domain method misbehaves | LOW | Already an Active requirement. Should return the version stamp (TS-12) |
| **TS-5** | **Warm long-lived server, one process per `forge test` run** | 256 fuzz runs × N tests × shrink steps; per-case process spawn is not viable | MEDIUM | Depends on TS-6, TS-7, TS-10 |
| **TS-6** | **Concurrency-safe request handling** — no global mutable state, no serializing lock around spec evaluation, `-threaded` RTS with `-N` | F9: `forge test` is parallel by default across logical cores | MEDIUM | Depends on TS-7. A single `MVar` around evaluation would silently serialize the whole suite. Precedent: kore-rpc is launched with `GHCRTS=-N<threads>` |
| **TS-7** | **Pure, stateless request handling** — the response is a function of the request alone; no cross-request state, no session handles | F10: counterexample replay and fuzz shrinking both re-issue the same request and require the same answer. Also the precondition for TS-6 | LOW (a constraint) | Make it a documented, tested invariant, not an accident of the current implementation |
| **TS-8** | **Per-request Haskell exception firewall** — `try . evaluate . force` inside the handler, converting `ErrorCall`, incomplete-pattern, arithmetic and array exceptions into a typed internal-error response | Haskell-specific: laziness means a thunk can blow up *after* the handler returns, during serialization, killing the connection and presenting as transport failure. A spec bug would then masquerade as a network problem — a direct violation of the Core Value | MEDIUM | Non-obvious and easy to omit. Requires forcing to normal form, so the result type needs `NFData`. Depends on TS-1 |
| **TS-9** | **Server-side per-request timeout** | F6: no timeout is set at Foundry's call site. A non-terminating spec evaluation hangs `forge test` forever with no diagnostic | LOW-MEDIUM | Timeout must return a *typed* internal-error response (so it is classifiable), not just drop the connection |
| **TS-10** | **Lifecycle management owned by the harness, not by Solidity** — start server, poll until ready, run `forge test`, stop server; failure to become ready aborts the run | `forge` has no pre-test hook. Nothing in Solidity can start a process (short of `vm.ffi`, which the transport decision moved away from) | MEDIUM | Lives in the `justfile`/`Makefile`/CI job. Readiness = poll TS-4 with backoff and a deadline (pyk precedent), never `sleep 2` |
| **TS-11** | **Structured error taxonomy with stable numeric codes** for the `error` channel | Free-text messages cannot be matched on; F5 shows Foundry already forces one layer of untyped string on you, so do not add a second | LOW-MEDIUM | Copy the kore-rpc shape: small positive integers for domain-protocol faults, `-32000..-32099` for server faults, standard codes for JSON-RPC-level faults |
| **TS-12** | **Version/build stamp** in the health response, asserted by the test setup | Warm processes go stale. A server built from an older spec commit will happily serve wrong answers all day. This is the characteristic warm-process failure mode | LOW | Stamp = spec package version + git SHA + protocol version. Enhances TS-4 |
| **TS-13** | **Deterministic replay artifact** — every request/response pair logged with the fuzz seed, in a form that can be re-issued without `forge` | F10: reproducing a fuzz failure needs the exact input. Debugging the Haskell side through `forge` is miserable | MEDIUM | Minimum viable version is the `execution-apis` `>>`/`<<` transcript format. Depends on TS-7 (otherwise replay is not meaningful) |
| **TS-14** | **Hex-string wire encoding for all numeric and byte quantities; never JSON numbers** | `uint256` through a JSON number loses precision at 2^53. This is settled Ethereum JSON-RPC convention and Foundry's `json_value_to_token` (F7) handles hex strings cleanly | LOW | Also implies: reject unknown fields, reject out-of-range, reject non-canonical encodings — strictly (see AF-3) |
| **TS-15** | **Request/response correlation** — echo the JSON-RPC `id`, reject notifications and unexpected batch shapes | Standard JSON-RPC hygiene | LOW | Honest scoping: over HTTP with one request per connection (F6), correlation is nearly free. It becomes load-bearing only if IPC/streaming is ever adopted. Do it right anyway; it costs nothing |

### Differentiators (this is where the project competes)

| # | Feature | Value Proposition | Complexity | Notes |
|---|---|---|---|---|
| **D-1** | **Solidity interface + params encoder + response decoder generated from the Haskell protocol types** | The stated differentiator. Turns silent 3am wire drift into a compile error. Precedent: Foundry's own `Vm` generation (F12) | HIGH | **Must include the params encoder**, not just the interface: `vm.rpc` takes `params` as a *JSON string* the test has to build. A generated interface with hand-built JSON params has moved the drift, not removed it |
| **D-2** | **Typed guard identity in rejections** — a closed, stable, enumerated guard ID (plus optional human message), so the test can assert *which* guard fired | Distinguishes "the spec rejected this because of the tick-spacing guard" from "the spec rejected this for some reason." Without it, rejection is a single opaque bucket and you cannot tell a correct rejection from a decoder bug | MEDIUM | Depends on TS-1, D-1. Precedent: kore-rpc's numeric taxonomy and its per-step rule logs |
| **D-3** | **CI drift gate** — regenerate the Solidity artifact in CI and fail on any diff | Generation only prevents drift if regeneration is enforced. Otherwise the checked-in artifact is just a hand-written file with extra steps | LOW-MEDIUM | Depends on D-1. Cheap, and it is the feature that makes D-1 real |
| **D-4** | **Vacuity guard / oracle-call accounting** — the run asserts the oracle was consulted at least N times and produced at least one `ok`; zero-success runs fail | The direct antidote to the Core Value's stated nightmare: "a green light that means nothing." Catches an over-tight guard that rejects 100% of fuzz inputs, which otherwise passes silently | LOW-MEDIUM | Precedent: Certora `--rule_sanity` vacuity check. Implementable server-side (run summary + a `spec_runStats` method the test asserts in `tearDown`) or client-side via a counter contract |
| **D-5** | **Input digest echoed in the response** — canonical hash of the decoded request returned alongside the answer, checked by the generated decoder | Proves the answer corresponds to the input actually sent, closing the whole class of misrouting/stale-response/wrong-server bugs that a warm shared process makes possible | LOW | Depends on TS-7, D-1. Very cheap, very high value under `-j` |
| **D-6** | **Structured observability** — one line per request: id, method, input digest, outcome tag, guard ID, latency; plus an end-of-run summary (ok / rejected / internal counts, guard histogram) | Makes "which guard is eating my fuzz corpus" a five-second question. The guard histogram is what turns D-4 from a pass/fail into a diagnosis | MEDIUM | Depends on D-2, TS-13. Feeds D-4 |
| **D-7** | **Golden-vector export mode** (`fill`) — a CLI that dumps `(input, expected outcome)` pairs to JSON for offline replay with no live server | Directly de-risks the PROJECT.md risk *"GHC/cabal on the consumer's self-hosted runner is unverified"*: a runner that cannot run a Haskell service can still consume vectors. Also gives a fast no-oracle smoke test | MEDIUM | Precedent: `execution-spec-tests` `fill`/`consume`. Depends on TS-7, TS-13. **Strong v1.x candidate** |
| **D-8** | **Counterexample bundle** — on failure, emit a self-contained tarball: request, response, spec version, server version, fuzz seed | Converts "it failed in CI" into a reproducible artifact. Precedent: `pyk`'s `BugReport` | MEDIUM | Depends on TS-13, TS-12 |
| **D-9** | **`spec_batch` method** — one RPC carrying N inputs, N tagged outcomes | Amortizes per-call TCP setup (F6: one connection per call) for table-driven tests | MEDIUM | **Honest assessment: this does not help fuzzing.** Fuzz gives one input per run, so the batch size is one. Only worth building when a table-driven consumer exists. v1.x at the earliest |
| **D-10** | **`vm.rpcJson` + `vm.parseJson` decode path** as an alternative to the `bytes` path | Escape hatch if F7's heuristic coercion misbehaves on a future richer result shape | LOW | Cheap insurance. Generate both, pick one as default |

### Anti-Features (deliberately NOT built)

| # | Feature | Why Requested | Why Problematic | Alternative |
|---|---|---|---|---|
| **AF-1** | **Domain rejection returned as a JSON-RPC `error` object** | It "feels" like an error; JSON-RPC has an error channel, so use it | **Fatal.** F3+F4+F5: Foundry maps it to the identical untyped `CheatcodeError(string)` revert as a refused connection. Destroys the Core Value | Rejection in `result` as a tagged union (TS-2). `error` only for faults that genuinely belong in the "no answer" bucket |
| **AF-2** | **General-purpose EVM node proxy** — forwarding unknown `eth_*` methods, or pretending to be a node | "It's already a JSON-RPC server, why not point a fork at it" | Turns a small pure oracle into an EVM implementation with a consensus surface. Unbounded scope; also invites Foundry's fork machinery (`refresh_active_fork_state`) to start interacting with it | Namespace every method `spec_*`; return `-32601 Method not found` for everything else, loudly |
| **AF-3** | **Mutable oracle state / session handles** (`spec_newSession` → `spec_step` → `spec_commit`) | Feels natural for the deferred v2 spec-drives-EVM direction | Breaks TS-7, and with it fuzz shrinking (F10) and counterexample replay: the same request stops yielding the same answer. Also serializes TS-6. Foundry's own `refresh_active_fork_state` special-case for `anvil_set*` methods is a live demonstration of what state-mutating RPC costs downstream | Keep v1 pure. If v2 needs sessions, make the session an **explicit request parameter** (state passed in, new state returned), preserving purity |
| **AF-4** | **Lenient decoding** — default on decode failure, coerce out-of-range values, ignore unknown fields | "Be liberal in what you accept" | A silently-defaulted input means the spec answers a *different question* than the contract was asked, and the answers agree by luck. This is the single most insidious way to get a meaningless green | Strict decode; a decode failure is a *typed protocol fault* on the `error` channel with a code (TS-11) and must fail the test |
| **AF-5** | **A skip/degrade path** — `if (!oracleReachable) return;` or `vm.skip(true)` on transport failure | "Don't block the build on infrastructure" | The exact failure the project exists to prevent. A test that passes when the oracle is down is a green light that means nothing | Transport failure **always** fails the test, with a message naming the transport (TS-3). If a no-oracle CI lane is genuinely needed, use D-7 golden vectors — a *different* lane with *different*, explicit coverage |
| **AF-6** | **Routing spec rejection through `vm.assume`** | Rejected inputs "aren't interesting," so filter them | F11: burns the shared 65536 reject budget and can fail the run with a misleading message. Worse, it makes rejections invisible — you cannot distinguish "spec correctly rejected" from "spec wrongly rejected" from "decoder is broken" | Assert on the rejection: the contract must reject too, and ideally with a corresponding reason. `vm.assume` only for inputs the *test* considers out of scope, never for spec-guard outcomes. See D-4 |
| **AF-7** | **Client-side retries / backoff around `vm.rpc`** | "Networks are flaky" | On `127.0.0.1` to a local process, a failure is a real bug. Retry converts a reproducible nondeterminism bug into an intermittent one. (Foundry does no retry for `vm.rpc` anyway — F6) | Fail fast and loudly. Fix the nondeterminism |
| **AF-8** | **Persistent on-disk answer cache** | "Same input, same answer — cache it" | Pure in-process memoization within one run is harmless. A cache that **survives across spec versions** will serve pre-fix answers after the spec is fixed, and the differential test will confirm the old bug | If caching is needed, key it on the version stamp (TS-12) and never persist it across processes |
| **AF-9** | **Server spawned per test or per fuzz case** | Simplest lifecycle; no shared state to worry about | Process-spawn cost × thousands of cases; port collisions under `-j` (F9); GHC RTS startup per case | Warm server (TS-5) + purity (TS-7) gives isolation without spawn cost |
| **AF-10** | **Domain-agnostic plugin/registry abstraction** in v1 | "We'll want other specs later" | Explicitly out of scope per PROJECT.md ("cfmm-first, generalize later"). An abstraction built for one real and one imagined consumer fits neither | Depend directly on `cfmm-vol-markets-spec`. Extract on the *second real* demand |
| **AF-11** | **Auth, TLS, rate limiting, multi-tenancy** | Reflex when you hear "server" | It binds `127.0.0.1` and lives for the duration of one `forge test`. Every one of these adds failure modes that present as transport failure | Bind loopback only. Refuse non-loopback connections if you want a guarantee |
| **AF-12** | **WebSocket / subscriptions / streaming** | "Push results as they compute" | `vm.rpc` is strictly request/response (F1). There is no consumer for a push channel | HTTP/1.1 request/response only |
| **AF-13** | **Hand-written Solidity mirrors of the Haskell types** | Faster to start; no codegen pipeline to build | Precisely the drift the project exists to eliminate. F12 shows what happens when generation covers only one side | D-1 generation + D-3 CI drift gate |

---

## 3. Feature Dependencies

```
TS-1 Three-outcome algebra (Haskell sum type)
  ├──requires──> (nothing; this is the root design decision)
  ├──enables───> TS-2 Rejection in `result`, not `error`
  │                └──enables──> TS-3 Solidity try/catch transport catcher
  │                                └──requires──> D-1 Generated interface (to ship the catcher)
  ├──enables───> D-2 Typed guard identity
  │                └──enables──> D-6 Structured observability
  │                                 └──enables──> D-4 Vacuity guard / call accounting
  └──requires──> TS-8 Haskell exception firewall (else a spec crash leaks out as transport failure)

TS-7 Pure, stateless handling
  ├──enables───> TS-6 Concurrency-safe handling  ──requires──> TS-5 Warm server
  ├──enables───> TS-13 Deterministic replay artifact
  │                 ├──enables──> D-7 Golden-vector export
  │                 └──enables──> D-8 Counterexample bundle ──requires──> TS-12 Version stamp
  ├──enables───> D-5 Input digest echo
  └──conflicts──> AF-3 Mutable session state

TS-5 Warm server
  ├──requires──> TS-9 Server-side timeout (no client timeout exists — F6)
  ├──requires──> TS-12 Version stamp (warm processes go stale)
  └──requires──> TS-10 Harness lifecycle management
                    └──requires──> TS-4 Health method (readiness polling target)

D-1 Generated Solidity interface
  ├──requires──> a settled protocol type set (blocked on OPEN: RPC-02 responsibility split)
  ├──requires──> a settled VolOrder wire format (blocked on OPEN: consumer Phase 4)
  ├──enables───> D-3 CI drift gate
  └──enables───> D-10 rpcJson alternative decode path

TS-14 Hex-string wire encoding ──enables──> clean F7 `bytes` decode in Solidity

AF-5 Skip-on-unreachable ──conflicts──> TS-3, and negates the entire Core Value
AF-6 vm.assume for rejections ──conflicts──> D-2, D-4
```

### Dependency notes

- **TS-2 requires TS-1 as a *type*, not a convention.** If `Guard` is `String` and the outcome is
  `Either String a`, nothing prevents a future contributor from putting a transport message in the
  rejection slot. The whole guarantee lives in the constructors.
- **TS-3 requires D-1.** The `try/catch` wrapper must live in generated code. A hand-written wrapper
  in the consumer's repo will drift from the server's error shape, and it is the one component whose
  drift produces a *false pass* rather than a compile error.
- **TS-8 is not optional given TS-1.** Haskell laziness means an unforced thunk can throw during
  response serialization, after the handler has already classified the outcome as `SpecOk`. The
  connection dies, Foundry sees a transport failure, and a genuine spec bug is filed under
  "infrastructure." Forcing to NF inside the handler is what makes TS-1's guarantee true at runtime
  rather than only at the type level.
- **D-1 is currently blocked on two OPEN decisions** recorded in PROJECT.md (RPC-02 responsibility
  split, `VolOrder(T)` wire format). The *generator machinery* can be built against the health/echo
  method (TS-4) before either is settled — which is a strong argument for sequencing the payload-free
  skeleton first.
- **D-4 and AF-6 are the same question answered two ways.** Either rejections are first-class and
  counted, or they are filtered away and invisible. Choosing D-4 forbids AF-6.

---

## 4. MVP Definition

### Launch With (v1 — query direction only)

- [ ] **TS-1** Three-outcome Haskell sum type — the Core Value; nothing else matters if this is wrong
- [ ] **TS-2** Rejection in `result`, protocol faults in `error` — forced by Foundry's source (F3/F4/F5)
- [ ] **TS-3** Generated Solidity transport-failure catcher — without it the third outcome is unobservable
- [ ] **TS-4** Payload-free health/echo — already an Active requirement; also the readiness target
- [ ] **TS-5** Warm server, one per `forge test` run — the reason JSON-RPC was chosen over `vm.ffi`
- [ ] **TS-6** Concurrency-safe handling — `forge test` is parallel by default (F9), not an edge case
- [ ] **TS-7** Pure, stateless handling — precondition for shrinking, replay and concurrency
- [ ] **TS-8** Haskell exception firewall — otherwise spec bugs masquerade as transport failures
- [ ] **TS-9** Server-side timeout — otherwise a diverging spec hangs CI with no diagnostic (F6)
- [ ] **TS-10** Harness-owned lifecycle with readiness polling — nothing in Solidity can do this
- [ ] **TS-11** Numeric error taxonomy for the `error` channel
- [ ] **TS-12** Version stamp in health, asserted by the test — the warm-process staleness guard
- [ ] **TS-14** Hex-string wire encoding, strict decode
- [ ] **TS-15** JSON-RPC `id` correlation and shape validation
- [ ] **D-1** Generated Solidity interface **+ params encoder + response decoder** — the stated differentiator
- [ ] **D-3** CI drift gate — makes D-1 real rather than aspirational
- [ ] **D-2** Typed guard identity — an Active requirement ("carrying the rejecting guard")
- [ ] **D-5** Input digest echo — cheap, and it closes a class of warm-shared-process bugs

### Add After Validation (v1.x)

- [ ] **TS-13** Full replay artifact — *trigger:* first fuzz failure that is painful to reproduce
- [ ] **D-6** Structured observability + guard histogram — *trigger:* first "why is my corpus empty" incident
- [ ] **D-4** Vacuity guard / oracle-call accounting — *trigger:* as soon as D-6 exists; ideally sooner
- [ ] **D-7** Golden-vector export — *trigger:* the self-hosted-runner GHC question comes due, or CI cost bites
- [ ] **D-8** Counterexample bundle — *trigger:* a failure that cannot be reproduced locally
- [ ] **D-10** `rpcJson` decode path — *trigger:* first F7 coercion surprise

### Future Consideration (v2+)

- [ ] **D-9** `spec_batch` — defer: fuzzing gives one input per run, so batch size is one today
- [ ] Spec-drives-EVM direction — explicitly out of scope per PROJECT.md; no consumer exists
- [ ] Domain-agnostic core — deferred until a second real demand (AF-10)
- [ ] `cancel` method — only meaningful once long-running spec computations exist

### Rewrite-forcing gaps (flag these loudly — absent in v1 means a v2 rewrite, not a v2 addition)

| Gap if omitted in v1 | Why it forces a rewrite |
|---|---|
| **Rejection in `result` rather than `error` (TS-2)** | Changing the outcome channel changes every response shape and every consumer decoder. This is the one that cannot be retrofitted cheaply |
| **Method namespacing (`spec_*`) and a `protocolVersion` field in every response** | Both are one line now. Retrofitting a version field into a shipped protocol means a flag day with the consumer. Cost now: near zero |
| **Purity/statelessness contract (TS-7)** | If v1 tolerates handler state, the v2 drive direction will be designed around sessions, and shrinking/replay guarantees are lost permanently. Purity must be a stated, tested invariant from day one — with v2 sessions passing state as an explicit parameter |
| **Generation pipeline (D-1)** | Retrofitting generation over a hand-written interface means rewriting the interface and every call site. The generator can and should be built against TS-4's payload-free method before the domain types are settled |
| **Input digest echo (D-5)** | Adding a field to the response later is a protocol change. It is three lines now |
| **`Guard` as a closed enum, not `String` (D-2)** | Consumers will start string-matching guard messages. Once they do, the messages are a public API |

---

## 5. Concurrency & lifecycle: what a warm oracle needs to serve `forge test`

This is the question the downstream consumer asked specifically. Answering it from the verified
mechanics rather than from intuition:

**The load shape.** `forge test -j <N>` defaults `N` to logical cores (F9). Each test thread runs
`vm.rpc` synchronously via `foundry_common::block_on` — so requests are serialized *within* a thread
and concurrent *across* threads. Per test function: `fuzz.runs` (default 256) calls, **plus** shrink
steps on failure, **plus** replayed persisted counterexamples at campaign start (F10). Foundry builds
a **fresh provider per call** with no retry and no timeout (F6), so the realistic profile is
*thousands of short-lived TCP connections, up to `N` concurrent, each carrying exactly one small
request, over the lifetime of one `forge test` invocation.*

**Required feature set for that load:**

1. **HTTP/1.1 server on loopback** sized for high connect/accept churn rather than high concurrency.
   Set `SO_REUSEADDR`; expect `TIME_WAIT` accumulation; handle `Connection: close` correctly. Do not
   assume keep-alive will amortize anything — F6 says it will not.
2. **No per-connection warmup.** Any per-connection setup cost is paid thousands of times. All
   expensive initialization (spec loading, table construction) happens once at startup, before
   readiness is signalled.
3. **True parallel evaluation.** `-threaded` RTS, `-N` set explicitly (kore-rpc's `GHCRTS=-N<n>`
   precedent). Audit for accidental serialization: a single `MVar`, an `IORef` counter under
   contention, or a shared `stdout` handle without buffering discipline will each throttle the whole
   suite to one core while looking fine in a single-threaded test.
4. **Purity as the isolation mechanism (TS-7).** With no shared mutable state, concurrency needs no
   locking and shrinking/replay stay sound. This is why AF-3 (sessions) is an anti-feature, not merely
   a deferral.
5. **Server-side timeout per request (TS-9).** With no client timeout, one non-terminating evaluation
   pins a test thread forever and CI dies on a job timeout with no useful output.
6. **Bounded, non-blocking logging.** Per-request logging (D-6) at thousands of requests per run must
   not become the serialization point. Buffer, and drain on a separate thread (pyk's stdout/stderr
   reader-thread pattern).
7. **Deterministic under concurrency.** Same request → same response regardless of what else is
   in flight. D-5's input digest echo is the cheap runtime check that this actually holds.
8. **Readiness before the first test, teardown after the last (TS-10).** Start the server, poll the
   health method with backoff until a deadline (never `sleep`), fail the job if the deadline passes,
   run `forge test`, then terminate and reap. Port allocation: either a fixed loopback port with a
   pre-flight "is something already listening" check, or an ephemeral port published through an env
   var consumed by `foundry.toml`'s `${VAR}` interpolation (F8) — both are supported by Foundry's
   resolver, and the ephemeral-port route is safer against collisions when multiple CI jobs share a
   runner.
9. **A one-server-per-run assumption, made explicit.** The version stamp (TS-12) asserted in
   `setUp`/`tearDown` is what catches the case where a stale server from a previous run is still bound
   to the port.

---

## 6. Competitor / prior-art feature comparison

| Feature | kore-rpc + pyk | execution-spec-tests (EELS) | Kontrol / halmos / hevm | Certora | **This project's plan** |
|---|---|---|---|---|---|
| Architecture | Warm Haskell server over JSON-RPC | Offline fixture generation (`fill`/`consume`) | Reinterpreter — replaces the executor | Separate spec language + prover | Warm Haskell server over JSON-RPC, called from real EVM execution |
| Outcome vs error split | `reason` tag in the success payload; numeric codes in `error` | Fixture is expected-output; mismatch = failure | Proof result: proved / refuted / unknown | valid / violated / timeout | **Tagged union in `result`; `error` reserved for faults (forced by F3/F4/F5)** |
| Third "don't know" state | `implies` returns `valid \| invalid \| indeterminate`; `pyk` collapses it with a documented rationale | n/a | `unknown` from the solver | timeout / unknown | Transport failure is the third state, and it is **never** collapsed |
| Generated interface | Hand-written client, generated from docs by hand | Python types shared in-repo | n/a | n/a | **Generated Solidity from Haskell types (D-1)** — the differentiator |
| Vacuity / meaningless-green defence | n/a | Fixture count is visible | n/a | **`--rule_sanity` vacuity check** | **D-4 oracle-call accounting**, modelled on Certora |
| Replay artifact | **`BugReport` tarball** (requests, responses, definition, versions) | The fixture JSON *is* the artifact | Proof artifacts | Rule report | **TS-13 transcript, D-8 bundle** |
| Lifecycle | Client owns it: `Popen`, port discovery, connection-refused polling, `SIGINT`/terminate | No server | No server | Cloud service | **TS-10, harness-owned** (nothing in Solidity can do it) |
| Batching | JSON-RPC batch mode, with `cancel` explicitly unsupported inside it | n/a | n/a | n/a | **Deferred (D-9)** — fuzzing gives batch size one |

---

## 7. Honest gaps and open questions

- **The consumer's `SpecHelper` shape is not fully determined by this research.** Whether the
  `try/catch` boundary is a helper contract or an external self-call (`this.f(...)`) has gas and trace
  consequences I did not measure. Both work under F4; pick one during design.
- **IPC transport is plausible but unverified.** F8 shows `rpc_endpoint` accepts an existing file path
  as an IPC socket, but I did not confirm that `ProviderBuilder::<AnyNetwork>::new(url).build()` in
  `rpc_result` handles a bare filesystem path. **LOW confidence — treat HTTP on loopback as the
  supported path** and do not design around IPC without testing it.
- **The exact `bytes` layout of `vm.rpc` for non-string JSON results is heuristic** (F7,
  `json_value_to_token` + foundry issue #8287). This research supports "return a flat hex string" as
  the safe shape; it does not enumerate what happens for objects and arrays. If the protocol ever
  needs a structured result, prototype it against a real `forge test` before committing.
- **Whether a cheatcode revert is reliably catchable by `try/catch` across a call boundary** is
  inferred from F4 (`InstructionResult::Revert` in the sub-frame is an ordinary revert) rather than
  observed. It is a strong inference, but **it is the single mechanic the Core Value rests on and it
  should be proven by an end-to-end spike before any other work.** If it turns out not to hold, the
  three-outcome requirement needs a different mechanism entirely and the whole design changes.
- **`beacon-fuzz`'s handling of "spec rejected vs implementation errored"** could not be confirmed
  from the announcement posts; answering it would require reading the repository. The general lesson
  (differential fuzzing must compare *error behaviour*, not just success values) is well supported
  elsewhere and I have relied on that rather than on beacon-fuzz specifics.
- **D-1's scope is gated on two OPEN decisions** in PROJECT.md (RPC-02 responsibility split;
  `VolOrder(T)` wire format). "Dumb transport" and "owns decode plus error classification" produce
  materially different generator complexity. The generator machinery can nonetheless be proven against
  TS-4's payload-free method first, which is the lowest-risk sequencing.

## Sources

**Read directly from source (HIGH confidence):**
- `foundry-rs/foundry` master: `crates/cheatcodes/src/evm/fork.rs`, `crates/cheatcodes/src/inspector.rs`, `crates/cheatcodes/src/error.rs`, `crates/cheatcodes/src/config.rs`, `crates/config/src/endpoints.rs`, `crates/cheatcodes/assets/cheatcodes.json`, `docs/dev/cheatcodes.md`
- `runtimeverification/haskell-backend`: `docs/2022-07-18-JSON-RPC-Server-API.md`
- `runtimeverification/k`: `pyk/src/pyk/kore/rpc.py`

**Official documentation (HIGH/MEDIUM confidence):**
- https://www.getfoundry.sh/reference/cheatcodes/rpc/ — `rpc` / `rpcJson` signatures
- https://www.getfoundry.sh/reference/forge/test — `-j / --threads`
- https://book.getfoundry.sh/forge/fuzz-testing — `max_test_rejects`, `--fuzz-seed`
- https://book.getfoundry.sh/cheatcodes/assume — `vm.assume` rejection budget
- https://docs.certora.com/en/latest/docs/prover/checking/sanity.html — vacuity check
- https://ethereum.github.io/execution-apis/ — OpenRPC specification
- https://github.com/ethereum/hive/tree/master/simulators/ethereum/rpc-compat — conformance simulator
- https://github.com/ethereum/execution-spec-tests — `fill`/`consume` (archived, merged into `execution-specs`)
- https://github.com/ethereum/execution-specs — EELS reference implementation
- https://docs.runtimeverification.com/kontrol — Kontrol
- https://github.com/argotorg/hevm — Haskell EVM
- https://hackage.haskell.org/package/quickcheck-state-machine — model-based PBT

**Search-verified, single-source (LOW/MEDIUM confidence — flagged in text):**
- https://sigmaprime.io/blog/beacon-fuzz/ and https://github.com/sigp/beacon-fuzz
- https://github.com/foundry-rs/foundry/issues/4091 — `max_test_reject_rate`
- https://github.com/foundry-rs/foundry/issues/8287 — `vm.rpc` fixed-bytes encoding

---
*Feature research for: executable-specification-as-test-oracle bridges*
*Researched: 2026-08-27*
