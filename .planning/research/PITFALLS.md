# Pitfalls Research

**Domain:** Cross-language spec-oracle bridge — Haskell JSON-RPC service consumed by Foundry/Solidity differential tests over `vm.rpc`
**Researched:** 2026-08-27
**Confidence:** HIGH for the Foundry/`vm.rpc` findings (read from foundry source **and** empirically reproduced against a stub oracle on `forge 1.5.1-stable`, commit `b0a9dd9`). MEDIUM for the Haskell-runtime and CI findings (official docs + upstream issue threads, not reproduced here). LOW where explicitly marked.

> **Method note.** Sections marked **[MEASURED]** were verified by running a real `forge test` against a stub JSON-RPC oracle in `/tmp/orctest` while writing this document. Do not treat those as opinion — they are observations. Sections marked **[SOURCE]** were read from `foundry-rs/foundry` master. Where master and 1.5.1-stable disagree, that disagreement is itself a pitfall and is called out.

---

## The one-paragraph version

The core value in PROJECT.md — *"can tell spec success, spec rejection, and transport failure apart — never conflating them"* — is **actively fought by the transport that was chosen**. `vm.rpc` flattens a JSON-RPC error object, an HTTP 5xx, a connection refusal, and a request timeout into **one** revert with **one** selector (`CheatcodeError(string)` = `0xeeaa9e6f`), differing only in an unstable English message. And `vm.rpc`'s success path applies a value-dependent JSON→ABI coercion that can change the returned ABI *type* based on the *magnitude* of the number the spec returned. Both are measured facts, not risks. The roadmap must design around them in Phase 1, not discover them in Phase 7.

---

## Critical Pitfalls

### Pitfall 1: All three outcomes already arrive on one channel — `vm.rpc` erases the distinction the project exists to preserve **[MEASURED]**

**What goes wrong:**
`vm.rpc` returns `Result<serde_json::Value>` from a single call site and maps *every* failure through `fmt_err!("{method:?}: {err}")` ([`crates/cheatcodes/src/evm/fork.rs`, `rpc_result`](https://github.com/foundry-rs/foundry/blob/master/crates/cheatcodes/src/evm/fork.rs)). That becomes a cheatcode revert ABI-encoded as the custom error `CheatcodeError(string)`. Measured returndata prefixes, all identical:

| Oracle behaviour | Solidity `success` | Returndata selector | Message body (the *only* discriminator) |
|---|---|---|---|
| JSON-RPC error object `-32001` | `false` | `0xeeaa9e6f` | `vm.rpc: "spec_reject": server returned an error response: error code -32001: guard violated: tickLower` |
| HTTP 500 + non-JSON body | `false` | `0xeeaa9e6f` | `vm.rpc: "spec_bad": HTTP error 500 with body: boom` |
| Connection refused (port closed) | `false` | `0xeeaa9e6f` | `vm.rpc: "spec_smallStr": error sending request for url (http://127.0.0.1:8600/)` |
| Request timeout (~45 s, see Pitfall 6) | `false` | `0xeeaa9e6f` | timeout text from `reqwest`/`alloy` |

There is **no error code**, **no structured field**, **no distinct selector**. A spec rejection and a dead server are the same bytes up to prose. XPORT-02 is unimplementable if rejection travels as a JSON-RPC `error` object.

**Why it happens:**
JSON-RPC 2.0's *idiomatic* answer for "the input violated a precondition" is an `error` object with an application code in the `-32000..-32099` range. Every JSON-RPC tutorial, and `servant-jsonrpc`'s `JsonRpcErr` type, pushes you there. It is the wrong answer for this transport, and it is the answer a Haskell engineer will reach for by default.

**How to avoid:**
Make the three outcomes a **sum type inside the JSON-RPC `result`**, and reserve the JSON-RPC `error` channel exclusively for things that are genuinely not spec answers (malformed request, unknown method, internal crash). Then, and only then:

- `success == false` ⟺ **transport failure**, unconditionally, no string parsing.
- `success == true` ⟹ decode the payload's tag byte to get **spec success** vs **spec rejection**.

This is a one-line invariant a Solidity helper can enforce, and it is the single highest-leverage design decision in the project. It also happens to make the `Result`-shaped Haskell type and the Solidity three-way enum line up naturally.

**Do not** build a string-matching classifier over the `CheatcodeError` message. Those strings come from `reqwest`, `alloy`, and `fmt_err!` — three upstreams, none of which treat them as API surface. A Foundry bump silently reclassifies rejections as transport failures or vice-versa, and the differential test goes green.

**Warning signs:**
- Any Haskell code path that constructs a JSON-RPC `error` object for a *domain* reason (guard violated, out of range, unsupported variant).
- Any Solidity code containing `keccak256(bytes(errMsg))`, `startsWith`, or a substring search over a revert message.
- A `SpecHelper` whose transport-failure branch and rejection branch both originate from `success == false`.

**Phase to address:** Phase 1 (protocol core / three-outcome type). This constrains the wire schema, so it must land before any codec work.

---

### Pitfall 2: `vm.rpc`'s JSON→ABI coercion is **value-dependent**, so the same Haskell type produces different Solidity types for different fuzz inputs **[MEASURED]**

**What goes wrong:**
`rpc_call` does not decode the JSON against a declared type. It calls `json_value_to_token(&result, None)` — foundry's heuristic coercion — with struct definitions explicitly **disabled** (`None`), then ABI-encodes whatever token it guessed. The heuristics ([`crates/cheatcodes/src/json.rs`](https://github.com/foundry-rs/foundry/blob/master/crates/cheatcodes/src/json.rs)) include:

- A JSON **string** that parses as an integer **but fits in `i64`/`u64` stays a Solidity `string`**; one that **exceeds** `i64`/`u64` becomes `int256`/`uint256`.
- A JSON **number** becomes `uint256`, or `int256` if negative.
- A JSON **`null`** becomes `bytes32(0)`.
- A `"0x…"` string becomes `address` (20 bytes), `bytes32` (32 bytes), or `bytes` (anything else) — then `convert_to_bytes` collapses all three to `bytes`.
- A JSON **object** becomes a tuple ordered **alphabetically by key**.

Measured, same record shape, two different values:

```
result = {"tag":"Rejected","guard":"tickLower","tokenId":"0"}
  → tuple(string guard, string tag, string tokenId)   [320 bytes returndata]

result = {"tag":"Ok","guard":"","tokenId":"18446744073709551616"}
  → tuple(string guard, string tag, uint256 tokenId)  [224 bytes returndata]
```

**The third field changed from `string` to `uint256` because the number got bigger.** A `tokenId` below 2^64 and one above 2^64 are different ABI types. Under fuzzing, `abi.decode(ret, (string,string,uint256))` works on some inputs and reverts on others, with a bare `EvmError: Revert` and no message. Worse, some mismatches *don't* revert — see Pitfall 3.

**Why it happens:**
`vm.rpc` was designed to read `eth_getBlockByNumber`, not to carry a typed domain payload. Its "return type" in `Vm.sol` is `bytes memory`, which reads as "raw bytes, you parse it" — but it is not raw; it is pre-chewed by heuristics you did not opt into. Nothing in the Foundry docs says the coercion is magnitude-sensitive.

**How to avoid:**
**Make the JSON result a single, even-length, `0x`-prefixed hex string carrying an ABI-encoded payload the bridge produced itself.** That is the only JSON shape whose coercion is total and value-independent: any `0x`-prefixed even-length hex decodes to `DynSolValue::Bytes` and survives `convert_to_bytes` unchanged. Then on the Solidity side, `abi.decode(payload, (…))` against the *generated* interface types. The bridge — not foundry's heuristics — owns the encoding.

Concretely: the spec's answer becomes `{"result": "0x01000000…"}` where byte 0 is the outcome tag and the remainder is `abi.encode(...)` of the variant payload. This simultaneously fixes Pitfall 1, 2, 3, 4 and 5.

Two hex traps to encode into the generator, both from source:
- Odd-length hex is **left-padded with a zero nibble**, silently changing the value (`"0xabc"` → `0x0abc`). Always emit even-length.
- A hex payload of exactly **39 characters after `0x`** returns a hard error (`Cannot parse "…" as an address`). Even-length emission avoids it, but assert it in a test.

**Warning signs:**
- A JSON result that is an object, an array, a bare number, or a bare decimal string.
- A fuzz test that passes at 256 runs and fails at 10 000 with `EvmError: Revert` and no message.
- A test that reproduces from the persisted counterexample but not from a fresh seed, or vice-versa.
- `abi.decode` appearing directly on the `vm.rpc` return value rather than on a bridge-owned payload.

**Phase to address:** Phase 1 (wire result shape) and Phase 3 (Solidity interface generation must emit the decoder, not just the struct).

---

### Pitfall 3: `bytes memory b = vm.rpc(...)` sometimes reverts with no message and sometimes returns silent garbage **[MEASURED]**

**What goes wrong:**
The `Vm` interface declares `rpc(...) returns (bytes memory)`, but on `forge 1.5.1-stable` the raw returndata is `abi.encode(<coerced value>)` — *not* `abi.encode(<bytes>)`. Solidity's ABI decoder is then handed data that does not match `bytes`. Measured, typed call site `bytes memory b = vm.rpc("spec", m, "[]")`:

| Oracle result | Coerced to | Outcome |
|---|---|---|
| `"42"` | `string` | PASS, `b.length == 2` (correct-ish) |
| `"0xcdcd…"` (32 B) | `bytes` | PASS, `b.length == 32` (correct) |
| `"18446744073709551616"` | `uint256` | **FAIL — `EvmError: Revert`, no message** |
| `-5` | `int256` | **FAIL — `EvmError: Revert`, no message** |
| `{"tag":…,"guard":…,"tokenId":"0"}` | tuple | **PASS — and `b.length == 96`, pure garbage** |

The last row is the dangerous one. A struct result decodes "successfully" as `bytes` of a bogus length taken from the tuple's first head word. No revert, no warning — the differential test compares the contract's answer against nonsense and can agree with it by coincidence, or disagree for the wrong reason.

Note also that `master` and `1.5.1-stable` **differ here**: master wraps the payload in `DynSolValue::Bytes(payload).abi_encode()`, 1.5.1 does not. The wire behaviour of `vm.rpc` is therefore a function of the consumer's pinned Foundry version.

**Why it happens:**
Nobody tests the failure shape. The happy-path string case works, so the pattern gets copied, and the pathological shapes only appear once real domain values flow through.

**How to avoid:**
- Pin the exact Foundry version in `foundry.toml` (`solc` and the toolchain), and pin it *identically* in this repo's CI and in the consumer's. Record the pinned version in the generated Solidity header comment.
- Add a **Foundry-behaviour conformance test** to this repo's CI: a fixture oracle that returns each of the coercion classes above, asserting the observed shape. It fails loudly when Foundry changes coercion — which is exactly the drift the project claims to prevent, extended to the toolchain.
- Never call `vm.rpc` through the typed `Vm` interface for a domain method. Call it via `address(vm).call(abi.encodeWithSignature("rpc(string,string,string)", …))` so you own the `(bool success, bytes memory ret)` split — which you need for Pitfall 1 anyway.

**Warning signs:**
- `EvmError: Revert` with no message and no source line, from a test that does no `require`.
- Payload lengths that are suspiciously round (32, 64, 96) and don't match the spec's actual answer size.
- Any use of `vm.rpc` return value without a length assertion.

**Phase to address:** Phase 3 (Solidity interface generation) — the generator emits the low-level call site, never the typed one. Phase 5 (CI) owns the conformance fixture.

---

### Pitfall 4: `vm.rpcJson` is not available in the shipped toolchain **[MEASURED]**

**What goes wrong:**
`vm.rpcJson(alias, method, params) returns (string)` is the obvious escape hatch from Pitfall 2 — it returns the raw JSON with no coercion. It is documented at getfoundry.sh and present on `foundry-rs/foundry` master. It **does not exist in `forge 1.5.1-stable`**. Calling it yields:

```
[Revert] unknown cheatcode with selector 0x273b74f8; you may have a mismatch between the
`Vm` interface (likely in `forge-std`) and the `forge` version
```

— itself encoded as `CheatcodeError(string)` `0xeeaa9e6f`, i.e. **indistinguishable from a transport failure** by selector (Pitfall 1 again, now applied to the bridge's own tooling).

**Why it happens:**
Foundry's published cheatcode reference tracks master, not the latest release. Researching the docs and researching the installed binary give different answers, and the difference is invisible until runtime.

**How to avoid:**
Design against the coercion (Pitfall 2's hex-payload rule), which works on both versions, rather than against `rpcJson`, which works on neither reliably. If a later phase wants `rpcJson`, gate it behind a *capability probe* in CI — call it once against a fixture and assert `success == true` — rather than a version-string comparison.

**Warning signs:**
- A plan or design doc citing `vm.rpcJson` with a getfoundry.sh link and no `forge --version` check.
- `unknown cheatcode with selector` anywhere in a trace.
- forge-std bumped independently of the `forge` binary.

**Phase to address:** Phase 1 (transport shape decision) — record explicitly that `rpcJson` was checked and rejected as unavailable, with the version it was checked against.

---

### Pitfall 5: `null` is not a rejection — it is `0`, and `0` may be a legal answer **[MEASURED]**

**What goes wrong:**
Aeson's default record encoding (`omitNothingFields = False`) writes `Maybe` fields as JSON `null`. Foundry's coercion turns `Value::Null` into `FixedBytes(B256::ZERO, 32)`, which `convert_to_bytes` turns into 32 zero bytes. Measured: a `null` result comes back as `0x0000…0000` with `success == true`.

So a Haskell spec that models "guard violated" as `Nothing`, or a record with an absent optional field, produces **a successful RPC call returning zero**. If the Solidity side's rejection sentinel is also `0`, or if `tokenId == 0` is a legitimate value, the differential test compares zero to zero and passes. This is the exact "green light that means nothing" PROJECT.md warns about, reached by the most natural Haskell idiom available.

**Why it happens:**
`Maybe a` is the Haskell reflex for partiality. It is a *lossy* encoding of the three-outcome type: it collapses rejection into an absence, and JSON collapses absence into `null`, and Foundry collapses `null` into zero. Three lossy hops, no compile error at any of them.

**How to avoid:**
- Ban `Maybe` in the wire schema types (not in the spec — in the *protocol* types). The result type is an explicit tagged sum with a constructor per outcome, and its `ToJSON` is a hand-checked tagged encoding, not `genericToJSON` defaults.
- Add a property test asserting the encoder **never emits `null`** anywhere in a result document, for arbitrary inputs. This is cheap, mechanical, and catches every future field addition.
- Reserve no in-band sentinel. The tag byte carries the outcome; the payload carries only data.

**Warning signs:**
- `null` appearing in any captured request/response log.
- A `Maybe` in a type used by both the encoder and the Solidity generator.
- A Solidity helper with `if (tokenId == 0) return;` or `bytes32(0)` compared against a spec answer.
- Aeson options left at defaults on a wire type.

**Phase to address:** Phase 1 (protocol types) — enforce with a property test in the same phase, not later.

---

### Pitfall 6: A wedged oracle costs 45 seconds per fuzz case and the test still passes **[MEASURED]**

**What goes wrong:**
Two measurements, one test:

1. A server that accepts the connection and never responds causes `vm.rpc` to block for **45 seconds** before failing (foundry's `REQUEST_TIMEOUT`; `RpcEndpointConfig` exposes only `retries`, `retry_backoff`, `compute_units_per_second` — **no timeout knob** for `vm.rpc`, and the `retries` it does expose are wired into forking, not into `vm.rpc`).
2. The test **PASSED** anyway, because the call site ignored the return value:
   ```
   [PASS] test_hang() (gas: 4012) ... finished in 45.00s
   ```

At Foundry's default `fuzz.runs = 256`, a systematically wedged oracle is **3.2 hours** of green CI. On a self-hosted runner with no job timeout, it is an indefinitely occupied runner. And 45 s of *silence* per case is the single most likely way this project's CI gets abandoned.

**Why it happens:**
`vm.rpc` is synchronous (`foundry_common::block_on`) and a wedge is far more likely in a Haskell service than in a node — a `<<loop>>`, a blocked MVar, a non-allocating tight loop under a non-`-threaded` RTS, or a `Data.Map` lookup on a key whose `Ord` instance diverges. And the "test still passes" half is invisible: nothing in the trace says the test asserted nothing.

**How to avoid:**
- **Every** oracle call site asserts on `success`. Make this structural, not disciplinary: the generated `SpecHelper` should have no code path that returns without either producing a verdict or reverting. If the generator emits the call site, it can guarantee this.
- Give the *Haskell server* a hard per-request deadline (e.g. `System.Timeout.timeout`) well under 45 s — 2–5 s — so the oracle answers "I timed out" as a structured transport-level JSON-RPC error rather than letting Foundry's 45 s dominate. A fast negative beats a slow silence.
- Set an explicit CI job `timeout-minutes` on the test job. Absent one, GitHub Actions runs to the 6-hour limit; a self-hosted runner runs forever.
- Assert a **wall-clock budget** in CI: if the differential suite exceeds N minutes, fail. A suite that suddenly takes 40× longer is a wedged oracle even when it is green.

**Warning signs:**
- Suite duration jumping by an order of magnitude with no test-count change.
- Any test containing `address(vm).call(...)` whose `success` is unused (`ok;` to silence the compiler is the tell).
- `finished in 45.00s` — or any multiple of 45 — in a suite that should be milliseconds.
- Zero assertions counted in a passing differential test.

**Phase to address:** Phase 2 (server: request deadline), Phase 3 (generated call site asserts), Phase 5 (CI timeout + duration budget).

---

### Pitfall 7: The health method proves the wrong thing

**What goes wrong:**
REQ says *"a payload-free health/echo method is exercisable end-to-end, proving the transport shape independently of any domain method."* The natural implementation — `spec_health` returning `"ok"` — proves almost nothing that matters. `"ok"` coerces to a Solidity `string`, which is one of the *few* shapes that decodes cleanly (Pitfall 3). A green health check therefore tells you the socket is open while saying nothing about whether domain payloads survive the coercion, whether rejections are distinguishable, or whether the generated interface matches.

Worse, it becomes the thing people check when a domain method breaks — "health is green, must be the spec" — and misdirects debugging.

**Why it happens:**
"Health check" is a well-worn pattern with a well-worn shape, and the well-worn shape is a string.

**How to avoid:**
Make the health method return **the exact wire shape a domain method returns** — the hex-payload envelope with the outcome tag — carrying a known constant. Then it genuinely proves the transport shape. Add a second fixture method that deliberately returns a *rejection* and a third that deliberately returns a *transport-level* JSON-RPC error, so the Solidity side's three-way classifier is exercised end-to-end without any domain logic. Three fixture methods, not one.

**Warning signs:**
- A health method whose return type differs from every domain method's.
- No fixture method that produces a rejection.
- A Solidity classifier whose rejection branch has never executed in CI.

**Phase to address:** Phase 2 (server + health), extended to a three-method fixture suite. This is the cheapest possible insurance against Pitfall 1 regressing.

---

### Pitfall 8: The "generated" Solidity interface goes stale because nothing fails when it does

**What goes wrong:**
The central claim — *"a wire contract change breaks the build instead of drifting"* — holds only if the generated artifact is **regenerated and compared** in CI. The common failure: the generator is a `cabal run gen-solidity > out/ISpec.sol` that a human runs, the output is committed, and CI builds the committed file. A Haskell field rename then changes the wire format, nobody reruns the generator, the committed `.sol` still compiles, and the drift the project was built to prevent happens anyway — with a false sense of safety on top.

Two specific accelerants here:
- Under Pitfall 2's alphabetical-tuple coercion, a **rename** reorders fields with no type change. `tokenId → id` moves a field from last to first. The Solidity struct still compiles. The values are wrong.
- If the generator reads the *spec's* types (via `cfmm-vol-markets-spec`), then a spec-side change with no bridge-side commit changes the correct output — so "the file hasn't changed since I last generated it" is not evidence.

**Why it happens:**
Generate-and-commit is the path of least resistance, and the check ("is the committed file what the generator produces *right now*?") is an extra CI step that feels redundant on the day you write it.

**How to avoid:**
A CI job that runs the generator and does `git diff --exit-code` on the output. Non-zero exit = "generated artifact is stale" with a message telling the developer the exact command to run. This is the only thing that makes the project's headline claim true. It must run on every PR, including PRs that touch only the spec submodule pointer.

Additionally, generate a **schema digest** (a hash over the ordered field names and types of every wire type) into both the Haskell side and the Solidity side, and have the server return it from the health method. The Solidity helper asserts the digest matches at test start. This catches the case where the generated file is current but the *running server* is an older binary — which the diff check cannot catch.

**Warning signs:**
- A generated file with no `// GENERATED — do not edit` header, or with one that a human has edited.
- A PR that changes a Haskell wire type but not the `.sol`.
- No CI step whose name contains "check" or "verify" for the generated artifact.
- The consumer running against a server binary built from a different commit than the `.sol` they compiled.

**Phase to address:** Phase 3 (generation) for the generator + digest; Phase 5 (CI) for the `git diff --exit-code` gate. Neither phase is complete without the other.

---

### Pitfall 9: Bottom values escape as HTTP 500, not as a typed rejection — and Haskell's laziness moves *where* they escape

**What goes wrong:**
The spec is Haskell, and Haskell specs contain `error`, `undefined`, incomplete patterns, `head`, `fromJust`, `toEnum`, and `div`. A guard-violating fuzz input hits one, and the thunk does not blow up in the handler — it blows up later, wherever the value is finally forced. Two distinct bad outcomes:

- **Forced during encoding.** The handler returns cleanly, Servant/Warp forces the lazy `ByteString` while computing `Content-Length`, the `ErrorCall` propagates out of the WAI application, and Warp's `defaultOnExceptionResponse` returns **HTTP 500** with a non-JSON body. Foundry sees `HTTP error 500 with body: …` — a **transport failure** (Pitfall 1). A guard violation has been reported as a broken bridge. `REQ: guard-violating inputs return a typed rejection, not a crash` is silently unmet.
- **Forced after headers are committed** (streaming responses, `responseStream`). The client gets a truncated body, `alloy` fails to deserialize, and Foundry reports a *parse* error — a third flavour of the same flattened channel. Servant issue [#1192](https://github.com/haskell-servant/servant/issues/1192) documents that Warp has no clean way to translate these into a custom response.

**Why it happens:**
`throwError`-style handling covers *your* explicit failures. It does not cover bottoms inside a dependency you don't own — and this bridge *deliberately* does not modify the spec's model (`REQ: without modifying the spec's own types`). The spec's partiality is inherited, not authored.

**How to avoid:**
- Force the answer to normal form **inside** the handler, under a catch: `try (evaluate (force answer))` with `NFData` on the result type, catching at least `ErrorCall`, `ArithException`, `PatternMatchFail`, and `ArrayException`. Map the caught exception to a **typed rejection** carrying the exception text as the "rejecting guard" — not to a 500.
- Use `responseLBS`-style (non-streaming) responses only. Never `responseStream` for spec answers.
- Install a top-level `setOnExceptionResponse` that emits a **well-formed JSON-RPC error object** rather than Warp's default 500-with-text-body — so even the truly unexpected case arrives as structured data rather than as an HTTP-layer failure.
- Add an `NFData` constraint on the result type in the protocol module. It makes "this type can be fully forced before we commit a status" a compile-time property.

**Warning signs:**
- `HTTP error 500 with body:` in any forge trace.
- Server stderr containing `Prelude.head: empty list`, `Non-exhaustive patterns`, `divide by zero`, `Irrefutable pattern failed`.
- A handler whose type is `IO Result` with no `evaluate`/`force`.
- A rejection count of zero across a full fuzz run when the spec demonstrably has guards.

**Phase to address:** Phase 2 (server) for the catch-and-force boundary and the Warp exception response; Phase 4 (`volOrderToTokenId` integration) for verifying real guard violations actually produce rejections, with a fixture input that is known to violate.

---

### Pitfall 10: The warm process is the whole point, and statefulness is what kills it

**What goes wrong:**
The transport decision was explicitly justified by *"a warm service avoids per-case process spawn."* Warmth is exactly what makes cross-case contamination possible, and `vm.ffi` (the rejected alternative) would have been immune by construction. Concrete leaks:

- A memo cache keyed on something that isn't the full input — case *N* returns case *M*'s answer. Under fuzzing, this looks like a random, unreproducible divergence.
- An `IORef`/`MVar` counter, RNG seed, or "last request" used anywhere in the answer path.
- Aeson's `Value` retained by a logger, growing the heap monotonically across 256 × M calls. GHC's generational GC will not reclaim a retained thunk; RSS climbs, the runner starts swapping, and latency per call rises through the run — turning a 5 ms oracle into a 500 ms one by case 200.
- A lazy `Data.Map` accumulator of thunks (`insertWith (+)`) — the classic Haskell space leak, invisible at 10 requests and fatal at 100 000.
- Test-ordering dependence: `forge test` parallelises across test *contracts*, so concurrent requests hit the shared server. Any shared mutable state is now a race.

**Why it happens:**
The service is written and tested with a handful of manual `curl` calls where none of this shows. Fuzzing is the first time it sees sustained concurrent load, and by then it is integrated into someone else's CI.

**How to avoid:**
- **Make the handler a pure function of its request, structurally.** No `IORef`, no `MVar`, no cache, no logging that retains payloads, in the answer path. If the spec needs an environment, build it once at startup and pass it immutably.
- Build the executable with `-threaded -rtsopts "-with-rtsopts=-N"`. Without `-threaded`, a non-allocating spec computation blocks the Warp timeout manager and *every* other connection — turning one slow case into a suite-wide wedge (Pitfall 6).
- Add a **soak test** to this repo's CI: N ≫ 256 sequential requests plus a concurrent burst, asserting (a) identical answers for identical inputs, (b) answers independent of request order, (c) RSS growth bounded. Cheap, and it is the only test that can catch a leak before the consumer's fuzz run does.
- Log request/response pairs to a file (append-only, `Text`/`ByteString`, not retained) so a divergence is reproducible from the log, not just from the fuzz seed.

**Warning signs:**
- RSS climbing monotonically during a fuzz run (`ps` the server before and after).
- Per-call latency rising through a run.
- A divergence that does not reproduce when the failing input is replayed alone.
- Any `IORef` or `unsafePerformIO` in a module reachable from the handler.

**Phase to address:** Phase 2 (server: purity + `-threaded`), Phase 5 (CI: soak test and RSS assertion).

---

### Pitfall 11: The CI job that starts a background service and doesn't reliably stop it

**What goes wrong:**
Both this repo's gate and the consumer's need a Haskell process running while `forge test` runs. The naive shape — `cabal run server & ; forge test` — fails in at least five distinct ways, and each one is a *flaky red or a silent green*:

- **Race between start and connect.** `sleep 5` is not a readiness check. On a cold self-hosted runner under load, GHC's RTS startup plus the spec's initialisation can exceed it. The result is a connection-refused on the first fuzz case, which — if any call site is unasserted — is a silent green (Pitfall 6).
- **Zombie on failure.** If `forge test` fails, the `&&`-chained `kill` never runs. On a **self-hosted** runner (the consumer's situation) the process outlives the job and holds the port. GitHub-hosted runners are ephemeral and hide this entirely — so this repo's hosted-CI choice actively *conceals* the bug that will bite the consumer.
- **Port collision.** Two concurrent jobs on one self-hosted runner both bind 8545/8599. Second job gets `EADDRINUSE`, or — worse — connects to the *first job's* server and silently tests against a different binary.
- **Silent death.** The server exits (OOM, exception in `main`) and the job continues; every subsequent case is a transport failure that unasserted call sites swallow.
- **No logs on failure.** The server's stderr goes to a file nobody uploads, so a red CI run gives you a Solidity revert message and nothing about *why* the oracle refused.

**Why it happens:**
The pattern works on the first try on a laptop, and hosted runners' ephemerality masks the leak permanently.

**How to avoid:**
- **Poll for readiness, don't sleep.** Loop on the health method (Pitfall 7's real-shape one) until it returns the expected payload, with a bounded retry count, then fail the job explicitly with the server log if it never comes up. `curl --retry-connrefused --retry N --retry-delay 1`.
- **Bind an ephemeral port; have the server print the bound port.** Write it into `foundry.toml`'s `rpc_endpoints` (or an env var referenced as `${SPEC_RPC_URL}`) at job time. This eliminates collisions on shared runners and makes concurrent jobs safe.
- **Always-run teardown.** `if: always()` step, kill by recorded PID, and additionally verify the port is free. On self-hosted, add a pre-job sweep that kills any stale server before starting.
- **Always-upload the server log** with `if: always()`, and print the last N lines inline on failure. A red differential test whose only artifact is `EvmError: Revert` is unactionable.
- **Assert the service is still alive after the suite**, not just before. A post-suite health check turns "server died at case 40" from a silent pass into a red.
- Prefer a **GitHub Actions `services:` container** or a `docker run` for the oracle over a bare background process, if the Haskell binary is containerised. Docker gives you lifecycle and log capture for free and eliminates the zombie class entirely. Given the global preference for Docker-based installation in this environment, this is worth costing in Phase 5 rather than retrofitting.

**Warning signs:**
- `sleep` in a CI workflow.
- A `kill` step without `if: always()`.
- A hardcoded port number.
- CI that is green on hosted runners and flaky on self-hosted — this is the signature.
- A failing CI run with no server-side log artifact.

**Phase to address:** Phase 5 (CI gate). **And this pitfall is the reason to reconsider the hosted-only CI decision:** hosted runners cannot exercise the zombie/collision/self-hosted class at all, so choosing hosted CI does not merely *defer* the consumer's `GHC-on-self-hosted` risk — it makes this repo's CI structurally incapable of detecting the failures that risk will produce. Recommend at least one self-hosted-shaped job (or a container that mimics a persistent runner) before declaring integration ready.

---

### Pitfall 12: Haskell CI build time and cache invalidation make the gate unusable

**What goes wrong:**
A cold `cabal build` of a Servant/Warp/aeson stack is routinely 20–40 minutes on a 2-core hosted runner. Two specific traps compound it:

- **The classic Cabal-cache trap**: caching `~/.cabal/store` and `dist-newstyle` appears to work — dependencies are reused — but *your own package rebuilds every run anyway*, because `actions/checkout` writes fresh mtimes and GHC's recompilation check is mtime-based (documented in the widely-cited [raehik writeup](https://raehik.github.io/2021/03/01/caching-stack-and-cabal-haskell-builds-on-github-actions.html)). You pay the cache-restore cost *and* the rebuild cost. Fix: restore file mtimes to last-commit time, or accept the rebuild and only cache the store.
- **Submodule-driven invalidation**: the cache key is normally derived from `cabal.project.freeze`. But this project depends on `cfmm-vol-markets-spec` as a **source dependency**, so a spec submodule bump changes nothing in the freeze file while invalidating the build. Either the cache key includes the submodule SHA (correct) or the cache goes stale-but-used (silently building against the wrong spec) or is over-invalidated.
- **`GHC on the self-hosted runner is unverified`** (PROJECT.md's own carried risk) is *understated*: the runner must not merely have GHC, it must have GHC **plus** a C toolchain, `zlib`/`libgmp` dev headers, and enough RAM. GHC's simplifier on a Servant type-level API routinely needs 3–4 GB; a runner with 2 GB OOM-kills the build with a message that looks like a random crash.

**Why it happens:**
Haskell CI cost is front-loaded and easy to underestimate, and the cache-that-doesn't-cache failure is invisible (it just looks slow, not broken).

**How to avoid:**
- Cache key = hash of `cabal.project.freeze` **+ the spec submodule SHA + GHC version**. Include GHC version explicitly; a `haskell-actions/setup` bump silently invalidates everything and you want that legible.
- Commit a `cabal.project.freeze`. Without it, dependency resolution drifts and yesterday's green build is not reproducible — which for a *spec oracle* is a correctness issue, not just a convenience one.
- Split CI into a fast gate (build library + protocol tests + generated-artifact diff, no Foundry) and a slow gate (server + `forge test` integration). The fast gate must stay under ~5 minutes or the two-step review process stalls behind it.
- **Verify GHC/cabal on the consumer's self-hosted runner early — as a throwaway probe job, in Phase 0 or 1**, not at integration. It is a 10-minute experiment that de-risks the entire distribution requirement, and PROJECT.md's decision to defer it is the single largest schedule risk in the plan.

**Warning signs:**
- Cache "hit" reported but build time unchanged.
- `ghc: out of memory` or a bare `Killed` in the build log.
- Build time creeping upward run over run (cache key too specific → never hits).
- No `cabal.project.freeze` in the repo.

**Phase to address:** Phase 0/1 (self-hosted GHC probe), Phase 5 (CI structure and cache keys).

---

### Pitfall 13: The spec diamond — the consumer resolves two different `cfmm-vol-markets-spec` versions

**What goes wrong:**
PROJECT.md names the topology; here is what it actually costs. The consumer pins `spec/` as its own submodule **and** pins `evm-spec-bridge`, which itself pins `cfmm-vol-markets-spec`. Concretely:

- **Two checkouts, two SHAs.** `cfmm-vol-markets/spec` at SHA A; `cfmm-vol-markets/lib/evm-spec-bridge/spec` at SHA B. Nothing forces A == B. Git submodules have no resolution step — no "nearest wins", no conflict, no warning. Both are just directories.
- **The failure is a false divergence.** The bridge answers using spec@B. The consumer believes it is testing spec@A. A fuzz case where A and B differ produces a red differential test that blames Plank for a discrepancy that is actually spec-version skew. Engineers then "fix" Plank to match the wrong spec.
- **Or a false agreement**, if the skew happens to cancel — which is the worse half.
- **Cabal makes it worse if both end up in one build plan.** If the consumer ever links the bridge as a Haskell dependency alongside its own spec checkout, Cabal will either fail with a confusing duplicate-package error or silently pick one, depending on `packages:` stanza layout.
- **Every spec change costs four PRs.** `JMSBPP/cfmm-vol-markets-spec` → PR → `d2p-finance/cfmm-vol-markets-spec`; then bump in `JMSBPP/evm-spec-bridge` → PR → canonical; then bump the bridge pointer in `JMSBPP/cfmm-vol-markets` → PR → canonical. Under the fork→PR rule with two-step review on each, a one-line spec fix is a multi-day round trip. This is *correct process*, but it must be planned for — a design that requires frequent spec changes is far more expensive here than the diff size suggests.

**Why it happens:**
Submodule diamonds are invisible. `git submodule status --recursive` shows both, but nobody runs it, and no build tool complains.

**How to avoid:**
- **Make the skew loud.** Compile the spec's commit SHA into the server binary (via a generated module or `gitrev`) and return it from the health method. The consumer's `SpecHelper` asserts it equals the SHA of the consumer's own `spec/` checkout, read via `vm.readFile`/`vm.envString` at test setup. **A mismatch fails the suite immediately with a clear message** instead of producing a mystery divergence 200 fuzz cases later. This single check retires the entire diamond risk class.
- Add `git submodule status --recursive` to CI output on both sides. Free, and makes the diamond visible in every log.
- **Prefer eliminating the diamond**: if the consumer can consume the spec *only* through the bridge, there is one pin. That is a consumer-side decision (and per PROJECT.md's scope rule, theirs to make) — but it should be put to them explicitly as a question, with this failure mode attached, rather than left implicit.
- Batch spec changes. Given the four-PR cost, a phase that expects iterative spec tweaking should be resequenced to front-load them.

**Warning signs:**
- `git submodule status --recursive` showing two paths ending in `cfmm-vol-markets-spec` at different SHAs.
- A differential failure that reproduces in CI but not locally (or vice-versa) — classic skew signature.
- Any PR that bumps one spec pointer without the other.

**Phase to address:** Phase 1 (SHA in the health payload — it is part of the protocol), Phase 6 (consumer integration: the assertion + the explicit question about collapsing the diamond).

---

### Pitfall 14: Building against a contract two other agents are still negotiating

**What goes wrong:**
Two decisions this project depends on are, by PROJECT.md's own account, **not this project's to make**: the RPC-02 responsibility split (who owns decode / validation / guard evaluation / error classification) and the `VolOrder(T)` wire format (Shock-style tagged vs per-variant, owned by the consumer's Phase 4). A third party — the agent owning the consumer's planning tree — has been sent the decision set and had not replied.

The failure mode is not "we build the wrong thing." It is subtler and more common: **the bridge builds a defensible default, ships it, and the default becomes the decision by inertia.** By the time the consumer's agent replies, changing course costs a rewrite plus a cross-repo PR chain (Pitfall 13), so nobody changes course. The project then has, in fact, pre-empted exactly the decision it documented as not-ours — repeating the transport-decision tension it explicitly flagged as a mistake to avoid.

The second-order cost is trust: the consumer's agent discovers its Phase 4 decision was made for it, which makes the *next* handoff harder.

**Why it happens:**
Being blocked is uncomfortable and a "temporary" placeholder is always available. Also: the RPC-02 split *sizes this project* — PROJECT.md says so — so you cannot plan phases without an answer, and planning pressure forces the guess.

**How to avoid:**
- **Sequence around it, don't guess through it.** Phases 1–3 (protocol envelope, three-outcome type, server, health/fixture methods, generator, CI) are *entirely independent* of both open decisions. That is a genuinely large, genuinely valuable slice. Build it, and let the codec phase (4) be the one that blocks. This is the strongest argument for a specific phase ordering in the roadmap.
- **Make the codec a plugged-in module, not a baked-in assumption.** The envelope carries opaque bytes (Pitfall 2's hex payload); the codec that interprets them is one module with one type class. Both `VolOrder` layouts are then a same-day change rather than a rewrite. Note this is *not* the "domain-agnostic abstraction" the project scoped out — it is a single seam in a single module, not a reusable core.
- **Write down the placeholder as a placeholder.** If a default is needed to make progress, record it in Key Decisions as `PROVISIONAL — reverts to open if not confirmed by <date>`, and set a real date. An unmarked provisional decision is indistinguishable from a real one after two weeks.
- **Time-box the wait.** If no reply by the date, escalate to the user rather than deciding unilaterally — the user has already shown willingness to make these calls, and that is the legitimate path.

**Warning signs:**
- A `VolOrder` codec with concrete field offsets appearing before the consumer's Phase 4 has an answer.
- Key Decisions entries flipping from `OPEN` to `— Pending` with no recorded external input.
- Bridge code that would need to change if the responsibility split lands the other way, outside the designated codec module.
- The consumer's ROADMAP still describing Phase 5 as "build the transport" while this repo has already shipped one.

**Phase to address:** Roadmap sequencing itself — put the two open decisions on the critical path *explicitly*, with the independent slice ahead of them. Revisit at every phase boundary.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|---|---|---|---|
| Rejection as a JSON-RPC `error` object | Idiomatic JSON-RPC; `servant-jsonrpc` hands it to you | Destroys XPORT-02 outright; indistinguishable from a dead server (Pitfall 1) | **Never** |
| JSON result as an object/number instead of a hex payload | Human-readable in `curl` | Value-dependent ABI type; alphabetical field reordering; silent garbage decode (Pitfalls 2, 3) | Only for a debug-only method never called from Solidity |
| `Maybe` in the wire result type | Natural Haskell | `null` → `bytes32(0)` → false agreement (Pitfall 5) | **Never** in protocol types |
| Generate the `.sol` by hand-run script, commit output | Fast; no CI work | The project's headline anti-drift claim becomes false (Pitfall 8) | Only before the first consumer integration, and only with a tracked TODO |
| `sleep 5` for service readiness in CI | One line | Flaky red or silent green; worse on loaded self-hosted runners (Pitfall 11) | **Never** — `curl --retry-connrefused` is also one line |
| Hosted-only CI | Greenfield iteration speed (the stated rationale) | Structurally cannot detect zombie/port-collision/self-hosted-toolchain failures, i.e. the consumer's actual environment (Pitfalls 11, 12) | Acceptable for Phases 1–3; must be joined by a self-hosted-shaped job before Phase 6 |
| No `cabal.project.freeze` | Skips a step | Non-reproducible oracle answers across time; broken cache keys (Pitfall 12) | Never for an oracle — reproducibility *is* the product |
| In-process memo cache for spec answers | Latency under fuzzing | Cross-case contamination; unreproducible divergences (Pitfall 10) | Only if keyed on the full canonical request bytes and covered by the soak test |
| Provisional `VolOrder` codec ahead of the consumer's Phase 4 | Unblocks the demo | Pre-empts a decision explicitly scoped out; becomes permanent by inertia (Pitfall 14) | Only inside the designated codec seam, marked `PROVISIONAL` with a date |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|---|---|---|
| Foundry `vm.rpc` | Calling it through the typed `Vm` interface (`bytes memory b = vm.rpc(...)`) | Low-level `address(vm).call(...)` so you own `(bool success, bytes memory ret)` — required for the three-way split *and* avoids the un-messaged ABI-decode revert (Pitfall 3) |
| Foundry `vm.rpc` | Assuming `success == false` means "the spec said no" | `success == false` means **transport failure only**; the spec's verdict lives in the successful payload's tag byte |
| Foundry `vm.rpc` | Relying on `vm.rpcJson` for uncoerced JSON | Not in `forge 1.5.1-stable` (Pitfall 4); probe for it in CI before depending on it |
| Foundry `foundry.toml` | Hardcoding the oracle port in `[rpc_endpoints]` | `spec = "${SPEC_RPC_URL}"` with the ephemeral bound port injected at job time (Pitfall 11) |
| Foundry timeouts | Expecting a configurable per-call timeout | There is none for `vm.rpc`; `RpcEndpointConfig` has only `retries`/`retry_backoff`/`compute_units_per_second`, and those aren't wired to `vm.rpc`. Budget on the **server** side |
| Warp/Servant | Letting handler exceptions reach Warp's default handler | `setOnExceptionResponse` emitting a JSON-RPC error object; `try (evaluate (force x))` inside the handler (Pitfall 9) |
| Warp | Streaming responses for spec answers | `responseLBS`-shaped only, so the status is never committed before the body is known-good |
| aeson | `genericToJSON` defaults on wire types | Explicit, tested options; `omitNothingFields` moot because `Maybe` is banned; property-test that `null` never appears |
| aeson | Encoding EVM integers as JSON numbers | Even the `uint256` path goes through `f64` in foundry's coercion. Encode inside the hex payload; never as a JSON number |
| Git submodules | Assuming one `cfmm-vol-markets-spec` resolves | Two independent checkouts, no resolution. Assert the SHA over the wire (Pitfall 13) |
| `cabal` + submodule source deps | Cache key from `cabal.project.freeze` alone | Include the spec submodule SHA and the GHC version in the key |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|---|---|---|---|
| Wedged oracle × Foundry's 45 s timeout | Suite duration in hours; `finished in 45.00s` multiples | Server-side `timeout` of 2–5 s; CI `timeout-minutes`; wall-clock budget assertion | Immediately at `fuzz.runs = 256` — 3.2 h |
| New HTTP client per `vm.rpc` call | TIME_WAIT socket accumulation; `EADDRNOTAVAIL` on long runs | Keep-alive is client-side and not under your control; instead keep per-call latency low and consider raising `fuzz.runs` only after measuring | ~10k–28k calls on a default ephemeral port range |
| Sequential blocking calls | Suite time = runs × RTT, linearly | Keep the oracle p99 in single-digit ms; measure it in CI, don't assume it | 256 runs × 20 ms = 5 s (fine); × 200 ms = 51 s (not) |
| Space leak in the warm server | RSS climbing through the run; latency drifting upward | No retained state in the answer path; soak test with an RSS bound; strict accumulators | Somewhere between 1k and 100k requests — i.e. exactly at fuzz scale, never at `curl` scale |
| Non-`-threaded` RTS + non-allocating spec computation | One slow case wedges *all* connections, including the health check | `-threaded -rtsopts "-with-rtsopts=-N"` | First concurrent request during a tight loop |
| Cold Haskell CI build | 20–40 min gate; review process stalls behind it | Split fast/slow gates; correct cache keys; mtime restoration | Every cache miss |
| Concurrent `forge test` contracts hitting one server | Intermittent wrong answers, order-dependent | Pure handler (mandatory anyway); concurrency in the soak test | As soon as the consumer has two test contracts |

---

## Security Mistakes

Threat model is narrow — a localhost dev/CI service — but three items are real:

| Mistake | Risk | Prevention |
|---|---|---|
| Binding `0.0.0.0` instead of `127.0.0.1` | On a **shared self-hosted runner**, another job (or another tenant) reaches the oracle, and the oracle can be made to answer from the wrong spec version — a correctness attack on the differential test, not just an info leak | Bind loopback explicitly; make the bind address a required, not defaulted, argument |
| Unbounded request body / recursion depth in the JSON decoder | A fuzz-generated giant payload OOMs the server mid-run → every subsequent case is a transport failure, silently green if any call site is unasserted | `setMaximumBodyFlush` / explicit body size limit; bounded decoder depth; reject oversize with a structured error |
| Echoing untrusted input into the error message | Log injection and, more practically, a `CheatcodeError(string)` message so large it is unreadable in the trace | Truncate and sanitise the rejecting-guard text to a bounded length before it enters the wire |
| Reading RPC URLs / secrets from `foundry.toml` `${VAR}` without them being set | `rpcUrl()` reverts with a confusing message that looks like a bridge bug | Assert required env vars at CI job start, before `forge test` |

---

## "Looks Done But Isn't" Checklist

- [ ] **Three-outcome distinction:** often "done" as three Haskell constructors with no Solidity-side test that a rejection and a dead server produce *different* observable results. Verify: a fixture method returning a rejection and a stopped server both run in CI, and the classifier distinguishes them.
- [ ] **Generated Solidity interface:** often committed but not verified. Verify: CI runs the generator and `git diff --exit-code`; deliberately rename a Haskell field on a branch and confirm CI goes red.
- [ ] **Health method:** often returns `"ok"`, proving only that a socket is open. Verify: it returns the same envelope shape as a domain method and carries the spec commit SHA.
- [ ] **Guard-violating input returns a typed rejection:** often "done" via `throwError`, which doesn't cover bottoms in the unmodified spec. Verify: a fixture input that triggers a `head []`/incomplete pattern *inside the spec* still yields a rejection, not HTTP 500.
- [ ] **Warm across test cases:** often verified with two manual calls. Verify: a soak run of ≥5 000 requests with identical-input determinism and bounded RSS growth.
- [ ] **Unreachable server reported distinguishably:** often tested by killing the server between runs. Verify: killed *mid-suite*, and confirm the suite goes **red**, not green — this is the vacuity check.
- [ ] **`vm.rpc` payload decoding:** often tested with one small value. Verify: values spanning the coercion boundaries — below and above 2^64, negative, zero, empty, and a 32-byte payload.
- [ ] **Submodule pinning:** often "done" as `git submodule add`. Verify: `git submodule status --recursive` in CI, and the over-the-wire SHA assertion.
- [ ] **CI teardown:** often "done" with a `kill` step. Verify: force a test failure and confirm no orphaned process holds the port afterwards; run two jobs concurrently.
- [ ] **Fuzz assertions actually run:** verify the differential test *fails* when the contract is deliberately mutated. A test that has never been seen red has not been seen.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---|---|---|
| Rejection shipped as JSON-RPC error object | MEDIUM | Move rejection into the `result` envelope; change is confined to encoder + classifier if the envelope exists. HIGH if the consumer already wrote string-matching logic — that must be deleted, not adapted |
| JSON result shape is an object/number | MEDIUM | Wrap in the hex-payload envelope; regenerate the `.sol`; four-PR chain if the consumer pinned it (Pitfall 13) |
| `Maybe`/`null` in the wire schema | LOW if caught before integration | Replace with explicit tags; add the no-`null` property test |
| Generated artifact drifted | LOW to catch, HIGH to trust | Regenerate, diff, then **re-run the full differential suite** — any prior green results are void and must be re-established, not assumed |
| Vacuous test discovered late | HIGH | Every prior green run is worthless. Audit all call sites for unasserted `success`; re-run the full suite; treat the whole prior result set as unknown |
| Spec version skew | MEDIUM | Add the wire SHA assertion, align pins, re-run. The expensive part is re-litigating any "fix" made to Plank to match the wrong spec |
| Space leak / statefulness found under fuzzing | MEDIUM | Purify the handler; add soak test. Prior divergence reports are suspect and must be replayed |
| Provisional codec became permanent by inertia | HIGH | Cross-repo redesign under the fork→PR chain, plus the trust cost with the consumer's agent. Prevention is enormously cheaper than recovery |

---

## Pitfall-to-Phase Mapping

Phase names below are *recommended* — the roadmap does not exist yet. The ordering matters: everything through Phase 3 is independent of the two open decisions (Pitfall 14), so that slice should come first.

| Pitfall | Prevention Phase | Verification |
|---|---|---|
| 1 — Three outcomes on one channel | **Phase 1 — Protocol core** | Fixture rejection + stopped server produce different classifications in a CI-run Solidity test |
| 2 — Value-dependent coercion | **Phase 1 — Protocol core** (envelope), **Phase 3** (generator emits decoder) | Boundary-value test: results below/above 2^64, negative, zero, empty, 32-byte |
| 3 — Typed `vm.rpc` decode | **Phase 3 — Generation** | Generated call site uses low-level `.call`; Foundry-coercion conformance fixture in CI |
| 4 — `rpcJson` unavailable | **Phase 1 — Protocol core** | Capability probe in CI; pinned `forge --version` recorded |
| 5 — `null` → zero | **Phase 1 — Protocol core** | Property test: encoder never emits `null` for arbitrary inputs |
| 6 — 45 s wedge / vacuous pass | **Phase 2 — Server**, **Phase 3** (asserting call site), **Phase 5 — CI** | Kill the server mid-suite; suite must go **red**. Wall-clock budget assertion |
| 7 — Health proves nothing | **Phase 2 — Server** | Three fixture methods (ok / rejection / transport error), all exercised in CI |
| 8 — Stale generated artifact | **Phase 3 — Generation**, gated in **Phase 5 — CI** | `git diff --exit-code` on regenerated output; schema digest returned over the wire |
| 9 — Bottoms escape as HTTP 500 | **Phase 2 — Server**, verified in **Phase 4 — Codec/`volOrderToTokenId`** | A known guard-violating input yields a typed rejection; zero `HTTP error 500` in traces |
| 10 — Warm-process statefulness | **Phase 2 — Server**, **Phase 5 — CI** | Soak test: determinism, order-independence, bounded RSS |
| 11 — CI service lifecycle | **Phase 5 — CI** | Forced failure leaves no zombie; two concurrent jobs both pass; server log always uploaded |
| 12 — Haskell CI cost / GHC availability | **Phase 0/1 — throwaway self-hosted probe**, **Phase 5 — CI** | Probe job builds and *runs* the server on the consumer's runner; fast gate under 5 min |
| 13 — Spec submodule diamond | **Phase 1** (SHA in the health payload), **Phase 6 — Consumer integration** | `git submodule status --recursive` in CI; wire-SHA assertion fails a deliberately skewed pin |
| 14 — Building a contract still under negotiation | **Roadmap sequencing**, revisited every phase boundary | Phases 1–3 contain nothing that depends on RPC-02 or the `VolOrder` layout; open decisions carry a dated `PROVISIONAL` marker |

---

## Sources

**Primary — read from source (HIGH):**
- [`foundry-rs/foundry` — `crates/cheatcodes/src/evm/fork.rs`](https://github.com/foundry-rs/foundry/blob/master/crates/cheatcodes/src/evm/fork.rs) — `rpc_call`, `rpc_json_call`, `rpc_result`, `convert_to_bytes`
- [`foundry-rs/foundry` — `crates/cheatcodes/src/json.rs`](https://github.com/foundry-rs/foundry/blob/master/crates/cheatcodes/src/json.rs) — `json_value_to_token` coercion heuristics (alphabetical object ordering, number/string/null branches)
- [`foundry-rs/foundry` — `crates/cheatcodes/src/error.rs`](https://github.com/foundry-rs/foundry/blob/master/crates/cheatcodes/src/error.rs) — `CheatcodeError(string)` encoding
- [`foundry-rs/foundry` — `crates/config/src/endpoints.rs`](https://github.com/foundry-rs/foundry/blob/master/crates/config/src/endpoints.rs) — `RpcEndpointConfig` (no timeout field)

**Primary — measured (HIGH):**
- Live `forge test` probes against a stub JSON-RPC oracle, `forge 1.5.1-stable` / `b0a9dd9`, solc 0.8.34, 2026-08-27. Reproduced: three-way outcome flattening onto `0xeeaa9e6f`; alphabetical tuple ordering; magnitude-dependent `string`↔`uint256` coercion; `null` → 32 zero bytes; typed-interface revert vs silent-garbage decode; `vm.rpcJson` absent; 45.00 s hang with a passing test.
- `cast sig "CheatcodeError(string)"` → `0xeeaa9e6f`

**Secondary (MEDIUM):**
- [Foundry cheatcode reference — `rpc`](https://getfoundry.sh/reference/cheatcodes/rpc/) — note: documents `rpcJson`, which is not in 1.5.1-stable
- [Foundry `assume` reference](https://book.getfoundry.sh/cheatcodes/assume) and [`max_test_rejects` discussion](https://github.com/foundry-rs/foundry/issues/1202)
- [Warp `Network.Wai.Handler.Warp` docs](https://hackage-content.haskell.org/package/warp-3.4.15/docs/Network-Wai-Handler-Warp.html) — 30 s default slowloris timeout; `defaultOnExceptionResponse` → 500
- [servant issue #1192 — "Proper servant-server exception handling for warp/wai"](https://github.com/haskell-servant/servant/issues/1192)
- [servant issue #1022 — impure exceptions in servant-server](https://github.com/haskell-servant/servant/issues/1022)
- [raehik — "Caching Stack and Cabal Haskell builds on GitHub Actions"](https://raehik.github.io/2021/03/01/caching-stack-and-cabal-haskell-builds-on-github-actions.html) — the mtime-based cache-miss trap
- [`haskell-actions/setup`](https://github.com/haskell-actions/setup)
- [`servant-jsonrpc-server` on Hackage](https://hackage.haskell.org/package/servant-jsonrpc-server)

**Project context:**
- `.planning/PROJECT.md` — carried risks, Key Decisions, scope boundaries

---
*Pitfalls research for: cross-language spec-oracle bridge (Haskell JSON-RPC ↔ Foundry differential testing)*
*Researched: 2026-08-27*
