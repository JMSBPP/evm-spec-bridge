# Architecture Research

**Domain:** Out-of-process typed-specification oracle for EVM differential testing (Haskell JSON-RPC service consumed by Foundry via `vm.rpc`, distributed as a git submodule)
**Researched:** 2026-08-27
**Confidence:** HIGH for the `vm.rpc` transport mechanics (read from Foundry `master` source + local `forge 1.5.1-stable` + forge-std `Vm.sol`). MEDIUM for CI lifecycle and submodule topology (general-practice + GitHub docs, no direct prior art for this exact shape). LOW for anything touching the consumer's still-open `VolOrder(T)` wire format.

---

## HEADLINE: The `vm.rpc` assumption is VERIFIED. The design is viable.

**`vm.rpc` forwards arbitrary method names, verbatim, with zero validation, to any HTTP/WS/IPC endpoint. It does not care whether the endpoint is an Ethereum node.**

Evidence — `crates/cheatcodes/src/evm/fork.rs` on `foundry-rs/foundry@master`:

```rust
fn rpc_result(url: &str, method: &str, params: &str) -> Result<serde_json::Value> {
    let provider = ProviderBuilder::<AnyNetwork>::new(url).build()?;
    let params_json: serde_json::Value = serde_json::from_str(params)?;
    foundry_common::block_on(provider.raw_request(method.to_string().into(), params_json))
        .map_err(|err| fmt_err!("{method:?}: {err}"))
}
```

There is no allowlist, no `eth_*` prefix check, no namespace filter. `method` goes straight into `raw_request` as an owned string. The only thing Foundry inspects the method name for is `refresh_active_fork_state`, which matches a fixed list of `anvil_*`/`hardhat_*`/`tenderly_*` state-setters and returns `Ok(())` for everything else — so a method named `spec_volOrderToTokenId` is passed through and then ignored by that hook.

**The endpoint is not validated as a node either.** `Cheatcodes::rpc_endpoint` (`crates/cheatcodes/src/config.rs`) resolves in this order: (1) an alias in `[rpc_endpoints]`, (2) a builtin chain alias, (3) *any string starting with `http` or `ws`, or any existing file path* (IPC). No handshake, no `eth_chainId` probe, no scheme policing. `ResolvedRpcEndpoint::url()` is `self.endpoint.clone()` — it just hands back the resolved string.

**Practical consequence, and a simplification worth taking:** the three-argument overload does not need a `foundry.toml` alias at all, and does not need an active fork. `impl Cheatcode for rpc_1Call` is `apply` (stateless), not `apply_stateful` — it never touches the fork DB. So `vm.rpc("http://127.0.0.1:8547", "spec_health", "[]")` works in a plain `forge test` with no `--fork-url`, no anvil, and no `[rpc_endpoints]` entry.

**Nothing in PROJECT.md's Key Decisions is invalidated.** The transport decision stands. What the source *does* change is the shape of the protocol — see the two constraints below, both of which are architectural, not cosmetic.

### Constraint 1 — the return path is lossy unless you force it

`vm.rpc` returns `bytes memory`, but it does not return your JSON. It runs the JSON `result` through `json_value_to_token` (`crates/cheatcodes/src/json.rs`), a heuristic coercer:

| JSON `result` | Becomes | Notes |
|---|---|---|
| `"0x<even-nibble hex>"` | `Bytes` (via `Address`/`FixedBytes` → `convert_to_bytes`) | **byte-exact round trip** |
| `123` | `Uint(256)` | scientific-notation / `f64` rounding edge cases in the code |
| `"hello"` | `String` | falls through after hex and big-int-string branches |
| `{"b":2,"a":1}` | `Tuple` in **alphabetical key order** | `defs` is passed as `None`, so no struct-name matching happens for `vm.rpc` |
| `null` | 32 zero bytes | |
| `"0x" + 39 nibbles` | **hard error** | explicit "cannot parse as address" rejection |

Then `rpc_call` wraps it: `DynSolValue::Bytes(payload).abi_encode()`, where `payload` is the raw bytes if the token was `Bytes`, else `token.abi_encode()`.

**Therefore: the server must return its entire result as a single hex string, `"0x" <> hex(abiEncode(response))`.** That is the only branch of `json_value_to_token` that is byte-exact and total. ABI payloads are always a multiple of 32 bytes, so the odd-nibble and 39-nibble hazards are structurally unreachable, and the `Address`(20)/`FixedBytes`(32) special-cases are neutralised by `convert_to_bytes`, which converts both back to `Bytes` with identical content. Solidity then receives exactly the bytes Haskell produced and does `abi.decode(data, (...))` on a payload Haskell fully owns.

Returning a JSON *object* and letting Foundry tuple-ise it is the tempting shortcut and it is a trap: field order becomes alphabetical-by-key, adding a field silently reorders the tuple, and numbers go through `f64`.

### Constraint 2 — `vm.rpcJson` exists but you cannot use it yet

`vm.rpcJson(string,string,string)` returns the raw JSON `result` as a `string`, which would sidestep all of the above. It was merged in [foundry PR #15076](https://github.com/foundry-rs/foundry/pull/15076) on 2026-06-05.

Version check (grepping `crates/cheatcodes/assets/cheatcodes.json` at each tag):

| Foundry tag | `rpcJson` present |
|---|---|
| v1.6.0 | no |
| v1.7.0 | no |
| **v1.8.0** (published **2026-08-27**, i.e. today) | **yes** |

The forge binary on this machine is `1.5.1-stable` and the forge-std `Vm.sol` checked out under `~/cfmm/` has no `rpcJson` declaration. **Do not build v1 on `rpcJson`.** The hex-ABI envelope works on every Foundry that has ever had `vm.rpc` and costs nothing extra, since the protocol wants a versioned binary envelope anyway.

### Constraint 3 — all three failure modes revert identically in kind

`rpc_result` maps *every* non-success into `fmt_err!("{method:?}: {err}")`, which becomes a cheatcode `Error`, ABI-encoded as `CheatcodeError(string)` (`crates/cheatcodes/src/error.rs`) and returned as revert data. Collapsed into that one bucket:

- connection refused / DNS failure / socket error
- HTTP non-200 (any status)
- malformed or non-JSON-RPC response body
- **a JSON-RPC `error` object in the response** — alloy surfaces this as `RpcError::ErrorResp`
- the 45-second request timeout (`REQUEST_TIMEOUT`, `crates/common/src/constants.rs`)

**This is the single most important design consequence in the whole project.** PROJECT.md's Core Value is that spec success, spec rejection, and transport failure must never be conflated. Foundry conflates JSON-RPC `error` with transport failure. So:

> **A spec rejection MUST be delivered as a successful HTTP 200 carrying a JSON-RPC `result`, with the rejection encoded inside the ABI envelope. The server must never emit a JSON-RPC `error` object, and never a non-200 status, for a domain-level rejection.**

JSON-RPC `error` is then reserved for genuine protocol faults — unknown method, unparseable params, envelope-version mismatch — which *are* correctly classified as transport/contract failures and *should* revert loudly. That is a coherent split, not a workaround.

Distinguishing revert-vs-success on the Solidity side is done with a low-level call, which is what a high-level `vm.rpc(...)` compiles to anyway:

```solidity
(bool ok, bytes memory ret) = address(vm).call(
    abi.encodeWithSignature("rpc(string,string,string)", url, method, params)
);
// ok == false  -> transport failure; ret is CheatcodeError(string) with the reason
// ok == true   -> ret is abi.encode(bytes payload); decode, then read the tag byte
```

`try`/`catch` on `vm.rpc` may also work but inserts an `extcodesize` check against the cheatcode address; the low-level form avoids that question entirely and preserves the error message. **Verify empirically in Phase 1 either way** — this is the one claim here I could not settle from source alone.

### Constraint 4 — retries, timeouts, and proxies

`rpc_result` builds the provider with `ProviderBuilder::new(url)` defaults, **not** `from_config`. So `foundry.toml`'s `eth_rpc_timeout`, `eth_rpc_headers`, and the per-endpoint `retries`/`retry_backoff` under `[rpc_endpoints]` **do not apply to `vm.rpc`**. You get the hardcoded defaults: `max_retry: 8`, `initial_backoff: 800ms`, `timeout: 45s`.

Alloy's retry policy (`TransportErrorKind::is_retry_err`) retries only on HTTP 429, HTTP 503, `MissingBatchResponse`, `BackendGone`, and errors whose text contains `429 Too Many Requests`. **Connection-refused is not retried** — an unreachable server fails fast rather than hanging for 8 backoffs. Good news for CI feedback time.

But the server *can* be replayed if it ever returns 429/503, so **handlers must be pure and idempotent**. For a spec oracle that is free; just do not add hit counters or mutable session state.

`guess_local_url` (alloy) considers a URL local only when the host is exactly `localhost`, `127.0.0.1`, or `::1`; Foundry sets `no_proxy = true` for those. **Address the service as `http://127.0.0.1:8547`.** A container hostname or `0.0.0.0` in the URL is not "local", so `HTTP_PROXY`/`HTTPS_PROXY` in the CI environment would be honoured and the call would be routed off-box.

Also note the provider is constructed *inside* `rpc_result`, i.e. **per call** — a fresh reqwest client and TCP connection for every `vm.rpc`, with no keep-alive pooling across calls, no batching, and no caching. Loopback makes this cheap, but it sets the fuzzing cost model (see Scaling).

---

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│  CONSUMER REPO (cfmm-vol-markets)          forge test process         │
├──────────────────────────────────────────────────────────────────────┤
│  ┌────────────────┐   ┌──────────────────────────────────────────┐   │
│  │ Differential   │──▶│  SpecOracle.sol  (hand-written runtime)   │   │
│  │ test / fuzzer  │   │  + ISpecOracle.sol (GENERATED, checked in)│   │
│  └────────────────┘   └────────────────────┬─────────────────────┘   │
│                                            │ address(vm).call(...)   │
│                              ┌─────────────▼───────────────┐         │
│                              │  vm.rpc cheatcode (Foundry) │         │
│                              └─────────────┬───────────────┘         │
└────────────────────────────────────────────┼─────────────────────────┘
                            HTTP/1.1 POST JSON-RPC 2.0
                            http://127.0.0.1:8547
┌────────────────────────────────────────────▼─────────────────────────┐
│  BRIDGE REPO (evm-spec-bridge)            spec-server process         │
├──────────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  server-transport   (warp/wai — HTTP, always 200, no state)     │  │
│  └───────────────────────────┬────────────────────────────────────┘  │
│  ┌───────────────────────────▼────────────────────────────────────┐  │
│  │  jsonrpc-codec      (JSON-RPC 2.0 envelope, Aeson-derived)      │  │
│  └───────────────────────────┬────────────────────────────────────┘  │
│  ┌───────────────────────────▼────────────────────────────────────┐  │
│  │  method-registry    ◀── SINGLE SOURCE OF TRUTH ──▶ solidity-    │  │
│  │  typed Method: name, param type, result type, sol signature     │  │
│  └───────────────────────────┬───────────────────────────────────┬┘  │
│  ┌───────────────────────────▼────────────────────┐  ┌───────────▼─┐ │
│  │  abi-codec  (Sol ABI encode/decode in Haskell) │  │ solidity-   │ │
│  │  + protocol types: Outcome = Ok | Rejected     │  │ codegen exe │ │
│  └───────────────────────────┬────────────────────┘  └───────┬─────┘ │
│  ═══════════════ DOMAIN SEAM (everything above is cfmm-free) ══╪═══   │
│  ┌───────────────────────────▼────────────────────────────────┐│      │
│  │  cfmm-adapter                                              ││      │
│  │  VolOrder(T) wire decode ▸ guard eval ▸ Rejected mapping    ││      │
│  └───────────────────────────┬────────────────────────────────┘│      │
└──────────────────────────────┼─────────────────────────────────┼──────┘
                               │ cabal dep (overridable pin)     │ writes
┌──────────────────────────────▼─────────┐                       │
│  cfmm-vol-markets-spec  (Haskell)      │      solidity/src/ISpecOracle.sol
│  volOrderToTokenId, guards, model      │◀──────────────────────┘
└────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Knows about cfmm? | Typical implementation |
|---|---|---|---|
| `protocol` | `Outcome` ADT (`Ok`/`Rejected`), `ProtocolVersion`, envelope layout, tag constants | **No** | Pure Haskell types, no deps |
| `abi-codec` | Solidity-ABI encode/decode in Haskell; `AbiType` class; hex-string wrapping | **No** | Hand-rolled or a Solidity-ABI lib; the encode direction is the only one v1 strictly needs, decode is needed for `VolOrder` bytes |
| `jsonrpc-codec` | JSON-RPC 2.0 request parse / response build; Aeson instances derived from types | **No** | Aeson + derived instances |
| `method-registry` | Typed `Method` values: wire name, param type, result type, Solidity signature, handler. Dispatch table. **The one artifact codegen reads.** | **No** | Existential/GADT list of `Method` records |
| `server-transport` | HTTP listener; binds `127.0.0.1:PORT`; always 200; maps registry misses to JSON-RPC `error` | **No** | warp/wai |
| `solidity-codegen` | Walks the registry, emits `ISpecOracle.sol` + version constant | **No** | Separate executable component |
| `cfmm-adapter` | Decodes Plank `VolOrder(T)` bytes → spec types; calls `volOrderToTokenId`; maps guard violations → `Rejected guardId` | **Yes — and only this one** | Library component depending on `cfmm-vol-markets-spec` |
| `spec-server` (exe) | **Composition root.** Wires `cfmm-adapter`'s methods + `spec_health` into the registry, starts transport. | Yes, by construction | tiny `main` |
| `SpecOracle.sol` | Hand-written Solidity runtime: low-level `vm.rpc` call, three-way `Outcome`, version handshake | n/a | ~80 lines, stable |
| `ISpecOracle.sol` | **Generated + checked in.** Method signatures, tag constants, `PROTOCOL_VERSION` | n/a | codegen output |

### Where the decoupling seams are

PROJECT.md defers "domain-agnostic abstraction" to a second demand, which is right — but that only works if the seams are *placed* now even though they are not *exercised* now. Two seams, both enforced by the build rather than by discipline:

1. **`cfmm-adapter` is a separate cabal library component.** `protocol`, `abi-codec`, `jsonrpc-codec`, `method-registry`, `server-transport` and `solidity-codegen` must not list `cfmm-vol-markets-spec` in their `build-depends`. Cabal then makes an accidental domain import a compile error. No abstraction, no type classes for hypothetical consumers — just a dependency edge that cannot be drawn.
2. **The executable is the composition root.** A second consumer adds a second adapter library and a second exe (or a flag), and touches nothing above the seam.

That is the entire "generalize later" investment: one cabal stanza boundary. It costs nothing and it is the thing that is genuinely painful to retrofit.

---

## Recommended Project Structure

```
evm-spec-bridge/
├── cabal.project                 # pins cfmm-vol-markets-spec by SHA (see Submodule Topology)
├── cabal.project.freeze
├── evm-spec-bridge.cabal         # multiple library components + 2 exes
├── src/
│   ├── Protocol/
│   │   ├── Types.hs              # Outcome, ProtocolVersion, tag constants
│   │   └── Envelope.hs           # abi layout of the response envelope
│   ├── Abi/
│   │   ├── Class.hs              # AbiType
│   │   ├── Encode.hs
│   │   └── Decode.hs
│   ├── JsonRpc/
│   │   ├── Types.hs              # Request/Response/ErrorObject
│   │   └── Codec.hs
│   ├── Registry/
│   │   ├── Method.hs             # typed Method record; sol signature carried here
│   │   └── Dispatch.hs
│   ├── Server/
│   │   └── Http.hs               # warp; 127.0.0.1 bind; always-200 discipline
│   └── Codegen/
│       └── Solidity.hs           # registry -> .sol text
├── adapter-cfmm/                 # THE DOMAIN SEAM — separate library component
│   └── src/Adapter/Cfmm/
│       ├── VolOrderCodec.hs      # BLOCKED on consumer Phase 4 wire-format decision
│       └── Methods.hs            # spec_volOrderToTokenId
├── app/
│   ├── server/Main.hs            # composition root
│   └── gen-solidity/Main.hs      # writes solidity/src/ISpecOracle.sol
├── solidity/
│   ├── src/
│   │   ├── ISpecOracle.sol       # GENERATED — checked in, DO NOT EDIT header
│   │   └── SpecOracle.sol        # hand-written runtime helper
│   └── test/
│       └── Transport.t.sol       # the bridge's own Foundry tests (health + 3 outcomes)
├── scripts/
│   ├── run-server.sh             # start + wait-for-health + record PID
│   └── with-spec-server.sh       # wrapper: start, run "$@", stop
├── foundry.toml                  # for THIS repo's own solidity tests
└── .github/workflows/ci.yml
```

### Structure Rationale

- **`src/` holds zero domain knowledge.** Grep-verifiable and cabal-verifiable.
- **`adapter-cfmm/` is a sibling, not a subdirectory of `src/`.** Makes the seam visible in a file listing, not just in a `.cabal` file.
- **`solidity/src/` is what the consumer remaps to.** The consumer needs no Haskell toolchain to compile Solidity, so the generated interface must be committed — see Codegen.
- **`solidity/test/` matters more than it looks.** The bridge must prove all three outcomes *in its own repo*, against its own server, before the consumer ever integrates. Otherwise the first end-to-end test of the transport happens in the consumer's CI, where the diagnosis surface is worst.

---

## Architectural Patterns

### Pattern 1: Hex-ABI response envelope (the load-bearing pattern)

**What:** every method returns `"0x" <> hex(abi.encode(uint8 tag, uint16 version, bytes body))`. Success is `tag = 0` with `body` = the method's ABI-encoded result. Rejection is `tag = 1` with `body` = ABI-encoded rejection detail (guard identifier + whatever the guard carries).

**When to use:** always, for every method, including `spec_health`.

**Trade-offs:** costs a hex encode/decode and a nested `abi.decode`. Buys byte-exactness, total control of the layout from Haskell, independence from `json_value_to_token`'s heuristics, independence from Foundry ≥ v1.8.0, and a version field on the wire.

```solidity
// SpecOracle.sol (hand-written runtime)
enum Kind { Ok, Rejected, TransportFailure }

struct Outcome { Kind kind; bytes body; string failure; }

function call(string memory url, string memory method, string memory params)
    internal returns (Outcome memory o)
{
    (bool sent, bytes memory ret) = address(vm).call(
        abi.encodeWithSignature("rpc(string,string,string)", url, method, params)
    );
    if (!sent) return Outcome(Kind.TransportFailure, "", _decodeCheatcodeError(ret));

    bytes memory payload = abi.decode(ret, (bytes));
    (uint8 tag, uint16 version, bytes memory body) = abi.decode(payload, (uint8, uint16, bytes));
    require(version == PROTOCOL_VERSION, "spec oracle: protocol version skew");
    return Outcome(tag == 0 ? Kind.Ok : Kind.Rejected, body, "");
}
```

```haskell
-- Server side: every handler funnels through this. There is no other exit.
respond :: AbiType a => Outcome a -> Value
respond o = String . hexPrefixed . abiEncode $ case o of
  Ok  a          -> (0 :: Word8, protocolVersion, abiEncode a)
  Rejected guard -> (1 :: Word8, protocolVersion, abiEncode guard)
-- NOTE: there is deliberately no constructor here that produces a JSON-RPC error.
```

### Pattern 2: Registry-as-source-of-truth codegen

**What:** a `Method` value carries everything both sides need — the wire name, the Haskell param/result types, and the Solidity signature string. The server dispatches from the registry; the generator renders from the same registry. Adding a method is one value.

**When to use:** from Phase 3 onward. Do not build it in Phase 1 — Phase 1's job is to falsify the transport, and a registry abstraction there is speculative structure around an unproven mechanism.

**Trade-offs:** the Haskell-type-to-Solidity-type mapping has to live somewhere and it is the fiddly part. Keep it total and small: fail the generator loudly on an unmapped type rather than emitting `bytes` and hoping.

### Pattern 3: Protocol-version handshake, because the compile-time guarantee has a hole

**What:** one `protocolVersion` constant, defined in Haskell, emitted into `ISpecOracle.sol` by the generator, echoed by `spec_health`, and asserted by `SpecOracle.call` on every response.

**Why it is not redundant with codegen:** PROJECT.md's stated guarantee is "a wire contract change breaks the build instead of drifting." Codegen delivers that only when the `.sol` file and the running server binary come from the same commit. In the submodule diamond they demonstrably do not have to — the consumer pins a bridge SHA for the `.sol`, while CI might build the server from a different checkout, or a stale server process might be left running on 8547 from a previous run. The version field turns that from a wrong `tokenId` into an immediate, unambiguous revert.

**Trade-offs:** two extra bytes per response and one `require`. There is no argument against it.

### Pattern 4: External process lifecycle, owned by the harness, never by the test

**What:** a `with-spec-server.sh` wrapper starts the server, polls `spec_health` over plain `curl` until ready or a deadline, runs `forge test`, and kills the process in a `trap`. CI calls the wrapper; developers call the same wrapper.

**When to use:** always. See Process Lifecycle below for why the alternatives lose.

---

## Data Flow

### One oracle call, end to end

```
[fuzz case: bytes volOrderWire]
        │
        ▼
SpecOracle.call(url, "spec_volOrderToTokenId", '["0x<wire hex>"]')
        │  address(vm).call(abi.encodeWithSignature("rpc(string,string,string)", ...))
        ▼
Foundry cheatcode  rpc_1Call::apply
        │  config.rpc_endpoint(url).url()      -- no validation, accepts any http:// string
        │  ProviderBuilder::new(url).build()   -- fresh client, 45s timeout, no_proxy (127.0.0.1)
        │  provider.raw_request("spec_volOrderToTokenId", params_json)
        ▼
HTTP/1.1 POST 127.0.0.1:8547   {"jsonrpc":"2.0","id":1,"method":"spec_volOrderToTokenId","params":["0x.."]}
        │
        ▼
server-transport (warp)  ──▶  jsonrpc-codec (parse)  ──▶  method-registry (dispatch)
                                                              │
                                        ┌─────────────────────┴──────────────────┐
                                        ▼                                        ▼
                             method not in registry                    cfmm-adapter
                                        │                     VolOrderCodec.decode :: Bytes -> Either DecodeErr VolOrder
                                        │                                        │
                                        │                          ┌─────────────┴──────────────┐
                                        │                          ▼                            ▼
                                        │                  guard violated                  guards pass
                                        │                          │                            │
                                        │                  Rejected guardId          Ok (volOrderToTokenId o)
                                        │                          └─────────────┬──────────────┘
                                        │                                        ▼
                                        │                              Protocol.respond
                                        │                    "0x" <> hex(abi(tag, version, body))
                                        ▼                                        ▼
                            HTTP 200 {"error":{...}}              HTTP 200 {"result":"0x...."}
                                        │                                        │
                                        ▼                                        ▼
                        alloy RpcError::ErrorResp                   json_value_to_token -> Bytes
                                        │                           -> DynSolValue::Bytes(payload).abi_encode()
                                        ▼                                        │
                        fmt_err! -> CheatcodeError(string) revert                 ▼
                                        │                        Solidity: abi.decode(ret,(bytes))
                                        ▼                                        │
                        (bool ok = false, bytes ret)                             ▼
                                        │                     abi.decode(payload,(uint8,uint16,bytes))
                                        ▼                                        │
                          Kind.TransportFailure                     tag==0 ? Kind.Ok : Kind.Rejected
```

### Where each outcome is produced, and how it survives

| Outcome | Produced by | Wire representation | HTTP | Reaches Solidity as | Survives? |
|---|---|---|---|---|---|
| **Spec success** | `cfmm-adapter` handler returns `Ok tokenId` | `result: "0x" + abi(0, ver, tokenId)` | 200 | `ok == true`, tag `0` | Yes — byte-exact |
| **Spec rejection** | adapter maps a guard violation to `Rejected guardId` | `result: "0x" + abi(1, ver, guardId)` | **200** | `ok == true`, tag `1` | Yes — **only because it rides in `result`, not in `error`** |
| **Transport failure** | Foundry: connection refused, non-200, JSON-RPC `error`, malformed body, 45s timeout | n/a | any | `ok == false`, `CheatcodeError(string)` in `ret` | Yes — and the string carries the reason |

**Collapse risk, stated plainly:** if the server ever emits a JSON-RPC `error` object for a guard violation, or ever returns HTTP 4xx/5xx for one, Foundry converts it into exactly the same revert as "server is down." The test then reads "transport failure," and a harness that treats transport failure as skip-or-warn produces a green build that means nothing — the precise failure mode PROJECT.md names as worse than useless. The always-200/always-`result` rule is not a stylistic preference; it is the mechanism that keeps the three outcomes distinct.

**A second collapse risk, subtler:** a `Rejected` that decodes to a zero-length body is indistinguishable at a glance from `Ok` carrying a zero `tokenId` if the Solidity helper is sloppy about the tag. Make `Outcome` an enum with three constructors in Solidity and force call sites through a `switch`; do not return `(bool ok, bytes memory)`.

### Params direction

`vm.rpc` takes `params` as a **string that Foundry parses with `serde_json::from_str`** — it must be valid JSON, and by JSON-RPC convention an array or object. Building that string in Solidity is the awkward half of the trip. Use forge-std's `vm.toString(bytes)` (which yields `0x...`) and `string.concat`, and keep every method's params to a single positional hex string: `'["0x..."]'`. One shape, one helper, no per-method serialisation logic in Solidity, and the generated interface stays trivial. Resist the temptation to build JSON objects in Solidity.

---

## Process Lifecycle

The constraint from PROJECT.md is that the **consumer's CI is the sole validation gate**, and the consumer's convention is no local compilation. So the lifecycle must work unattended in a CI job, and the bridge should ship the script that does it.

| Option | How | Verdict |
|---|---|---|
| **A. Background step in the job, wrapper script** | build server → launch → poll health → `forge test` → `trap` kill | **RECOMMENDED** |
| B. `setUp()` spawns via `vm.ffi` | test spawns the process itself | **Rejected** |
| C. GitHub Actions service container | `services:` block in the job | **Deferred / not viable for v1** |
| D. `forge test` with an already-running dev server | developer starts it by hand | Fine locally, unusable as a gate |

**Why B loses, concretely.** Foundry's own docs state "`setUp()` runs before each test" — it is re-executed per test function, not once per contract. A spawn there is a spawn per test function, times every test contract. There is no `tearDown` hook, so nothing kills them; they leak. It requires `--ffi`, which the consumer may not want enabled repo-wide for a differential-testing suite. And it races on the port. B is the option that looks convenient and is not.

**Why C is deferred.** GitHub Actions service containers start at the pre-job stage, before any step runs, and can only pull images that already exist in a registry — you cannot build the Haskell image in the same job and use it as a service. Making C work means a publish job plus a consume job, GHCR authentication, and an image that carries the GHC runtime. That is real infrastructure for a v1 whose PROJECT.md already flags hosted-CI billing as a live risk. Revisit if the consumer's self-hosted runner turns out to lack a usable GHC.

**Shape of A, and the details that matter:**

```bash
# scripts/with-spec-server.sh
set -euo pipefail
PORT="${SPEC_ORACLE_PORT:-8547}"          # NOT 8545 — leave anvil's default alone
"$SERVER_BIN" --host 127.0.0.1 --port "$PORT" &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT

for i in $(seq 1 50); do                   # bounded wait, ~10s, then fail the job
  curl -sf -X POST "http://127.0.0.1:$PORT" \
    -H 'content-type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"spec_health","params":[]}' >/dev/null && break
  kill -0 "$PID" 2>/dev/null || { echo "spec-server died during startup"; wait "$PID"; }
  sleep 0.2
done

SPEC_ORACLE_URL="http://127.0.0.1:$PORT" exec "$@"
```

- **Bind and address `127.0.0.1`, never `0.0.0.0`.** Verified above: alloy's `guess_local_url` only recognises `localhost`/`127.0.0.1`/`::1`, and only those get `no_proxy`. A proxied runner would otherwise route loopback traffic outward.
- **Poll for readiness with a bounded deadline, and check the PID inside the loop.** A crashed server otherwise burns the full timeout before failing with a misleading message.
- **Pass the URL via env, read it in Solidity with `vm.envOr("SPEC_ORACLE_URL", "http://127.0.0.1:8547")`, and use the 3-arg `vm.rpc` overload.** Verified: `rpc_endpoint` accepts any string starting with `http`, so no `[rpc_endpoints]` entry is needed and the consumer's `foundry.toml` stays untouched. Fewer moving parts across the submodule boundary than an alias.
- **The health probe should be the exact same JSON-RPC shape the tests use**, not a bespoke `/healthz` route. A curl that succeeds while `vm.rpc` fails is a wasted debugging hour.
- **`spec_health` is also a Solidity test**, per PROJECT.md's payload-free-method requirement. The curl probe proves the socket; the Solidity test proves the cheatcode path. They are different claims.

---

## Codegen Pipeline

```
Registry/Method.hs  ──[cabal run gen-solidity]──▶  solidity/src/ISpecOracle.sol  ──git add──▶ repo
                                                             │
                                              consumer remaps and compiles it
                                              WITHOUT any Haskell toolchain
```

**The generated `.sol` must be committed.** This is forced, not stylistic: the consumer pins the bridge as a submodule and runs `forge build`. If the interface were generated at build time, every consumer of the submodule would need GHC and cabal to compile Solidity — which contradicts the consumer's no-local-compilation convention and would drag the unresolved self-hosted-runner GHC question into their build.

**Staleness gate**, as a distinct CI job:

```yaml
- run: cabal run gen-solidity -- --out solidity/src
- run: git diff --exit-code -- solidity/src/ISpecOracle.sol
      || { echo "::error::ISpecOracle.sol is stale — run 'cabal run gen-solidity'"; exit 1; }
```

Generator hygiene that makes this gate actually hold:
- **Deterministic output.** Sort methods by wire name; never iterate a `Data.Map` whose order could shift; do not embed a timestamp, a git SHA, or a generator version string in the file. A non-deterministic generator turns this gate into a flake and it will be disabled within a month.
- **`// SPDX` + `// AUTOGENERATED by gen-solidity — DO NOT EDIT` header.** Cheap, and it is the thing a stranger reads first.
- **Fail loudly on unmapped types.** A Haskell type with no Solidity mapping must abort the generator, not emit `bytes`.
- **Emit `PROTOCOL_VERSION` into the file** from the same Haskell constant the server uses.

Note the guarantee's actual scope, honestly: codegen makes `.sol`-vs-registry drift a CI failure *within the bridge repo*. It does **not** by itself catch a consumer that pinned bridge@X for the `.sol` while running a server built from bridge@Y. That is the version handshake's job. State this in the README so nobody over-trusts the compile-time claim.

---

## Submodule Topology (the diamond)

```
cfmm-vol-markets
├── spec/                    ──▶ cfmm-vol-markets-spec @ A
└── lib/evm-spec-bridge      ──▶ evm-spec-bridge @ X
                                  └── (dependency) cfmm-vol-markets-spec @ B
```

### Hazards

1. **Silent version skew, A ≠ B.** The worst one. The differential test compares Plank against the spec *as linked into the server* (B), while everyone reading the repo believes it is testing against `spec/` (A). Nothing fails; the answer is just from a different spec revision. This is a green-build-that-means-nothing, the exact failure class PROJECT.md is built to prevent.
2. **Recursive initialisation.** If the bridge vendors the spec as its own git submodule, `git submodule update --init` (non-recursive, the common default and the shape of most `actions/checkout` configs) leaves it empty and the bridge fails to build with a confusing missing-package error. The consumer's stated convention of leaving dependencies uninitialised makes this a near-certainty on first integration.
3. **Duplicate checkouts** of the same repo, doubling clone cost and giving two editable copies that can diverge locally.
4. **Three-repo update choreography.** Bumping the spec becomes: PR to spec → PR to bridge (bump pin, regenerate `.sol`) → PR to consumer (bump *both* pins). Miss the last half and you are back in hazard 1.

### Recommendation — do not make the spec a git submodule of the bridge

Depend on it through `cabal.project` instead:

```cabal
-- cabal.project
packages: . adapter-cfmm

source-repository-package
  type:     git
  location: https://github.com/d2p-finance/cfmm-vol-markets-spec
  tag:      <full-40-char-sha>
```

This kills hazard 2 outright (no submodule to forget to init), reduces hazard 1 to a single greppable SHA in one file, and keeps the bridge's own CI hermetic and pinned.

Then close hazard 1 from both sides:

- **Integration override.** The consumer's CI writes a `cabal.project.local` pointing the bridge at *its own* `spec/` checkout:
  ```cabal
  packages: ../../spec
  ```
  Now the integration build has exactly one spec checkout — the consumer's pin A — and skew is impossible *by construction* rather than by vigilance. This is the strongest available answer and it is why the spec should be an overridable dependency rather than a vendored one.
- **Coherence check**, for when the override is not in play:
  ```bash
  test "$(git -C spec rev-parse HEAD)" = "$(grep -A2 cfmm-vol-markets-spec lib/evm-spec-bridge/cabal.project | sed -n 's/.*tag: *//p')"
  ```
  One line in the consumer's CI. Cheap, and it converts a silent divergence into a red build.
- **Belt and braces:** `spec_health` should also report the spec revision the server was built against (via a `TemplateHaskell`/`gitrev`-style embed or a build-time env var). Then a Solidity test can assert it. This catches the case the SHA check cannot: a stale server *process* left running on port 8547 from an earlier checkout.

If a submodule is nevertheless required (e.g. offline/air-gapped builds, or `source-repository-package` proves painful with the consumer's cabal version): put it at a fixed path, document `git submodule update --init --recursive` prominently, set `actions/checkout` to `submodules: recursive` in both repos, and keep the SHA-equality check.

**Note the asymmetry worth stating to the consumer's owning agent:** the consumer's `spec/` submodule and the bridge's spec pin serve different purposes — `spec/` is presumably for their own Haskell work, the bridge's pin is for linking the server. If the consumer does not actually need `spec/` independently once the bridge exists, the cleanest resolution is to drop one of the two paths entirely. That is their call, not this project's.

---

## Scaling Considerations

Scale here is **fuzz runs per CI job**, not users.

| Scale | Behaviour and adjustment |
|---|---|
| Smoke (`spec_health`, a handful of unit tests) | Nothing to think about. Sub-millisecond loopback calls. |
| Default fuzzing (`runs = 256`, a few properties) | ~256 round trips per property. New reqwest client and TCP connection **per call** (the provider is built inside `rpc_result`), so budget connection setup, not just handler time. Loopback: expect low single-digit ms. Fine. |
| Heavy fuzzing (`runs = 10_000`) or invariant testing | Thousands of short-lived loopback connections. Watch for `TIME_WAIT` accumulation on the runner and for the 45s per-call timeout being hit if a handler is slow. `vm.rpc` results are **not cached and not batched** by Foundry, so there is no free lunch. |

### Scaling priorities

1. **First bottleneck: per-call connection setup, not spec computation.** Keep the server warm (already the plan), keep handlers pure, and set fuzz `runs` deliberately rather than cranking it. If it ever dominates, the lever is fewer-but-better-chosen fuzz inputs, not a faster server — Foundry gives no batching hook.
2. **Second bottleneck: CI wall-clock from server build time.** Building GHC + deps on a hosted runner dwarfs test runtime. Cache `~/.cabal` and `dist-newstyle` keyed on `cabal.project.freeze`. This matters far more to the gate's usability than anything at runtime.
3. **Non-bottleneck: concurrency.** `forge test` issues `vm.rpc` synchronously (`block_on`), so the server sees a low-concurrency stream even though Foundry parallelises across test contracts. Do not build a connection-pooling or worker-queue architecture for load that will not arrive.

---

## Anti-Patterns

### Anti-Pattern 1: Domain rejection as a JSON-RPC `error`

**What people do:** it is the obvious JSON-RPC idiom — invalid input, return `{"error": {"code": -32602, ...}}`.
**Why it's wrong:** verified above — alloy turns it into `RpcError::ErrorResp`, Foundry turns that into `fmt_err!`, and Solidity sees the identical `CheatcodeError(string)` revert it gets when the server is *down*. The three-outcome guarantee dies here and dies silently.
**Do this instead:** HTTP 200, JSON-RPC `result`, rejection encoded as `tag = 1` inside the ABI envelope. Reserve JSON-RPC `error` for unknown-method and unparseable-params — real contract faults that *should* revert.

### Anti-Pattern 2: Returning a JSON object and letting Foundry tuple-ise it

**What people do:** `{"tokenId": "0x...", "ok": true}` and `abi.decode(data, (bytes32, bool))`.
**Why it's wrong:** `json_value_to_token` is called with `defs = None` for `vm.rpc`, so object fields are ordered **alphabetically by key**. Adding a field named `aaa` silently reorders the tuple. Numbers pass through `f64`. `null` becomes 32 zero bytes.
**Do this instead:** one hex string, ABI-encoded, versioned.

### Anti-Pattern 3: Building v1 on `vm.rpcJson`

**What people do:** find `rpcJson` in `master`, use it, enjoy the raw JSON.
**Why it's wrong:** it landed 2026-06-05 and first shipped in a stable tag **today** (v1.8.0). The forge on this machine is 1.5.1. Depending on it forces every consumer to a same-day release, for a convenience the hex envelope already provides.
**Do this instead:** hex-ABI envelope on `vm.rpc`. Revisit `rpcJson` in v2 if it buys something real.

### Anti-Pattern 4: Spawning the server from `setUp()` via `vm.ffi`

**What people do:** make the test self-contained.
**Why it's wrong:** `setUp()` runs before *every test function*; there is no `tearDown`; processes leak; the port races; `--ffi` has to be on.
**Do this instead:** harness owns the lifecycle (`with-spec-server.sh`).

### Anti-Pattern 5: Generating `ISpecOracle.sol` at build time instead of committing it

**What people do:** treat generated code as a build artifact, keep the repo clean.
**Why it's wrong:** the consumer would need GHC to run `forge build`. That contradicts their no-local-compilation convention and imports the unresolved runner-toolchain risk into their gate.
**Do this instead:** commit it; enforce freshness with `git diff --exit-code` in the bridge's CI.

### Anti-Pattern 6: Trusting codegen alone to prevent drift

**What people do:** read PROJECT.md's "breaks the build instead of drifting" and stop there.
**Why it's wrong:** codegen couples the `.sol` to the *registry at a commit*. The submodule diamond and a stale background process both let the running server be a different commit. Nothing compiles-time-checks that.
**Do this instead:** runtime `PROTOCOL_VERSION` handshake asserted on every call, plus the spec-revision report in `spec_health`.

### Anti-Pattern 7: Binding or addressing the server as `0.0.0.0` / a container hostname

**What people do:** bind broadly so it works from anywhere.
**Why it's wrong:** alloy's `guess_local_url` only treats `localhost`/`127.0.0.1`/`::1` as local, and only local URLs get `no_proxy`. On a runner with `HTTP_PROXY` set, a non-local-looking URL sends your loopback call to a proxy.
**Do this instead:** `http://127.0.0.1:PORT`, and pick a port that is not 8545.

### Anti-Pattern 8: Any server-side mutable state across calls

**What people do:** a request counter, a memo cache, a session.
**Why it's wrong:** Foundry retries up to 8 times on 429/503, so a request can legitimately be replayed. And the whole value proposition is that the spec is a pure function.
**Do this instead:** pure handlers. If caching is ever needed, make it a transparent memo with no observable effect.

---

## Integration Points

### External

| Service | Integration pattern | Gotchas |
|---|---|---|
| Foundry `vm.rpc` | HTTP/1.1 JSON-RPC 2.0 on `127.0.0.1` | 45s hardcoded timeout; `foundry.toml` rpc timeout/retry settings **do not apply**; provider rebuilt per call; result coerced by `json_value_to_token` |
| `cfmm-vol-markets-spec` | `cabal.project` `source-repository-package`, overridable via `cabal.project.local` | The diamond; see Submodule Topology |
| Plank `VolOrder(T)` wire bytes | ABI/bytes decode inside `cfmm-adapter` | **BLOCKED** — format is the consumer's open Phase 4 decision (tagged vs per-variant). Do not guess. |
| GitHub Actions | background step + wrapper script | Service containers can't use locally-built images; cache `~/.cabal` + `dist-newstyle` |

### Internal boundaries

| Boundary | Communication | Notes |
|---|---|---|
| `server-transport` ↔ `jsonrpc-codec` | direct call | transport never inspects method semantics |
| `jsonrpc-codec` ↔ `method-registry` | direct call | registry miss → JSON-RPC `error` (correctly a hard failure) |
| `method-registry` ↔ `cfmm-adapter` | **the seam** — adapter registers `Method` values | enforced by cabal component `build-depends`, not by convention |
| `method-registry` → `solidity-codegen` | read-only traversal | codegen must never influence dispatch |
| `solidity-codegen` → `ISpecOracle.sol` | file write, committed | deterministic output or the staleness gate flakes |
| Bridge ↔ consumer | git submodule + remapped `solidity/src` + `SPEC_ORACLE_URL` env | no Haskell toolchain required on the consumer side |

---

## Suggested Build Order

Ordered by risk retired per unit of work, with external blockers pushed late.

| # | Component | Rationale | Depends on |
|---|---|---|---|
| **0** | Repo skeleton, cabal project, CI builds a hello-world exe on a hosted runner | Retires PROJECT.md's carried risk that hosted CI is billing-blocked and that GHC/cabal caching works, *before* any design work is sunk | — |
| **1** | **Transport spike: `spec_health` end to end** — minimal warp server, hardcoded hex-ABI response, one Solidity test calling `vm.rpc`, run under `with-spec-server.sh` | Falsifies or confirms the load-bearing assumption in reality. Source reading says it works; only a green test proves it. Also settles empirically whether `try`/`catch` works on `vm.rpc` or the low-level call is required | 0 |
| **2** | Protocol types + `Outcome` ADT + `abi-codec` + `SpecOracle.sol` runtime; a deliberately-rejecting stub method; a test that kills the server mid-run | Delivers the Core Value — three outcomes, provably distinct — with no domain code involved. This is the phase that must not be rushed | 1 |
| **3** | `method-registry` as typed values; migrate `spec_health` and the stub onto it | Structure is now justified by two real methods rather than speculation | 2 |
| **4** | `solidity-codegen` + staleness CI gate + `PROTOCOL_VERSION` handshake | Needs the registry to exist. Delivers the "drift is a build failure" requirement | 3 |
| **5** | Spec dependency wiring: `cabal.project` pin, coherence check, spec-revision in `spec_health` | Independent of the wire format; can land before the adapter | 0, 4 |
| **6** | **`cfmm-adapter`**: `VolOrder(T)` decode, `spec_volOrderToTokenId`, guard → `Rejected` mapping | **Externally blocked** on the consumer's open Phase 4 wire-format decision. Placed last so the blocker cannot stall phases 1–5 | 4, 5 |
| **7** | Consumption packaging: submodule docs, remappings, `with-spec-server.sh` hardening, consumer-side integration notes | Needs a real method to demonstrate | 6 |

**Ordering rationale.** Phase 1 exists to attack the assumption everything else rests on, and it is deliberately smaller than it wants to be — no registry, no codegen, no domain. Phase 2 delivers the actual Core Value using a stub, which means the three-outcome guarantee is tested against a rejection you control rather than one you have to construct through the domain. Phase 6 is last purely because it is blocked by a decision this project explicitly does not own; every other phase can complete without it.

**Phases likely to need their own deeper research:** 4 (Haskell-type → Solidity-type mapping has no obvious prior art) and 6 (blocked on an external decision, and the `VolOrder(T)` decode is where the real domain complexity lives).

---

## Open Questions / Gaps

1. **Does `try`/`catch` work on `vm.rpc`?** The Solidity high-level call inserts an `extcodesize` check against the cheatcode address, and I could not confirm from source whether Foundry gives that address non-empty code. The low-level `address(vm).call` form sidesteps it entirely and is the recommendation, but the ergonomic alternative is worth a 10-minute experiment in Phase 1. **LOW confidence.**
2. **Does alloy's HTTP transport enforce a `Content-Type` on the response?** Not verified. Send `application/json` regardless. **LOW confidence** that it is optional.
3. **`VolOrder(T)` wire format** — the consumer's open Phase 4 decision. Deliberately not anticipated, per PROJECT.md.
4. **RPC-02 responsibility split** — still open in PROJECT.md. This document assumes the bridge owns wire decode, guard evaluation, and error classification (the "real component" reading), because that is what the three-outcome guarantee requires: only the Haskell side can distinguish a guard violation from a decode failure. If the consumer's Phase 5 lands on "dumb transport," Phases 2 and 6 shrink substantially. **Flag this as an assumption, not a finding.**
5. **Whether the consumer's `spec/` submodule is still needed** once the bridge exists. Affects whether the diamond can be eliminated rather than merely managed. The consumer's agent owns this.
6. **`gitrev`-style embedding of the spec SHA into the binary** — mechanism not researched (TH vs build-time env var vs cabal custom-setup). Minor.

---

## Sources

**HIGH confidence — read directly from source:**
- `foundry-rs/foundry@master` `crates/cheatcodes/src/evm/fork.rs` — `rpc_0Call`/`rpc_1Call`/`rpcJson_*`, `rpc_result`, `rpc_call`, `convert_to_bytes`, `refresh_active_fork_state`
- `foundry-rs/foundry@master` `crates/cheatcodes/src/json.rs` — `json_value_to_token` / `_json_value_to_token`
- `foundry-rs/foundry@master` `crates/cheatcodes/src/config.rs` — `Cheatcodes::rpc_endpoint` alias-or-URL resolution
- `foundry-rs/foundry@master` `crates/cheatcodes/src/error.rs` — `Error::abi_encode` → `CheatcodeError(string)`
- `foundry-rs/foundry@master` `crates/common/src/provider/mod.rs` — `ProviderBuilder::new`, `build`, defaults (`max_retry: 8`, `initial_backoff: 800`, `REQUEST_TIMEOUT`), `is_local`/`no_proxy`
- `foundry-rs/foundry@master` `crates/common/src/constants.rs` — `REQUEST_TIMEOUT = 45s`
- `foundry-rs/foundry@master` `crates/config/src/endpoints.rs` — `ResolvedRpcEndpoint::url`, env interpolation
- `alloy-rs/alloy@main` `crates/transport/src/error.rs` — `TransportErrorKind::is_retry_err`
- `alloy-rs/alloy@main` `crates/transport/src/utils.rs` — `guess_local_url`
- Version matrix from `crates/cheatcodes/assets/cheatcodes.json` at tags v1.6.0 / v1.7.0 / v1.8.0
- Local `forge-std/src/Vm.sol` (`~/cfmm/cfmm-theory/clamm-automaton/lib/forge-std`) — `rpc` declared, `rpcJson` absent
- Local `forge --version` → `1.5.1-stable`
- [foundry PR #15076 — `feat(cheatcodes): vm.rpcJson`](https://github.com/foundry-rs/foundry/pull/15076), merged 2026-06-05
- [foundry releases API](https://api.github.com/repos/foundry-rs/foundry/releases) — v1.8.0 published 2026-08-27

**MEDIUM confidence — official docs:**
- [Foundry `vm.rpc` cheatcode reference](https://getfoundry.sh/cheatcodes/rpc)
- [Foundry — writing tests / `setUp()` runs before each test](https://getfoundry.sh/forge/tests/writing-tests)

**MEDIUM confidence — community/practice:**
- [GitHub community discussion #9053 — container actions built ahead of time](https://github.com/orgs/community/discussions/9053)
- [docker/build-push-action #1015 — local image not recognised in Actions](https://github.com/docker/build-push-action/issues/1015)
- [GitHub docs — using containerized services](https://docs.github.com/en/enterprise-server@3.14/actions/use-cases-and-examples/using-containerized-services)

---
*Architecture research for: Haskell spec oracle over JSON-RPC for Foundry differential testing*
*Researched: 2026-08-27*
