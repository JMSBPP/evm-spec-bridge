# Stack Research

**Domain:** Haskell JSON-RPC service acting as a typed specification oracle for Foundry/Solidity differential tests, with the Solidity interface generated from the Haskell protocol types
**Researched:** 2026-08-27
**Confidence:** HIGH on package versions and CI toolchain (verified live against Hackage, Stackage, GitHub runner-images, and Foundry source). MEDIUM on the JSON-RPC library recommendation (verified maintenance data, but the recommendation is a judgement call). LOW on the end-to-end Foundry↔non-Ethereum-RPC path (no prior art found — see "The Transport Constraint").

---

## Executive Summary of Recommendations

| Question | Answer | Confidence |
|---|---|---|
| JSON-RPC 2.0 library | **None of them wholesale.** Hand-roll the ~150-line envelope, optionally seeded from `jsonrpc-0.2.0.0` | MEDIUM |
| HTTP layer | **`warp` + `wai` + `http-types`** — no framework | HIGH |
| JSON | **`aeson-2.2.5.0`**, hand-written codecs for wire types, Generic for internal types | HIGH |
| Haskell→Solidity codegen | **No library exists.** Build an explicit IR + pure renderer, golden-tested | HIGH (that nothing exists) |
| Build tool | **`cabal`**, not `stack` | HIGH |
| GHC | **9.10.3** primary; 9.12.4 in matrix; **not** 9.14.1 despite it being preinstalled | HIGH |
| Testing | **`hspec` + `QuickCheck` + `hspec-golden`** | HIGH |
| Foundry cheatcode | **`vm.rpcJson`**, not `vm.rpc` | HIGH |

---

## The Transport Constraint (read this before the stack tables)

This section is stack-determining, so it comes first. All findings here are read directly from Foundry's `master` source, not from documentation.

### Finding 1 — Use `vm.rpcJson`, not `vm.rpc`

Foundry exposes four relevant cheatcodes (verified in `crates/cheatcodes/assets/cheatcodes.json`):

```solidity
function rpc(string calldata urlOrAlias, string calldata method, string calldata params)
    external returns (bytes memory data);
function rpcJson(string calldata urlOrAlias, string calldata method, string calldata params)
    external returns (string memory data);
```

`vm.rpc` runs the JSON result through `json_value_to_token` and ABI-encodes it — a coercion designed for Ethereum's hex-string results, and fragile for structured JSON objects. `vm.rpcJson` returns the raw JSON result as a Solidity `string`, consumable with `vm.parseJson*`.

For this project the spec's answer is a structured, tagged value, not a hex word. **`vm.rpcJson` is the correct cheatcode.** The `PROJECT.md` requirement wording ("reachable by Foundry's `vm.rpc`") should be read as the RPC cheatcode family, not literally `vm.rpc`.

Note `rpcJson` is the three-argument overload (`rpcJson_1`) that takes an alias or literal URL — the two-argument form targets the current fork and is not what you want.

### Finding 2 — The `error` channel conflates spec rejection with transport failure

`rpc_result` builds an alloy provider and calls `provider.raw_request(...)`. Any failure — connection refused, timeout, **or a JSON-RPC `error` object in the response** — comes back as a Rust `Err`, which Foundry turns into a cheatcode revert. Both outcomes are indistinguishable from Solidity.

`PROJECT.md`'s core value is that **spec success, spec rejection, and transport failure must never be conflated**. Therefore:

> **Architectural constraint: spec rejection MUST be returned in the JSON-RPC `result` field as a tagged success response. The JSON-RPC `error` field is reserved exclusively for transport/protocol-level faults.**

This single constraint disqualifies any JSON-RPC library that opinionatedly maps a Haskell `Left`/exception onto the `error` channel — which most of them do. It is the strongest single argument for the hand-rolled envelope recommended below.

Transport failure then surfaces as a revert, catchable by wrapping the cheatcode call in an external call plus `try`/`catch`.

### Finding 3 — Transport-failure detection is slow by default

From `crates/common/src/provider/mod.rs` and `crates/common/src/constants.rs`:

| Setting | Default | Consequence |
|---|---|---|
| `max_retry` | `8` | A refused connection is retried 8 times |
| `initial_backoff` | `800` ms | Exponential backoff; worst case tens of seconds |
| `REQUEST_TIMEOUT` | `45` s | A hung server blocks 45 s per attempt |
| `compute_units_per_second` | `330` (Alchemy free tier) | Rate limiting — but see below |

`guess_local_url` sets `is_local: true` for localhost URLs, which avoids the CUPS rate limiter. Good: the bridge is local.

But the retry/backoff behaviour means **a down server can cost minutes of CI time per test case**, and a fuzz campaign would multiply that. `eth_rpc_timeout` is configurable in `foundry.toml` (confirmed: `config.eth_rpc_timeout` is read in `ProviderBuilder`). Whether `max_retry` is exposed as a `foundry.toml` key is **UNVERIFIED** — I found the builder method (`maybe_max_retry`) but did not confirm a config key wires to it. This needs a spike.

**Implication for the Haskell server:** it must never hang. Every handler needs a bounded execution time, because the client-side timeout is 45 seconds.

### Finding 4 — No prior art

Searches for using `vm.rpc`/`vm.rpcJson` against a non-Ethereum JSON-RPC service found nothing. The documented Foundry idiom for differential testing against another language is `vm.ffi` (Foundry's own issue #6509 calls ffi "an unsafe security hole, bad UX, and slow" — which is the case *for* this project's transport choice, but it does not follow that `vm.rpc` is a supported substitute).

**Confidence that this works end-to-end: LOW.** This is a novel path. Specifically unverified:
- Whether Foundry's alloy `ProviderBuilder::<AnyNetwork>::new(url).build()` performs eager chain-detection calls (e.g. `eth_chainId`) that a non-Ethereum server would have to answer.
- Whether alloy's response deserializer tolerates a JSON-RPC 2.0 response whose `result` is an arbitrary object.

**Roadmap implication: the very first phase must be a throwaway spike — a hardcoded `{"jsonrpc":"2.0","id":1,"result":"pong"}` responder hit by `vm.rpcJson` from a real `forge test`.** Everything else in this stack is contingent on that returning. This aligns with the existing requirement for "a payload-free health/echo method exercisable end-to-end", but that requirement should be re-scoped from "prove the transport shape" to "prove the transport works at all, before writing any Haskell of consequence."

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|---|---|---|---|
| **GHC** | `9.10.3` | Compiler | Anchor of Stackage LTS 24.56 (verified), so maximal library compatibility. Available from `haskell-actions/setup`. Every candidate library supports it. |
| **cabal-install** | `3.18.1.0` | Build tool | Preinstalled on `ubuntu-24.04` runners (verified in `actions/runner-images`). See "cabal vs stack" below. |
| **`base`** | `4.20.x` | — | Ships with GHC 9.10. |
| **`aeson`** | `2.2.5.0` | JSON | The Stackage LTS 24.56 **and** nightly-2026-08-26 version (verified — both snapshots still pin 2.2.5.0, not 2.3.x). See "The aeson 2.3 trap" below. |
| **`wai`** | `3.2.5` | HTTP interface | One type: `Request -> (Response -> IO ResponseReceived) -> IO ResponseReceived`. Nothing to learn, nothing to fight. |
| **`warp`** | `3.4.15` | HTTP server | The standard Haskell HTTP server. Fast startup, `Warp.runSettings` with `setInstallShutdownHandler` for clean SIGTERM shutdown. |
| **`http-types`** | `0.12.6` | Status codes/headers | Tiny, ubiquitous, needed by wai anyway. |
| **`text`** | `2.1.x` | — | Ships with GHC. |
| **`bytestring`** | `0.12.x` | — | Ships with GHC. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---|---|---|---|
| **`jsonrpc`** | `0.2.0.0` | JSON-RPC 2.0 envelope types | **Optional.** Read its single `JSONRPC` module and either depend on it or copy the envelope. See analysis below. |
| **`hspec`** | `2.11.17` | Test framework | Default choice for the test suite. |
| **`QuickCheck`** | `2.18.0.0` | Property testing | Round-trip codec properties (`decode . encode == Right x`). |
| **`hspec-golden`** | `0.2.2.0` | Golden tests | **Critical** — gates the generated `.sol` against a checked-in golden file. This is the mechanism that makes "drift becomes a compile error" actually true. |
| **`prettyprinter`** | `1.7.1` | Solidity rendering | Layout-aware rendering of generated Solidity. Alternative: plain `Data.Text` concatenation (see below). |
| **`optparse-applicative`** | `0.19.0.0` | CLI parsing | For the server exe (`--port`) and the codegen exe (`--out`). Only if you need more than one flag; otherwise skip it. |
| **`hspec-wai`** | `0.12.1` | HTTP-level tests | Exercise the wai `Application` in-process without binding a socket. |
| **`stm`** | ships with GHC | Readiness signalling | For the test harness to know the server is listening before Foundry calls it. |

### Development Tools

| Tool | Purpose | Notes |
|---|---|---|
| `haskell-actions/setup` | `v2.11.0` (released 2026-04-15, verified) | Pin `ghc-version: '9.10.3'`, `cabal-version: 'latest'`. |
| `actions/cache` | Dependency caching | Key on hash of `cabal.project.freeze` + GHC version. See CI section. |
| `cabal.project.freeze` | Reproducibility | **Non-negotiable.** Commit it. Without it the build is not reproducible across time. |
| `fourmolu` or `ormolu` | Formatting | Optional; do not gate CI on it in v1. |
| HLS | IDE | Do not put it in CI. |

---

## 1. JSON-RPC Server Libraries — Full Comparison

All data verified live against Hackage on 2026-08-27 (upload timestamps and dependency lists read from package pages and `.cabal` files).

| Package | Latest | Last upload | Deps | Server? | HTTP? | Verdict |
|---|---|---|---|---|---|---|
| `jsonrpc` | `0.2.0.0` | **2026-02-16** | aeson, base, text | Types only | Transport-agnostic | **Best candidate** |
| `json-rpc` | `1.1.3` | **2026-08-18** | conduit, conduit-extra, stm-conduit, monad-logger, unliftio, attoparsec, QuickCheck, vector, unordered-containers, hashable, deepseq, time, mtl | Yes | No — socket/conduit | Reject: weight + wrong transport |
| `servant-jsonrpc` | `1.2.0` | 2024-09-28 | aeson, base, http-media, servant, text | Types + servant combinator | **Yes** | Reject: unmaintained + drags servant |
| `servant-jsonrpc-server` | `2.2.0` | 2024-09-28 | + servant-server, containers | Yes | **Yes** | Same |
| `jsonrpc-conduit` | `0.4.1` | 2024-02-19 | conduit, attoparsec, mtl, unordered-containers | Yes | No — stdio/conduit | Reject: wrong transport |
| `jsonrpc-tinyclient` | `1.1.0.0` | 2026-02-09 | http-client-tls, websockets, mtl, random, exceptions | **Client only** | Yes | Reject: it is a client |
| `json-rpc-server` | `0.2.6.0` | **2017-01-14** | aeson <1.6, base <4.15 | Yes | No | **Dead.** Will not build on any modern GHC |
| `mcp-server` | `0.2.0.1` | 2026-08-01 | wai, warp, aeson, stm, template-haskell, http-types, base64-bytestring, network-uri | Yes | Yes | Not applicable, but see below |

### Detailed analysis

**`jsonrpc-tinyclient` — eliminated on category, not quality.** It is a *client*. The question asked for it to be compared; the comparison is short. It is actively maintained (2026-02-09, by `akru` of the `hs-web3` project) but it makes JSON-RPC calls, it does not serve them. It also bounds `base < 4.21`, capping it at GHC 9.10, and pulls `websockets` + `http-client-tls` — a TLS stack this project has no use for. **Do not use.**

**`json-rpc` — maintained but wrong shape.** The most recently updated of the classic options (2026-08-18, nine days before this research, by `jprupp` of Haskoin). Maintenance is not the problem; architecture is. It is built around `conduit` for long-lived bidirectional socket sessions, with `stm-conduit`, `monad-logger`, and `unliftio` in the dependency closure, and — notably — `QuickCheck` as a *library* dependency, not just a test dependency. That is a lot of transitive build weight for a service that answers one-shot HTTP POSTs. Its session/notification/batch machinery is dead weight for a request-response oracle. **Reject on dependency weight and transport mismatch**, given the stated mandate that build weight is a first-class criterion.

**`servant-jsonrpc` — the closest match on paper, and the most tempting mistake.** It is the only option that genuinely does JSON-RPC 2.0 over HTTP, its own dependency list is admirably small (5 packages), and Bitnomial are a credible maintainer. Three reasons to reject it:

1. **Unmaintained.** Last Hackage upload and last GitHub push are both 2024-09-28 — 23 months stale. 10 stars. Zero open issues, which at this activity level reads as "nobody is filing them" rather than "everything works."
2. **It drags in `servant` + `servant-server`.** That is the type-level routing machinery, `http-api-data`, `http-media`, and a long tail. For a service with two methods this is enormous overhead in both build time and cognitive load, and servant is a well-known source of inscrutable type errors that will cost more time than the routing it saves.
3. **It owns the error channel.** Its `JsonRpcErr` handling maps handler failures onto the JSON-RPC `error` field. Per Finding 2 above, this project must keep spec rejections *out* of that field. Fighting a library for control of its central abstraction is a bad trade.

Use it only if the project independently adopts servant for other reasons. It should not.

**`jsonrpc-conduit` — wrong transport, stale.** 2024-02-19, one reverse dependency. It is a conduit pipeline over stdio/streams (the shape LSP servers use), not HTTP. Adapting it to wai means writing the wai part anyway. **Reject.**

**`json-rpc-server` — dead.** 2017. `base < 4.15` (GHC ≤ 8.10), `aeson < 1.6`. It will not compile on GHC 9.10. Listed here only so it is explicitly ruled out.

**`jsonrpc` `0.2.0.0` — the newest and best-shaped option.** Uploaded 2026-02-16 by DPella AB. From its `.cabal` (read verbatim):

> "A lightweight implementation of the JSON-RPC 2.0 protocol types for Haskell with Aeson serialisation. Provides the core request, response, notification, and error types along with type classes for deriving JSON-RPC method dispatch via `DerivingVia`."

- Dependencies: `aeson >=2.1 && <2.3`, `base >=4.18 && <4.22`, `text >=2.0 && <2.2`. **Three packages.**
- One exposed module: `JSONRPC`.
- `tested-with: ghc ==9.12.2`.
- Transport-agnostic — it does not decide HTTP vs stdio, which is exactly right.
- MPL-2.0.

The risks are real and should not be glossed: **one release, six months old, two reverse dependencies, single vendor, no track record.** If DPella abandon it, you inherit it.

**`mcp-server` `0.2.0.1` — not a candidate, but a useful data point.** Uploaded 2026-08-01, actively developed. MCP is JSON-RPC 2.0, and this package implements a JSON-RPC 2.0 server over `wai`/`warp`. It is MCP-protocol-specific so it cannot be used directly, but its existence confirms that **`wai` + `warp` + `aeson` is the live 2026 idiom for serving JSON-RPC 2.0 from Haskell** — nobody reaches for `servant-jsonrpc`. Worth reading as a reference implementation.

### Recommendation

**Write the JSON-RPC 2.0 envelope yourself.** Concretely: a `Bridge.JsonRpc` module of roughly 150 lines defining `Request`, `Response`, `ErrorObject`, the `id`/`jsonrpc` field handling, and batch rejection.

Rationale, in priority order:

1. **The error/result channel split is load-bearing** (Finding 2) and is precisely the decision every library makes for you and makes wrong for this use case.
2. **The JSON-RPC 2.0 spec is genuinely small.** The envelope is a handful of records. This is not a case where hand-rolling means reimplementing something hard.
3. **Zero added dependencies**, against a stated mandate that build weight and CI installability are first-class selection criteria and that the consumer's runner toolchain is unverified.
4. **Every library on offer has a disqualifying defect** — dead, client-only, wrong transport, too heavy, or unmaintained-and-drags-servant.
5. The protocol surface is two methods, not two hundred. The abstraction a library provides has almost nothing to abstract over.

**Use `jsonrpc-0.2.0.0` as the design reference.** Read its `JSONRPC` module first. If its envelope types and `DerivingVia` dispatch fit cleanly and leave you in control of the `result` field, depending on it is a defensible three-package cost that saves you writing and testing the envelope. If it fights you at all, copy the ~150 lines under MPL-2.0 attribution and move on. **Do not let this decision block the transport spike** — it is reversible and small either way.

**Honest caveat:** "write it yourself" is the kind of advice that ages badly if the protocol surface grows. If v2 adds the spec-drives-EVM direction with batching, notifications, and dozens of methods, revisit this. For v1's two methods, it is the right call.

---

## 2. HTTP Server Layer

**Recommendation: `warp` + `wai` directly. No framework.**

| Option | Dependency closure | Verdict |
|---|---|---|
| **`warp` + `wai`** | wai, http-types, http2, network, streaming-commons, simple-sendfile, ... (warp's own, unavoidable) | **Use this** |
| `servant` + `servant-server` | warp's closure **+** servant, servant-server, http-api-data, http-media, singleton-bool, sop-core, ... | Reject |
| `scotty` `0.30` | warp's closure **+** wai-extra, regex-compat, monad-control, transformers-base, blaze-builder, cookie, http-api-data, resourcet, unliftio, random | Reject |

Dependency lists verified from Hackage package pages.

**Why warp+wai wins on the stated criteria:**

- **Every alternative is warp plus more.** Both scotty and servant-server run on warp. Choosing them adds dependencies without removing any.
- **Routing is not a problem here.** A JSON-RPC server has exactly one HTTP route: `POST /`. Method dispatch happens on the JSON `method` field, not the URL path. A router is the one thing frameworks give you and the one thing this service does not need. `scotty`'s `regex-compat` dependency exists to route URLs you will never have.
- **Fast startup.** The requirement is a service that starts quickly in CI. Warp's `run` binds and accepts immediately. Neither alternative is meaningfully slower at runtime, but both are slower to *compile*, which is the cost that actually recurs in CI.
- **Clean shutdown.** `Warp.setInstallShutdownHandler` and `setGracefulShutdownTimeout` on `Settings` give you deterministic SIGTERM handling. This matters: the requirement is a warm service across test cases, so the CI job must be able to stop it reliably and not leak a process that wedges the runner. Frameworks obscure access to `Settings`.
- **The whole server is one function.** `app :: Application` — read the body, decode, dispatch, encode, respond. Roughly 60 lines. There is no framework-shaped hole to fill.

**When to reconsider:** if the bridge ever needs to serve a real HTTP API surface (multiple paths, content negotiation, generated OpenAPI), servant earns its weight. v1 does not.

**Startup-time caveat:** I did not benchmark cold-start times for warp vs scotty vs servant, and would not trust a number I did not measure. The argument above rests on dependency closure size and compile time, both of which are verified, not on runtime startup benchmarks.

---

## 3. JSON Encoding

### Version: pin `aeson-2.2.5.0`

**The aeson 2.3 trap — this will bite you if you take the latest version.**

- Hackage's latest `aeson` is **`2.3.1.0`** (verified).
- Stackage **LTS 24.56 and nightly-2026-08-26 both still ship `2.2.5.0`** (verified against both snapshots).
- **`jsonrpc` bounds `aeson >=2.1 && <2.3`.** **`servant-jsonrpc` bounds `aeson >=1.3 && <2.3`.** **`deriving-aeson` bounds `aeson <2.3`.** **`scotty-0.30` bounds `aeson <2.3`.**

A large part of the ecosystem has not moved to aeson 2.3. Taking `2.3.1.0` means `--allow-newer` and hoping, or dropping those packages. **Pin `2.2.5.0` in `cabal.project.freeze`.** There is no feature in 2.3 this project needs.

### Idiom: hand-written codecs for wire types, `Generic` for everything else

This is the least fashionable answer and the correct one here.

**For the wire-contract types** (the JSON-RPC envelope, method params, method results, the `VolOrder` codec), **write `ToJSON`/`FromJSON` by hand** using `object`/`.=` and `withObject`/`.:`.

Rationale, and it is specific to this project rather than general advice:

1. **The wire format is a contract with a Solidity artifact that is generated from the same source.** Generic deriving puts the wire shape behind a typeclass and a set of `Options`. The codegen would then have to *replicate aeson's `Options` interpretation* to know what field names it produced — the exact drift the project exists to prevent. An explicit codec written against the same schema description the renderer consumes keeps one source of truth.
2. **The wire format is not yours to choose.** `PROJECT.md` records `VolOrder(T)` serialization as an OPEN decision owned by the consumer's Phase 4 (Shock-style tagged vs per-variant). When someone else dictates your wire shape, you need direct control of it, not `Options`-tweaking to approximate it.
3. **Tagged sum encoding is where generic deriving hurts most.** The three-way outcome (success / rejection-with-guard / transport-failure) is a sum type crossing the wire. aeson's `SumEncoding` options are a small menu; the consumer's chosen format may not be on it.

**For internal, diagnostic, and non-wire types**, use `deriving stock Generic` + `deriving anyclass (ToJSON, FromJSON)`. Zero ceremony where the shape does not matter.

### On the three deriving mechanisms

| Mechanism | Use for | Notes |
|---|---|---|
| **Hand-written instances** | **All wire types** | Recommended. Explicit, greppable, diffable, and the thing the codegen must agree with. |
| `Generic` + `genericToJSON opts` | Internal types | Fine. No extra dependency. |
| `DerivingVia` + `deriving-aeson` `0.2.10` | — | Skip. Last upload 2024-11-23, bounds `aeson <2.3`, and it only buys you type-level `Options` — which is the mechanism you want to avoid for wire types anyway. |
| TemplateHaskell `deriveJSON` | — | Skip. Adds `template-haskell`, slows compilation, worse errors, and provides no benefit over `Generic` in 2026. |

### Has anything replaced aeson?

**No.** aeson remains unambiguously the standard. Two things supplement it, neither of which you should adopt:

- **`autodocodec` `0.6.0.0`** (2026-07-24, actively maintained) implements "define a codec once, derive `ToJSON` + `FromJSON` + JSON Schema from it." This is *architecturally* the right idea for this project — one description, multiple outputs — and is the strongest argument against my recommendation above. **Reject it anyway**, because: it pulls `validity`, `validity-scientific`, `dlist`, `time`, `vector`, `unordered-containers`, `hashable`, `mtl`, `scientific`, `containers`; its schema output is JSON Schema, which is the wrong IR for generating Solidity (JSON Schema has no notion of `uint256`, `bytes32`, or ABI packing); and you would still write a JSON-Schema→Solidity renderer. You get the dependency cost without avoiding the work. Revisit only if the protocol surface grows large enough that hand-written codecs become a maintenance burden.
- **`aeson-typescript` `0.6.4.0`** — not a JSON library; see the codegen section, where it is the key precedent.

---

## 4. Haskell → Solidity Codegen

### Finding: nothing exists. You are building this.

Searched Hackage and the web. **There is no Haskell→Solidity code generator.** HIGH confidence on the negative claim — verified by Hackage package search and targeted web search, with the closest hits inspected individually.

The near-misses, and why each is not it:

| Candidate | What it actually does | Why not |
|---|---|---|
| `web3-solidity` `1.1.0.0` (2026-02-09) | Solidity **ABI JSON → Haskell** via TemplateHaskell; `Language.Solidity.Abi` is an ABI *parser*; `Data.Solidity.Prim` gives Haskell `UIntN`/`Address`/`BytesN` types | **Exactly the opposite direction.** Also bounds `base <4.21` (caps GHC at 9.10) and pulls `basement`, `memory`, `cereal`, `generics-sop`, `web3-crypto`, `parsec`, `OneTuple`, `template-haskell`. Heavy. |
| `abi-to-sol` | ABI JSON → Solidity interface | TypeScript. Would add a Node build to the runner — explicitly rejected by `PROJECT.md`'s "no third language" constraint. |
| `abi-codegen`, `stack-packer`, `eip712-codegen` | Solidity→Solidity or TS→Solidity | Wrong input language. |

One narrow, optional idea: `web3-solidity`'s `Data.Solidity.Prim` types (`UIntN 256`, `BytesN 32`) are a ready-made vocabulary for Solidity primitives. **Do not depend on the package for them** — the weight and the GHC 9.10 ceiling are not worth it. Define your own five-constructor `SolType` ADT.

### The precedent that proves the approach: `aeson-typescript`

**`aeson-typescript` `0.6.4.0`** (Hackage 2024-11-01; GitHub `codedownio/aeson-typescript` pushed **2026-04-21**, 68 stars — actively maintained) generates TypeScript type declarations from Haskell types via TemplateHaskell, deliberately consuming the *same* aeson `Options` as the type's JSON instances so the two cannot disagree.

That is structurally identical to this project's requirement with `TypeScript` swapped for `Solidity`. It is worth reading before writing a line of the generator: it is the closest thing to prior art, it is maintained, and it has already made the mistakes.

### Recommended approach: explicit IR + pure renderer

Four approaches are realistic. Ranked:

**1. Explicit IR + pure renderer — RECOMMENDED.**

Define the protocol schema as ordinary Haskell *values*, not as types to be reflected over:

- A schema ADT: `data SolType = SolUint Int | SolBytes Int | SolBool | SolString | SolStruct Text [Field] | SolArray SolType`, plus `data Field = Field { fieldName :: Text, fieldType :: SolType }`.
- A `protocolSchema :: [SolType]` value — the single source of truth.
- A pure renderer: `renderSolidity :: [SolType] -> Text`.
- The hand-written aeson codecs are written against the same schema, with a test asserting agreement.
- A `codegen` executable writes `src/generated/ISpecBridge.sol`.

Why this wins:

- **The IR is a value, so it is testable.** You can QuickCheck the renderer, golden-test its output, and unit-test edge cases — none of which is comfortable with TemplateHaskell.
- **No `template-haskell` dependency**, no staging restrictions, no cross-compilation grief, no compile-time slowdown.
- **Renderer errors are ordinary runtime errors** with ordinary stack traces, not TH splice failures.
- **The IR is exactly where Solidity-specific knowledge lives** — bit widths, `memory`/`calldata` location, ABI packing — which have no Haskell-type counterpart to reflect from. A generic traversal of `VolOrder` cannot know it should be `uint128`. That information must be written down somewhere; the IR is that somewhere.
- It is the most boring option, which is the mandate.

**2. TemplateHaskell reflection over the Haskell types — the `aeson-typescript` approach.** Genuinely viable and has the strongest precedent. Rejected for v1 because it is harder to test, adds `template-haskell` + `th-abstraction`, and — decisively — still cannot infer Solidity bit widths without per-type annotations, so you end up with an IR anyway, just one that is harder to inspect.

**3. Generic traversal (`generics-sop` `0.5.1.4` / `GHC.Generics`).** Same objection as TH, plus type-level programming that will outlive its usefulness. Rejected.

**4. Emit JSON Schema, render Solidity from it.** Adds a lossy intermediate format with no Solidity type vocabulary, and invites a second tool in a second language. Rejected — it is approach 1 with a worse IR and an extra hop.

### The mechanism that makes "drift becomes a compile error" true

Generation alone does not prevent drift — a stale checked-in `.sol` does. Two gates are required, and both belong in the roadmap:

1. **Golden test (`hspec-golden` `0.2.2.0`).** The test suite renders the schema and compares to the checked-in `.sol`. Schema change without regenerating ⇒ Haskell test suite fails.
2. **CI drift check.** CI runs `cabal run codegen` and then `git diff --exit-code` on the generated path. A regenerated-but-uncommitted file fails the build.

Gate 1 catches it locally; gate 2 catches it when someone skips the local run. Then `forge build` on the generated interface catches anything that renders but does not compile. That three-gate chain is what turns the `PROJECT.md` requirement into something real.

**Renderer implementation note:** `prettyprinter` `1.7.1` is the right tool if the generated Solidity needs real layout. For a file of a few structs and one interface, plain `Data.Text` with explicit newlines is honestly sufficient and is one fewer dependency. Start with `Data.Text`; reach for `prettyprinter` only if nesting gets painful.

---

## 5. Build & Toolchain

### cabal, not stack

**Use `cabal`.** Verified reasons:

- **Neither `jsonrpc` nor `servant-jsonrpc` is in Stackage** (both return 404 on LTS 24.56 and nightly-2026-08-26 — verified). With stack, every non-Stackage package needs an `extra-deps` entry with its own transitive resolution. With cabal they are ordinary Hackage dependencies.
- **`cabal.project.freeze` gives the same reproducibility** stack's resolver provides, without constraining you to one curated set.
- **The project already needs a source-repository dependency** on `d2p-finance/cfmm-vol-markets-spec` (as a git submodule per `PROJECT.md`). cabal handles this natively via a `packages:` stanza pointing at the submodule path, or a `source-repository-package` stanza. This is cabal's home turf.
- Both are preinstalled on the runner, so availability is not the tiebreaker — resolution model is.

### GHC version: target 9.10.3

Available from `haskell-actions/setup` (verified from its README version list): `9.14.1`, `9.12.4`, `9.12.2`, `9.10.3`, `9.10.2`, `9.8.4`, `9.6.7`, and older.

**`ubuntu-24.04` hosted runners preinstall GHC `9.14.1`, Cabal `3.18.1.0`, Stack `3.11.1`, GHCup `0.2.6.2`** (verified from `actions/runner-images` `Ubuntu2404-Readme.md`).

**The preinstalled version is a trap.** GHC 9.14 ships `base-4.22`, and:

- `jsonrpc` bounds `base >=4.18 && <4.22` ⇒ **excludes GHC 9.14**.
- `servant-0.20.3.0` declares `tested-with` up to GHC **9.12.1** (bounds allow `base <4.23`, so 9.14 would build, but untested).
- `web3-solidity` and `jsonrpc-tinyclient` bound `base <4.21` ⇒ **GHC 9.10 maximum**.

The base↔GHC mapping used above (9.6→4.18, 9.8→4.19, 9.10→4.20, 9.12→4.21, 9.14→4.22) is from training data and is **not independently re-verified** — but it is consistent with `jsonrpc` declaring `tested-with: ghc ==9.12.2` alongside `base <4.22`, which pins 9.12→4.21.

| GHC | Case for | Case against |
|---|---|---|
| **9.10.3** ✅ | Anchor of **LTS 24.56** — maximal library compatibility. Every candidate supports it. Widest chance of already existing on an unverified self-hosted runner. | ~2 min ghcup install on the hosted runner (cacheable). |
| 9.12.4 | Current nightly anchor. `jsonrpc` is `tested-with` 9.12.2. Good matrix second. | Less library soak time. |
| 9.14.1 ❌ | **Preinstalled — zero install time.** | Ahead of `jsonrpc`'s `base` bound and servant's tested range. Trading correctness for ~2 min is a bad trade. |

**Recommendation: `9.10.3` primary, `9.12.4` as an optional matrix entry.** Revisit when LTS moves to 9.12.

This choice also hedges the `PROJECT.md` risk that GHC/cabal on the consumer's self-hosted runner is unverified: 9.10.3 is the version most likely to be installable or already present, since it is what Stackage LTS currently anchors.

### CI shape

```yaml
runs-on: ubuntu-24.04
steps:
  - uses: actions/checkout@v4
    with:
      submodules: recursive      # cfmm-vol-markets-spec

  - uses: haskell-actions/setup@v2      # v2.11.0
    id: setup
    with:
      ghc-version: '9.10.3'
      cabal-version: 'latest'
      cabal-update: true

  - name: Resolve dependency plan
    run: cabal build all --dry-run     # writes dist-newstyle/cache/plan.json

  - uses: actions/cache/restore@v4
    id: cache
    with:
      path: ${{ steps.setup.outputs.cabal-store }}
      key: ${{ runner.os }}-ghc${{ steps.setup.outputs.ghc-version }}-${{ hashFiles('**/plan.json') }}
      restore-keys: ${{ runner.os }}-ghc${{ steps.setup.outputs.ghc-version }}-

  - run: cabal build all --only-dependencies

  - uses: actions/cache/save@v4
    if: steps.cache.outputs.cache-hit != 'true'
    with:
      path: ${{ steps.setup.outputs.cabal-store }}
      key: ${{ steps.cache.outputs.cache-primary-key }}

  - run: cabal build all
  - run: cabal test all
  - name: Codegen drift gate
    run: |
      cabal run codegen -- --out src/generated/ISpecBridge.sol
      git diff --exit-code src/generated/
```

**Caching notes:**

- **Cache the cabal store, not `dist-newstyle`.** The store holds compiled dependencies (the expensive part and the stable part). `dist-newstyle` holds your own rebuilt-every-commit objects and is prone to stale-cache corruption. `haskell-actions/setup` emits `cabal-store` as an output — use it rather than hardcoding a path, since it moved to `~/.local/state/cabal/store` in recent cabal versions.
- **Key on `plan.json`, not on `.cabal` files.** The install plan hash changes exactly when dependencies actually change. This is the documented cabal caching idiom and it is why `--dry-run` runs before the cache restore.
- Use split restore/save with `if: cache-hit != 'true'` so a partial-restore run still saves a complete store.

**Build times — clearly labelled as estimates.** I did not measure these and neither Hackage nor the runner images publish them.

| Scenario | Estimate | Confidence |
|---|---|---|
| Cold build, warp + aeson + hspec closure, GHC 9.10 | 8–15 min | **LOW — unmeasured** |
| Warm build, cabal store cached, deps unchanged | 1–3 min | **LOW — unmeasured** |
| GHC 9.10.3 install via ghcup on hosted runner | 1–3 min | **LOW — unmeasured** |
| GHC 9.14.1 (preinstalled) | ~0 | HIGH (preinstall verified) |

**Measure these in the first CI run and record the real numbers.** If cold build materially exceeds 15 minutes, the dependency footprint is the lever — which is a further argument for the hand-rolled JSON-RPC envelope and for warp-over-servant.

**Carried risk (from `PROJECT.md`, unresolved by this research):** hosted CI has been blocked by GitHub billing elsewhere in this ecosystem (`tao-plank-vault`). This entire CI strategy assumes hosted runners are available. That is a prerequisite, not an assumption this research can retire.

---

## 6. Testing

**Recommendation: `hspec` + `QuickCheck` + `hspec-golden`.**

| Library | Version | Role |
|---|---|---|
| `hspec` | `2.11.17` | Test framework |
| `QuickCheck` | `2.18.0.0` | Property testing |
| `hspec-golden` | `0.2.2.0` | Golden test for generated Solidity |
| `hspec-wai` | `0.12.1` | In-process HTTP tests against the wai `Application` |

### hspec over tasty

Both are current (`hspec` 2.11.17, `tasty` 1.5.4). Choose `hspec` because:

- **One dependency instead of four.** tasty needs `tasty` + `tasty-hunit` + `tasty-quickcheck` (+ `tasty-golden`); hspec's QuickCheck integration is built in via `property`, and `hspec-discover` removes the manual test-tree wiring tasty requires.
- **`hspec-wai` exists and is idiomatic** — it lets you exercise the JSON-RPC `Application` without binding a socket, which is exactly the test you want most.
- `jsonrpc-0.2.0.0` itself tests with hspec, so if you vendor or depend on it you are already aligned.

**Choose tasty instead if** you need to run the same property under multiple engines or want fine-grained `--pattern` filtering in CI. Neither applies to v1.

### QuickCheck over hedgehog

Both current (`QuickCheck` 2.18.0.0, `hedgehog` 1.7). Choose `QuickCheck` because:

- **hspec integrates with it natively** (`property`); hedgehog needs `hspec-hedgehog` or `tasty-hedgehog` as a bridge.
- Round-trip codec properties are simple generators where hedgehog's integrated shrinking advantage is smallest.
- QuickCheck's `Arbitrary` instances are already provided by more of the ecosystem.

**Choose hedgehog instead if** the `VolOrder` generators turn out to need heavy invariants and QuickCheck's shrinking produces unhelpfully large counterexamples. This is a plausible outcome for a fuzzing-adjacent domain — treat it as a reversible decision, not a commitment.

### The four test layers this project needs

1. **Round-trip codec properties** (`QuickCheck`): `decode (encode x) == Right x` for every wire type. Plus the direction that actually catches drift — **decoding fixtures produced by the other side** (Plank's `VolOrder(T)` bytes). A round-trip property proves you agree with yourself, not with Solidity.
2. **Golden test on generated Solidity** (`hspec-golden`): render the schema, diff against the checked-in `.sol`.
3. **JSON-RPC envelope conformance**: malformed JSON ⇒ `-32700`; unknown method ⇒ `-32601`; bad params ⇒ `-32602`. And the load-bearing one: **assert that a spec rejection produces a `result`, never an `error`** (Finding 2). That assertion is the executable form of the project's core value.
4. **In-process HTTP tests** (`hspec-wai`): POST bodies against the `Application`.

**What this stack cannot test:** whether Foundry's alloy client actually accepts your responses. That requires a real `forge test` in CI against the running server, and it is the only test that validates the transport hypothesis. Budget for it as a distinct CI job, not as part of `cabal test`.

---

## Installation

```bash
# No package manager install step — dependencies are declared in the .cabal file
# and resolved by cabal from Hackage.

cabal update
cabal build all
cabal test all
```

`evm-spec-bridge.cabal` — library stanza:

```cabal
build-depends:
    base          >=4.20 && <4.21
  , aeson         >=2.2  && <2.3
  , bytestring
  , text
  , containers
  , wai           >=3.2  && <3.3
  , warp          >=3.4  && <3.5
  , http-types    >=0.12 && <0.13
  -- optional, decide after reading its source:
  -- , jsonrpc    >=0.2  && <0.3
```

Test stanza:

```cabal
build-depends:
    hspec         >=2.11 && <2.12
  , hspec-wai     >=0.12 && <0.13
  , hspec-golden  >=0.2  && <0.3
  , QuickCheck    >=2.18 && <2.19
  , evm-spec-bridge
```

Then:

```bash
cabal freeze          # commit cabal.project.freeze — non-negotiable
```

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|---|---|---|
| Hand-rolled JSON-RPC envelope | `jsonrpc-0.2.0.0` | If reading its `JSONRPC` module shows the envelope fits and leaves you in control of `result`. Three-package cost; defensible. |
| Hand-rolled JSON-RPC envelope | `servant-jsonrpc` + `servant-jsonrpc-server` | Only if the project adopts servant for independent reasons. Accept unmaintained-since-2024 and the `error`-channel fight. |
| `warp` + `wai` | `servant-server` | If the bridge grows a real multi-route HTTP API. Not v1. |
| `warp` + `wai` | `scotty` | If you want ergonomic routing and do not care about ~10 extra transitive deps. Not aligned with the stated mandate. |
| Hand-written aeson codecs | `Generic` + `Options` | For internal and diagnostic types where the wire shape is not a contract. Use both, per type. |
| Explicit IR + renderer | TemplateHaskell à la `aeson-typescript` | If the type count grows past ~20 and hand-maintaining the IR becomes the bottleneck. |
| Explicit IR + renderer | `autodocodec` + JSON Schema | If the project later needs real JSON Schema output for other consumers. Accepts a lossy IR for Solidity. |
| `cabal` | `stack` | If the team has strong existing stack tooling. Costs `extra-deps` entries for `jsonrpc`/`servant-jsonrpc` (neither is in Stackage). |
| GHC 9.10.3 | GHC 9.14.1 | If CI minutes are the binding constraint and you drop `jsonrpc`. Saves ~2 min/run. |
| `hspec` + `QuickCheck` | `tasty` + `tasty-hedgehog` | If `VolOrder` generators need hedgehog's integrated shrinking. |
| `Data.Text` rendering | `prettyprinter` `1.7.1` | If generated Solidity nesting gets painful. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|---|---|---|
| **`json-rpc-server`** | Last upload **2017-01-14**. `base <4.15`, `aeson <1.6`. Will not compile on GHC 9.10. | Hand-rolled envelope |
| **`jsonrpc-tinyclient`** | It is a **client**, not a server. Also `base <4.21` (GHC ≤9.10) and pulls `websockets` + `http-client-tls`. | Hand-rolled envelope |
| **`json-rpc`** | Conduit/socket-session architecture, not HTTP. Drags `stm-conduit`, `monad-logger`, `unliftio`, `attoparsec`, and `QuickCheck` **as a library dep**. Fails the build-weight criterion. | Hand-rolled envelope |
| **`jsonrpc-conduit`** | stdio/conduit transport, not HTTP. Stale (2024-02). One reverse dependency. | Hand-rolled envelope |
| **`servant-jsonrpc` / `servant-jsonrpc-server`** | Unmaintained since 2024-09-28 (Hackage *and* GitHub). Drags the full servant stack. Owns the `error` channel that this project must control. | Hand-rolled envelope on `warp`+`wai` |
| **`scotty`** | Adds `wai-extra`, `regex-compat`, `monad-control`, `transformers-base`, `blaze-builder`, `cookie`, `resourcet`, `unliftio` on top of warp — for URL routing a JSON-RPC server does not have. Also bounds `aeson <2.3`. | `warp` + `wai` |
| **`web3-solidity`** | Generates **Haskell from Solidity ABI** — the opposite direction. `base <4.21` caps GHC at 9.10. Pulls `basement`, `memory`, `cereal`, `generics-sop`, `web3-crypto`, `parsec`. | Own `SolType` IR |
| **`abi-to-sol` / `abi-codegen`** | TypeScript. Adds a Node toolchain to the runner. | Own IR + renderer in Haskell |
| **`aeson` `2.3.x`** | Not in Stackage LTS 24.56 or nightly. `jsonrpc`, `servant-jsonrpc`, `deriving-aeson`, and `scotty` all bound `<2.3`. Forces `--allow-newer`. | `aeson-2.2.5.0` |
| **`deriving-aeson`** | Last upload 2024-11-23, bounds `aeson <2.3`, and its type-level `Options` are the mechanism to avoid for wire types. | Hand-written instances or plain `Generic` |
| **TemplateHaskell `deriveJSON`** | Adds `template-haskell`, slows compiles, worse errors, no benefit over `Generic` in 2026. | `Generic` or hand-written |
| **GHC 9.14.1 (preinstalled)** | `base-4.22` exceeds `jsonrpc`'s `<4.22` bound and servant's tested range. Saves ~2 min at the cost of ecosystem compatibility. | GHC 9.10.3 |
| **`vm.rpc` (the cheatcode)** | ABI-coerces the JSON result via `json_value_to_token` — designed for hex results, fragile for structured JSON. | **`vm.rpcJson`**, which returns raw JSON as `string` |
| **JSON-RPC `error` field for spec rejections** | Alloy turns any `error` response into a Rust `Err` ⇒ cheatcode revert ⇒ **indistinguishable from transport failure**. Directly violates the project's core value. | Tagged union in the `result` field |
| **Caching `dist-newstyle`** | Holds your own objects, rebuilt every commit, prone to stale-cache corruption. | Cache the cabal store, keyed on `plan.json` |
| **Unbounded handler execution** | Foundry's client timeout is 45 s with 8 retries. A hung handler wedges CI for minutes per call. | Bound every handler's execution time |

---

## Stack Patterns by Variant

**If the transport spike fails (Foundry's alloy client rejects a non-Ethereum JSON-RPC server):**
- The Haskell library, IR, renderer, codecs, and test stack are all **unaffected** and remain correct.
- Only the wai/warp HTTP layer is discarded, replaced by a stdin/stdout responder driven by `vm.ffi`.
- Because the JSON-RPC envelope is hand-rolled and transport-agnostic, that swap is contained. **This is a further argument against `servant-jsonrpc`, which would couple the envelope to HTTP.**

**If the consumer's self-hosted runner turns out to lack GHC:**
- Ship a statically linked binary artifact from this repo's hosted CI, consumed by the runner. The `warp`+`wai` closure links cleanly; a servant-based build is larger and more fragile to link statically.

**If the protocol surface grows past ~20 methods (v2, spec-drives-EVM):**
- Revisit the hand-rolled envelope in favour of `jsonrpc-0.2.0.0`'s `DerivingVia` dispatch.
- Revisit hand-written codecs in favour of `autodocodec`.
- Revisit `warp`+`wai` in favour of `servant`.
- All three are the right call at scale and the wrong call for two methods.

**If CI build time exceeds ~15 minutes cold:**
- Dependency footprint is the lever. Drop `optparse-applicative`, `prettyprinter`, and `hspec-wai` first — all are conveniences.

---

## Version Compatibility

| Package | Compatible With | Notes |
|---|---|---|
| `aeson-2.2.5.0` | `jsonrpc-0.2.0.0`, `servant-jsonrpc-1.2.0`, `deriving-aeson-0.2.10`, `scotty-0.30` | **All of these bound `aeson <2.3`.** Do not upgrade to `2.3.1.0`. |
| `jsonrpc-0.2.0.0` | GHC 9.6 – 9.12 (`base >=4.18 && <4.22`) | **Excludes GHC 9.14.** `tested-with: ghc ==9.12.2`. |
| `servant-0.20.3.0` | GHC up to 9.12.1 tested; `base <4.23` | 9.14 permitted by bounds but untested. |
| `jsonrpc-tinyclient-1.1.0.0`, `web3-solidity-1.1.0.0` | GHC ≤ 9.10 (`base <4.21`) | Both would pin you to 9.10. Neither is recommended. |
| `warp-3.4.15` / `wai-3.2.5` | `base >=4.12 && <5` | Unconstrained in practice. LTS 24.56 ships `warp-3.4.9`; either is fine. |
| `GHC 9.10.3` | LTS 24.56 (verified), `aeson-2.2.5.0`, `servant-server-0.20.3.0`, `warp-3.4.9` | The maximum-compatibility choice. |
| `GHC 9.14.1` | Preinstalled on `ubuntu-24.04` | **Incompatible with `jsonrpc-0.2.0.0`.** |

---

## Open Questions / Gaps

Explicitly unresolved by this research:

1. **Does `vm.rpcJson` work against a non-Ethereum JSON-RPC server at all?** No prior art found. Specifically: does Foundry's `ProviderBuilder::<AnyNetwork>::new(url).build()` make eager chain-detection calls the bridge would have to answer? Does alloy's deserializer accept an arbitrary object in `result`? **Confidence LOW. Requires a spike before anything else is built.**
2. **Is `max_retry` exposed as a `foundry.toml` key?** `eth_rpc_timeout` is confirmed wired to the builder; the retry count is not. Affects how badly a down server degrades CI time.
3. **Is a `vm.rpcJson` transport failure catchable via `try`/`catch`?** Believed yes (cheatcode errors revert, and reverts from an external call are catchable), but not verified against Foundry's cheatcode error propagation. **This is the mechanism the three-way outcome distinction depends on.** MEDIUM confidence — verify in the same spike.
4. **Real build times.** All estimates are unmeasured. Record actuals from the first CI run.
5. **The base↔GHC version mapping** is from training data, not independently re-verified (though corroborated by `jsonrpc`'s `tested-with` + `base` bound pairing).
6. **`jsonrpc-0.2.0.0`'s actual API.** Its Haddocks were not reachable during research; the assessment rests on its `.cabal` description, dependency list, and module list. Read the source before depending on it.
7. **The `VolOrder(T)` wire format** remains owned by the consumer's Phase 4 (per `PROJECT.md`). The codec design consumes that decision; nothing here pre-empts it.

---

## Sources

All verified live on 2026-08-27.

**Hackage (HIGH confidence — authoritative, queried directly):**
- `hackage.haskell.org/package/{jsonrpc,json-rpc,jsonrpc-conduit,servant-jsonrpc,servant-jsonrpc-server,jsonrpc-tinyclient,json-rpc-server,mcp-server}` — versions, upload timestamps, dependency lists
- `hackage.haskell.org/package/jsonrpc-0.2.0.0/jsonrpc.cabal` — full cabal file, `tested-with`, bounds, description
- `hackage.haskell.org/package/servant-jsonrpc-1.2.0/servant-jsonrpc.cabal` + revisions — confirmed no bound-relaxing revision
- `hackage.haskell.org/package/{aeson,warp,wai,scotty,servant,hspec,tasty,QuickCheck,hedgehog,autodocodec,aeson-typescript,deriving-aeson,web3-solidity,prettyprinter}` — latest versions, deps, upload dates

**Stackage (HIGH confidence):**
- `stackage.org/lts-24.56` — GHC 9.10.3, `aeson-2.2.5.0`, `servant-server-0.20.3.0`, `warp-3.4.9`
- `stackage.org/nightly-2026-08-26` — GHC 9.12.4, `aeson-2.2.5.0`, `warp-3.4.15`
- Confirmed `jsonrpc` and `servant-jsonrpc` are **absent** from both (404)

**Foundry source, `master` branch (HIGH confidence — read directly, not from docs):**
- `crates/cheatcodes/src/evm/fork.rs` — `rpc_call`, `rpc_json_call`, `rpc_result`, `convert_to_bytes`
- `crates/cheatcodes/assets/cheatcodes.json` — `rpc_0`, `rpc_1`, `rpcJson_0`, `rpcJson_1` declarations
- `crates/common/src/provider/mod.rs` — `max_retry: 8`, `initial_backoff: 800`, `is_local`/`guess_local_url`
- `crates/common/src/constants.rs` — `REQUEST_TIMEOUT = 45s`, `ALCHEMY_FREE_TIER_CUPS = 330`

**GitHub (HIGH confidence — API queried directly):**
- `actions/runner-images` `Ubuntu2404-Readme.md` — GHC 9.14.1, Cabal 3.18.1.0, Stack 3.11.1, GHCup 0.2.6.2 preinstalled
- `haskell-actions/setup` releases — v2.11.0 (2026-04-15); README GHC/cabal/stack version lists
- `bitnomial/servant-jsonrpc` — `pushed_at: 2024-09-28`, 10 stars, not archived
- `codedownio/aeson-typescript` — `pushed_at: 2026-04-21`, 68 stars

**WebSearch (LOW–MEDIUM confidence, used only for negative claims and precedent):**
- Haskell→Solidity codegen search — no library found; `abi-to-sol`, `abi-codegen`, `stack-packer` inspected and ruled out
- Foundry differential testing — `vm.ffi` is the documented idiom; `foundry-rs/foundry` issue #6509 on ffi's shortcomings
- `getfoundry.sh/reference/cheatcodes/rpc/` — confirmed docs do **not** specify `vm.rpc` encoding behaviour, which is why source was read

---
*Stack research for: Haskell JSON-RPC spec oracle for Foundry differential testing*
*Researched: 2026-08-27*
