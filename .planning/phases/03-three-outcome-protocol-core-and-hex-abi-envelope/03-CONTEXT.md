# Phase 3: Three-Outcome Protocol Core and Hex-ABI Envelope - Context

**Gathered:** 2026-08-28
**Status:** Ready for planning

<domain>
## Phase Boundary

**The Core Value stops depending on discipline and becomes a property of the types.**

Spec success, spec rejection and transport failure become three constructors that no partial
function can turn into one another, and the wire representation survives Foundry's value-dependent
JSON→ABI coercion byte-exact.

Requirements: **PROTO-01, PROTO-02, PROTO-03, PROTO-04, PROTO-07, INTEG-02**.

**In scope:** the result sum type, the closed guard enum, the hex-ABI envelope layout, the
encoder/decoder, the call-site shape that makes a wedged oracle red, one hand-written Solidity test,
and a boundary sweep through real `forge test`.

**Out of scope:** the JSON-RPC method surface (`spec_health`, fixtures, `-32601`) is **Phase 4**;
the warm server, deadlines and lifecycle are **Phases 5-6**; codegen is **Phase 8-9**; `VolOrder`
is **Phase 11**. Phase 3's Solidity is hand-written **deliberately** — Phase 9 replaces it.

**Why it must not be rushed** (ROADMAP): every decision here is rewrite-forcing if omitted. The
rejection channel, envelope shape, closed guard enum and `protocolVersion` are near-zero cost now
and rewrite everything downstream later.

</domain>

<decisions>
## Implementation Decisions

### Execution model — GOVERNING, carried from Phase 2 as amended

- **Heavy pedagogical.** Concepts explained, not merely applied. Explanations are reported at
  **plan boundaries** rather than at each decision.
- **Every decision carries a reference pointer** — `file:line`, source URL, or a measurement.
- **Checkpoints stay inline with the user**, mid-plan. Batching applies to teaching, never to consent.
- **Background agents: forbidden by default, permitted on explicit user approval, for mechanical
  tasks INCLUDING authoring code chunks.** Delegation moves the typing, never the consent.
- **The executing work owns the STATE.md / ROADMAP.md update**, in-plan.
- **Reviewer gate: the user is the review.** The global `CLAUDE.md` two-step reviewer mandate is
  deliberately overridden for this project by user decision. `plan_checker` stays disabled.

### Envelope byte layout

- **`abi.encode(uint16 protocolVersion, uint8 tag, bytes body)`.**
- **Version FIRST.** It travels with the bytes the test actually decodes, so a version mismatch is
  caught where the payload is read — not in a JSON field the Solidity side never sees. Putting it
  in the JSON object instead would return a load-bearing field to the coercion path the envelope
  exists to escape (objects become alphabetically-ordered tuples).
- **Tag SECOND, a `uint8`.** ROADMAP criterion 1 says "reading a tag byte" — this is the literal
  form. Solidity reads the tag, then decodes `body` against the type that tag selects.
- **`bytes body`, variable length.** Phase 2 MEASURED that `convert_to_bytes` preserves true
  length: a 20-byte payload returned as length `0x14`, not padded to 32. Variable-length bodies are
  safe on the `vm.rpc` path.
- **REJECTED — discriminating by payload length.** That is exactly the value-dependent inference
  Phase 2 was spent eliminating. Recorded so it is explicitly rejected, not silently absent.
- **The envelope is designed as Phase 8's generator input from the start.** The Haskell type IS the
  schema. Generation is retrofit-expensive; doing it over a hand-shaped envelope means reshaping
  the envelope.

### Guard identity representation

- **Named cfmm constructors, in the core `protocol` component.** Consistent with PROJECT.md's
  "cfmm-first, generalize later" — v1 explicitly knows about `VolOrder`.
- **This does NOT violate CFMM-01.** The seam forbids a core component from `build-depends`-ing on
  the spec *package*. Naming a constructor after a cfmm guard creates no package dependency. The
  seam guard stays green; verify with `./scripts/seam-guard.sh`.
- **The enum CANNOT be derived from the spec's guard type** — that WOULD be a package dependency
  from core, and would fail to *resolve* under `stack-core.yaml` with `[S-4804]`.
- **`cfmm-adapter` maps spec guard → protocol enum, with an exhaustive match.** That match IS the
  compile error INTEG-02 demands: a new guard in the spec breaks the adapter's build. This realises
  PROJECT.md's RPC-02 split — the spec *evaluates* guards, the bridge only *maps* them — and is
  what Phase 11 criterion 4 means by "verifiable by inspection of a single mapping function".
- **Guard id ONLY on the wire. No free-text guard string, at all.** Strictest reading of INTEG-02:
  if no string exists, no consumer can begin matching on one. Diagnostics live in the server log,
  keyed by request. A "non-contractual" comment is not a mechanism.
- **Solidity consumes a generated enum (Phase 8).** Phase 3 hand-writes the equivalent so the test
  can assert on a named guard; Phase 8 replaces it with the generated artifact and CI goes red on
  drift. Hand-maintained Solidity constants are the drift the codegen exists to kill.

### The wedged-oracle red (criterion 3)

Defends the MEASURED failure at `PITFALLS.md:186` — *a wedged oracle costs 45 s per fuzz case and
the test still passes*. The 45 s timeout is hardcoded and unreachable from `foundry.toml`
(`ProviderBuilder::new` defaults, not `from_config`).

- **Two mechanisms, deliberately paired across phases:**
  - **Call site bounds the OUTCOME — Phase 3.** No path returns without producing a verdict, so a
    non-answer reverts. Catches it regardless of server behaviour, including a server that dies
    mid-request. It cannot shorten the 45 s.
  - **Server bounds the COST — Phase 5, SRV-04.** A handler exceeding its own deadline returns a
    typed fault well inside 45 s. **NOT Phase 3 scope** — there is no server component until
    Phase 4. Recorded here as the deliberate counterpart so Phase 5 does not re-derive it.
- **A deliberate never-answer fixture in the test harness** proves the red: a stub mode that
  accepts the connection and sleeps forever. Same discipline as Phase 1's negative seam test and
  Phase 2's server-down run — make the guard fire on purpose. **Reusable by Phase 5's soak and
  Phase 9's generated call site**, which is why it is built here.
- **Transport failure REVERTS and fails the test unconditionally.** INTEG-05: no skip, no degrade,
  no branch treating an unreachable oracle as agreement. The cheatcode already reverts; the call
  site must not catch and continue.
- **REJECTED — catching the revert and re-surfacing it as a typed third outcome in Solidity.** It
  would make the three outcomes uniform, but it creates a path where an unreachable oracle is a
  *value* rather than a stop — one refactor from being treated as a skip.

### Boundary sweep scope

- **Six classes, hex encoding only:** zero, above 2^64, negative, empty, 32-byte, odd-nibble.
  This proves OUR encoding is total across the classes that break naive ones.
- **Round-trip through a REAL `forge test`**, not Haskell-side only. Criterion 2 says "byte-exact",
  which only means something end-to-end through Foundry's coercion. An encoder tested against its
  own decoder is the one pairing that structurally cannot detect a coercion problem.
- **Type-level, not a property test.** A JSON number or `null` must be **UNREPRESENTABLE** in the
  result type, evidenced by the type definition. **ROADMAP criterion 2 amended accordingly** — it
  previously required a property test, which would be *vacuous by construction* once the type
  holds, and a trivially-passing test is the artifact this project keeps removing.
- **NOT in this phase:** arrays, and the three-encoding comparison (hex / decimal string / raw
  number). Both go to **Phase 8's coercion-conformance fixture** (criterion 4). See Deferred.

### Claude's Discretion

- Module layout within `protocol`, `abi-codec`, `jsonrpc`; which component owns which type.
- The concrete tag byte values and `protocolVersion`'s starting value.
- Whether the wedge fixture is a new stub or a mode on a rebuilt one, and where it lives.
- Whether the hand-written Solidity for Phase 3 lives in a throwaway directory (as Phase 2's did)
  or a permanent one — note Phase 2's `spike/` is deleted and there is currently **no forge project
  in the repo**.
- How far to take the type-level unrepresentability (newtype with a single `ToJSON`, or stronger).

</decisions>

<specifics>
## Specific Ideas

- **The framing that drove every decision here:** Foundry hands Solidity exactly ONE BIT — did the
  cheatcode revert or not. Connection refused, HTTP 500, malformed body, the 45 s timeout and a
  well-formed JSON-RPC `error` object all arrive as the identical `0xeeaa9e6f`. Every distinction
  the project needs must therefore be built INSIDE a successful response, by us.
- **The move this phase makes:** from "remember rejections go in `result`" to "a rejection cannot
  be constructed into the `error` channel". From "check the call succeeded" to "a call site that
  skips the check does not compile".
- **Nothing on our path contradicts a type.** There is no typed cheatcode between the wire and our
  `abi.decode`. Every field's type is asserted by our schema alone — which is exactly why the array
  signedness finding bites us and not a forge-std consumer.
- Phase 1-2 rules still in force: **exit code before greps**; every number carries its conditions;
  a guard nobody has seen fire is a guard being trusted; a criterion phrased against a tool needs
  evidence the tool exists; **a measurement is scoped to its CODE PATH as much as to its version**.

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project governance
- `.planning/PROJECT.md` — Constraints and Key Decisions. **Note the three entries added
  2026-08-28** (json-rpc envelope source, envelope layout, guard identity) and the SUPERSEDED
  strikethrough on the hand-rolled-envelope rationale
- `.planning/REQUIREMENTS.md` — PROTO-01/02/03/04/07 and INTEG-02 are this phase's requirements;
  `[M]` markers denote measured behaviour that must not be relaxed without re-measuring
- `.planning/ROADMAP.md` — Phase 3 success criteria (**criterion 2 amended 2026-08-28**) and the
  "Governing Decisions Applied" section
- `.planning/phases/02-transport-spike-throwaway/02-CONTEXT.md` — the execution model this
  document carries forward, and the json-rpc adoption decision
- `.planning/phases/02-transport-spike-throwaway/02-SUMMARY.md` — what Phase 2 proved and,
  importantly, **what it did NOT prove**

### Measured transport behaviour — read before writing any encoder or Solidity
- `.planning/research/PITFALLS.md` §7 (method note), **§55-82 (value-dependent coercion and the
  hex rule)**, §100-115 (return-path shape), §134-157 (`rpcJson` absent), §161-164 (`null` → 32
  zero bytes), **§186 (the 45 s hang that passes — criterion 3's target)**
- `.planning/research/ARCHITECTURE.md` §28 (stateless 3-arg form), §101/§405 (`guess_local_url`
  proxy trap, `[S]` and unverified), §103 (per-call provider)
- `.planning/research/FEATURES.md` §27 — **`convert_to_bytes` runs on the `vm.rpc` path only**;
  this is why our coercion rows do NOT transfer to `vm.parseJson`
- `.planning/phases/02-transport-spike-throwaway/02-01-PROBE-NOTES.md` — the 20-byte/Address
  measurement, the Content-Type matrix, and the `id:0` finding

### The library
- https://hackage.haskell.org/package/json-rpc-1.1.2 — `Network.JSONRPC.Data` is the envelope
  surface (`Response` vs `ResponseError` as separate constructors); `Network.JSONRPC.Interface` is
  REJECTED (TCP-conduit only)

### The seam
- `scripts/seam-guard.sh`, `stack-core.yaml` — CFMM-01. Adding a spec dependency to a core
  component fails to RESOLVE. The guard enum must live in `protocol` without one

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`components/protocol/src/Bridge/Protocol.hs`** — placeholder; becomes the result sum type,
  guard enum and `protocolVersion`. Currently `dependencies: [base]` only.
- **`components/abi-codec/src/Bridge/AbiCodec.hs`** — placeholder; becomes the hex + ABI encoding.
- **`components/jsonrpc/src/Bridge/JsonRpc.hs`** — placeholder; its comment was **corrected
  2026-08-28** (it claimed the envelope was hand-rolled).
- **`components/protocol/test/Main.hs`** — the `tasty` scaffold, already running in the gate.
- **`justfile`** — `seam`, `seam-negative`, `build`, `test`, `drift`, `foundry-pin`, `image`,
  `image-run`. The spike recipes were removed in 02-05.
- **`scripts/foundry-pin.sh`** — assert the pin before ANY measurement.

### Established Patterns
- **Guards are scripts that exit non-zero**, invoked by the identical string from `just` and CI.
- **Measurements land in a phase PROBE-NOTES with their conditions stated.**
- **A guard is made to fail on purpose**, in at least two distinguishable ways.
- **hpack drift gate globs `*.cabal` REPO-WIDE** — any new package's generated `.cabal` must be
  committed or the gate goes red.
- Adding dependencies means editing `package.yaml` and regenerating; the drift gate catches a
  forgotten regeneration.

### Integration Points
- `protocol` ← `abi-codec` ← `jsonrpc` is the expected direction; none may depend on the spec.
- `cfmm-adapter` is the ONLY component permitted a spec edge, and owns the guard mapping.
- **There is currently NO forge project in the repo** — `spike/` was deleted in 02-05. Phase 3
  needs one for its Solidity test and boundary round-trip.
- **`forge` v1.5.1 / `b0a9dd9`** is pinned and asserted; `just spike-test`-style recipes were
  removed and will need re-creating in whatever form Phase 3 chooses.

</code_context>

<deferred>
## Deferred Ideas

- **Arrays, and the three-encoding comparison (hex / decimal string / raw number)** → **Phase 8's
  coercion-conformance fixture** (criterion 4). Arrays matter because on our untyped path a
  wrong-branch decode CANNOT revert — `int256[]` and `uint256[]` are byte-identical. **`gams-evm-
  transport` is owed these results measured on the `vm.rpc` path**; tell them when Phase 8 runs.
- **Server-side handler deadline** → **Phase 5, SRV-04**. Paired with Phase 3's call-site guard.
- **Propagating the container decision into ROADMAP phases 6 and 10** — carried unresolved since
  Phase 1. **Must happen before Phase 6 is planned.**
- **The fork → upstream promotion PR has never been opened.** DIST-03 is Met on the *negative*
  (direct push refused), but the sanctioned path is untested end-to-end. Matters at Phase 10.
- **Acceptance criteria should read effective config, not grep source text** — two Phase 2 criteria
  were satisfied by comment wording.
- **`guess_local_url` / `HTTP_PROXY` remains `[S]`**, never observed → Phase 6, SRV-01.

</deferred>

---

*Phase: 03-three-outcome-protocol-core-and-hex-abi-envelope*
*Context gathered: 2026-08-28*
