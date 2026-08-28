# Phase 2: Transport Spike (Throwaway) - Context

**Gathered:** 2026-08-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Prove that Foundry's `vm.rpc` cheatcode can reach a **Haskell `warp` HTTP server** and get a usable
value back, on the Foundry version the consumer actually pins. Pin that version in a form that can
fail. Everything built here is discarded.

Requirements: **DIST-06**.

In scope: a throwaway warp stub, one green `forge test`, the Content-Type conformance matrix, the
hex-envelope round-trip, and the toolchain pin. Out of scope: registry, codegen, domain logic, the
real protocol envelope, and any abstraction over `vm.rpc`.

**Rescoping note — this phase is much smaller than the roadmap implies.** Three of its four
success criteria were already satisfied before it started (see Empirical Scope below), and the
fourth names a file that cannot satisfy it. ROADMAP Phase 2 is amended alongside this document.

</domain>

<decisions>
## Implementation Decisions

### Execution model — GOVERNING, supersedes 01-CONTEXT's weaker formulation

- **Heavy pedagogical.** Every concept is explained, not merely applied. A step that produces the
  right artifact while leaving the user unable to explain it has half-failed. **Amended
  2026-08-28:** explanations are reported at PLAN BOUNDARIES rather than at each individual
  decision. Checkpoints still interrupt mid-plan — batching applies to teaching, not to consent.
- **Every decision carries a reference pointer** — a `file:line`, a source URL, or a measurement.
  Not "it is known that" and not recall.
- **User checkpoints between decisions.** Ask in between; do not present a finished wall of work.
- **Background agents: forbidden by default, permitted on EXPLICIT user approval** (amended
  2026-08-28 mid-execution). When approved, delegation covers **mechanical tasks — including
  authoring code chunks** (the Haskell stub, the Solidity test), not merely config files, CI wiring
  and builds. Every `checkpoint:decision` and `checkpoint:human-verify` task stays inline with the
  user regardless of approval: delegation moves the typing, never the consent.
- **The executing skill owns execution AND the STATE.md / ROADMAP.md update**, inline. This exists
  because Phase 1's ledger was never updated — ROADMAP read `0/9` and STATE said "Ready to plan"
  while nine plans sat committed; it was patched by hand afterwards in `41eb40c`.
- **Reviewer gate: the user is the review.** The global `CLAUDE.md` two-step parallel reviewer gate
  (Reality Checker + one specialist) is **deliberately overridden for this project** — no reviewer
  agents. This is consistent with `plan_checker: false` and is a user decision on the record, not
  an omission.
- Commits go directly to `develop` on the fork; worktree-per-plan stays suspended while execution
  is inline.

### JSON-RPC library — adopt the envelope, reject the transport

- **Use `Network.JSONRPC.Data` from `json-rpc-1.1.2`.** Verified present in LTS 24.55 (Stackage
  redirects `/lts-24.55/package/json-rpc` → `json-rpc-1.1.2`), so it needs **no `extra-deps`
  entry** and the snapshot-matching constraint is untouched.
- **Do NOT use `Network.JSONRPC.Interface`.** Its only transports are `jsonrpcTCPClient` /
  `jsonrpcTCPServer` — raw TCP over conduit. The package depends on `conduit`, `conduit-extra`,
  `stm-conduit`, `attoparsec` and **no HTTP library whatsoever**. Foundry POSTs HTTP via alloy, so
  a conduit TCP server would receive `POST / HTTP/1.1\r\n...` as bytes and never emit a valid HTTP
  response. The library's own docs say "You may use any underlying transport."
- **The HTTP layer is ours**, on `wai-3.2.5` / `warp-3.4.9` — both verified in LTS 24.55.
- What the Data layer buys us, concretely:
  - `errorMethod` = `ErrorObj "Method not found" (-32601)` — exactly PROTO-08
  - `errorParams` (-32602), `errorInvalid` (-32600), `errorParse` (-32700)
  - `Id`, `Ver`, `BatchRequest`/`BatchResponse` — PROTO-09, PROTO-10
  - `Response { getResult :: !Value }` takes our `"0x" <> hex(...)` string directly
  - **`Response` and `ResponseError` are separate constructors**, so "a rejection never travels on
    the JSON-RPC error channel" becomes a question of which constructor a handler may build —
    structural, not a rule people follow.
- **This overrides a recorded Key Decision.** PROJECT.md states the envelope is hand-rolled, and
  the Stack-over-cabal rationale cited it ("moot, since the envelope is hand-rolled"). Adopting
  `json-rpc` does not weaken the Stack choice — it strengthens it, since the package is snapshot-
  resident and would be an extra-dep under cabal. PROJECT.md's Key Decisions table must be amended.
- **The exception firewall still applies.** `getResult` is strict only in the `Value` constructor;
  thunks inside can still throw during serialization after the outcome was classified success.
  `try . evaluate . force` does not go away.

### The spike stub itself

- **Crudest possible stub: hand-written JSON response bytes in warp.** The spike's one job is
  proving `vm.rpc` reaches Haskell; a library in the path is a second variable if it goes red.
  `json-rpc` adoption happens in Phase 3/4 where the envelope is actually designed.
- **Server runs as a locally built binary via `stack run`**, not the published image. Fastest
  edit-rebuild-rerun loop for an inline session, and it avoids coupling a throwaway to the image
  pipeline.
- **Address the server as `http://127.0.0.1:PORT`, never `0.0.0.0` and never a hostname.**

### Foundry pin (DIST-06)

- **Mirror the consumer's idiom exactly**: a shell-sourceable `.github/foundry-version` carrying
  the same three values — `FOUNDRY_VERSION`, `FOUNDRY_COMMIT`, `FOUNDRYUP_INSTALLER_COMMIT`. One
  recognisable format across both repos so a human comparing them sees drift instantly, and
  `KEY=value` is parseable in a few lines of Haskell for Phase 8's header stamping (second
  consumer: the generator, not just CI shell).
- **The values must match the consumer's**: `v1.5.1` / `b0a9dd9ceda36f63e2326ce530c10e6916f4b8a2`.
- **The assertion fires in CI AND in the spike's runner script.** The consumer asserts in CI only;
  we add the local one because a measurement taken on a `foundryup`-drifted box would look measured
  and be scoped to the wrong binary — Phase 1's recurring failure class.
- **Copy the pin, not the plumbing.** The consumer's per-pin `FOUNDRY_DIR`, `flock` and stamp file
  exist because `cfmm-build` is a **persistent self-hosted runner** where installing to
  `$HOME/.foundry` would rewrite the box's default forge on every push. **We run hosted ephemeral
  runners** — a fresh VM cannot have a colliding forge. Lifting their step wholesale would be
  cargo-culting: a correct mechanism applied outside the conditions that made it correct.
- **`foundry.toml` cannot pin a forge version.** Measured on the pinned binary: `forge config
  --json` emits 111 keys and the only version-ish one is `evm_version` (the EVM hardfork). ROADMAP
  criterion 3 is amended to name the enforceable mechanism, with this measurement as the reason.

### CI vs local measurement

- **Local measurement only.** The spike's `forge test` does not enter the gate. It is run on this
  box, recorded in PROBE-NOTES, and deleted with the spike.
- **Rationale:** a CI test earns its keep by catching change, but pinning Foundry means the
  transport cannot change without a reviewable commit — the test would guard a constant. More
  decisively, **ROADMAP Phase 8 criterion 4 already schedules the permanent version** ("a
  Foundry-coercion conformance fixture in CI goes red when the toolchain changes coercion
  behaviour"), correctly placed beside the drift gate where a real schema exists.
- **Do not build a permanent lane out of throwaway code.**
- **Reproducibility: a `just` recipe** the user can re-run and modify — starting the server,
  running `forge test`, tearing down. Extends the `justfile` pattern from 01-05.
- **Unmeasured, must not be estimated:** the cost of a Foundry install on a hosted runner. Known
  costs for comparison (01-01-PROBE-NOTES): `haskell-actions/setup` 106 s, seam job 125 s, build
  job 440 s.

### Empirical scope — what is genuinely open

Three of the four questions research posed for this phase were **already measured against
`1.5.1-stable`/`b0a9dd9` — byte-identical to the binary the consumer pins**. They are consumed,
not re-derived:

| Question | Status | Reference |
|---|---|---|
| (a) does `try`/`catch` catch a cheatcode revert? | **MEASURED** | PROJECT.md "Resolved since initialization" — `0xeeaa9e6f`, non-empty errdata with the cheatcode's own selector |
| (b) does 1.5.1 wrap the payload as `abi.encode(bytes)`? | **MEASURED** | `PITFALLS.md:103` — returndata is `abi.encode(<coerced value>)`, **not** `abi.encode(<bytes>)` |
| (c) is `vm.rpcJson` absent? | **MEASURED** | `PITFALLS.md:134-137`, Pitfall 4 `[MEASURED]` |
| (d) does alloy enforce a response `Content-Type`? | **OPEN** | `ARCHITECTURE.md:612` — "Not verified… **LOW confidence** that it is optional" |

**The reframing:** every one of those measurements was taken against a stub oracle in
`/tmp/orctest` (`PITFALLS.md:7`) — never against Haskell, never against `warp`. So Phase 2 is not
"discover how `vm.rpc` behaves". It is **"confirm `warp` can be the thing on the other end."**

What the spike therefore runs:

1. **One green `forge test`** against the warp stub — the genuinely new thing.
2. **Content-Type matrix**: identical bodies served three ways — `application/json`, `text/plain`,
   and **no Content-Type at all**. A table rather than one observation, so a future Foundry bump is
   compared against data. Content-Type is *binary plumbing*: it cannot corrupt a value, it can only
   let the call through or kill it.
3. **Hex-envelope round-trip, byte-exact.** Confirms the load-bearing claim (`PITFALLS.md:82`) that
   a `0x`-prefixed even-length hex string is the one JSON shape whose coercion is total and
   value-independent. Everything from Phase 3 on assumes it; it has never been tested against warp.
4. **(b) re-confirmed as a byproduct** — the test decodes the return value anyway.

Explicitly NOT run: re-derivation of (a) or (c).

### The SRV-01 proxy trap — deferred, not dismissed

`ARCHITECTURE.md:101`: alloy's `guess_local_url` treats a URL as local **only** when the host is
exactly `localhost`, `127.0.0.1` or `::1`, and only those get `no_proxy`. A container hostname or
`0.0.0.0` would honour `HTTP_PROXY` and **route a loopback oracle call off-box**.

This is marked **[S]** in REQUIREMENTS — *source-derived, never measured*. That is precisely the
provenance that produced the `vm.rpcJson` error. **Decision: address as `127.0.0.1` so the spike is
never affected; leave verification to Phase 6 where SRV-01 lands.** Recorded here so Phase 6 cannot
plan around it silently.

### Claude's Discretion

- Where the spike's files live and how deletion is guaranteed (`spike/` directory vs elsewhere) —
  the user did not select this area; choose whatever makes the discard mechanism most literal.
- The forge project skeleton for the spike (throwaway vs permanent), `forge-std` acquisition.
- Warp handler structure, port selection for local runs, and the shape of the `just` recipe.
- PROBE-NOTES section layout, following the 01-01-PROBE-NOTES pattern.

</decisions>

<specifics>
## Specific Ideas

- **Anvil is not in the path.** `forge test` runs `revm` in-process; `vm.rpc` is a cheatcode whose
  Rust handler builds an alloy HTTP client *inside the forge process*. Forge is the client, our
  warp process is the server, and no node, chain or anvil is involved
  (`ARCHITECTURE.md:28` — the 3-arg form is `apply`, stateless, needs no fork and no
  `[rpc_endpoints]` entry). Any design that assumes an intermediary node is wrong.
- **The four layers, and which one is the enemy.** ① HTTP `Content-Type` is a *label*, carrying no
  structure. ② JSON `Value`. ③ **Foundry's `json_value_to_token` coercion — this is the lossy,
  value-dependent step**: the same Haskell record yields different Solidity types for different
  values (`PITFALLS.md:66`, `:76`), and `null` becomes 32 zero bytes with `success == true`
  (`:164`). ④ our own `abi.decode`. The hex-envelope decision exists to reduce ② and ③ to a **dumb
  lossless pipe** between our encoder and our decoder: "the bridge — not foundry's heuristics —
  owns the encoding" (`PITFALLS.md:82`).
- **A pin you can read vs a pin that can fail.** DIST-06's operative word is *enforceable*. The
  consumer's `forge --version | grep -qF "$FOUNDRY_COMMIT" || exit 1` is a proposition that goes
  red — the same shape as our seam guard. A value sitting in `foundry.toml` is only a value.
- **Pin the commit, not the tag** — "a tag can in principle be re-cut, and '1.5.1' alone would not
  notice" (consumer's `.github/foundry-version`). The same discipline was applied this session to
  literature pointers for `cfmm-refs`: commit-pinned URLs, never `/blob/master/`.
- Phase 1's rule carries: **exit code before greps**, and *a check whose scope you cannot widen
  beats a check you trust yourself to interpret narrowly*.

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project governance
- `.planning/PROJECT.md` — Constraints and Key Decisions. **Note two entries this phase amends:**
  "the envelope is hand-rolled" (superseded by the `json-rpc` adoption above) and the "Resolved
  since initialization" block recording the measured `try`/`catch` and `vm.rpc`-forwarding results
- `.planning/REQUIREMENTS.md` — DIST-06 is this phase's only requirement; `[M]`/`[S]` markers
  distinguish measured from source-derived and must not be relaxed without re-measuring
- `.planning/ROADMAP.md` — Phase 2 success criteria (**amended alongside this document**) and the
  "Governing Decisions Applied" section
- `.planning/phases/01-repo-skeleton-component-seams-ci-floor/01-CONTEXT.md` — the execution model
  this document supersedes, and the container-as-artifact decision
- `.planning/phases/01-repo-skeleton-component-seams-ci-floor/01-SUMMARY.md` — Phase 1 outcomes,
  measured build costs, and the nine instrument failures with the rules that came out of them

### Transport behaviour — read before writing any Solidity or handler
- `.planning/research/PITFALLS.md` §7 (method note: `[MEASURED]` vs `[SOURCE]`), Pitfall 1 (three
  outcomes on one channel), **Pitfall 2 §55-82 (value-dependent coercion and the hex-envelope
  rule)**, **Pitfall 3 §100-115 (the 1.5.1 return-path shape)**, Pitfall 4 §134-157 (`rpcJson`
  absent), Pitfall 5 §161-164 (`null` → 32 zero bytes), Pitfall 6 §186 (45 s hang that passes)
- `.planning/research/ARCHITECTURE.md` §28 (stateless 3-arg form, no anvil), **§101 and §405
  (`guess_local_url` and the `HTTP_PROXY` trap)**, §103 (per-call provider, no pooling),
  **§612 (Content-Type unverified, LOW confidence)**
- `.planning/research/SUMMARY.md` §94, §103 (the `master` vs `1.5.1` return-path disagreement),
  §190-191 (this phase's originally-scoped deliverable and its four questions)

### The library
- https://hackage.haskell.org/package/json-rpc-1.1.2 — `Network.JSONRPC.Data` export list is the
  envelope surface we adopt; `Network.JSONRPC.Interface` is the transport we reject
- https://www.stackage.org/lts-24.55/package/json-rpc-1.1.2 — snapshot membership, the reason no
  `extra-deps` entry is needed

### External (upstream, read-only)
- `/home/jmsbpp/cfmms-playground/cfmm-wt/vol-markets/.github/foundry-version` — **the pin we must
  match and the idiom we mirror**; their requirement CI-05, commit `dddb26b`
- `/home/jmsbpp/cfmms-playground/cfmm-wt/vol-markets/.github/workflows/push-build.yml` §74-125 —
  the install-and-assert step; §80-86 explains the persistent-runner plumbing we deliberately omit
- `/home/jmsbpp/cfmms-playground/cfmm-wt/vol-markets/notes/TOOLCHAIN_PINS.md` — upstream's record of
  why this version and what breaks if it moves
- `/home/jmsbpp/.claude/CLAUDE.md` — the fork → PR rule. **Its two-step reviewer mandate is
  explicitly overridden for this project by user decision (see Execution model above).**

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `components/transport/` — exists with a trivial `app/Main.hs` and builds green; the natural
  place for a warp server later, though the *spike* stub should not settle there by inertia.
- `justfile` (01-05) — established recipe pattern; the spike's runner recipe extends it.
- `scripts/seam-guard.sh`, `scripts/seam-negative-test.sh`, `scripts/hpack-drift.sh` — the
  established shape for a guard: a script that exits non-zero, invoked identically from `just` and
  from CI (`ci.yml:57`, `:59`, `:106`). The Foundry pin assertion should follow this shape.
- `.github/workflows/ci.yml` — three jobs: `seam` (125 s), `build` (440 s), `image`
  (`needs: [seam, build]`, pushes only on push events). The pin assertion lands here; the spike
  test does not.
- `components/protocol/test/Main.hs` — the `tasty` scaffold, already running in the gate.

### Established Patterns
- **Stack + hpack**, snapshot pinned by URL to LTS 24.55; committed `.cabal` with a drift gate.
  Adding `json-rpc`, `wai`, `warp` means editing `package.yaml` and regenerating — the drift gate
  will catch a forgotten regeneration.
- **The seam is enforced by resolution**: `stack-core.yaml` omits the spec extra-dep, so a core
  component gaining a spec dependency fails to resolve. Any new dependency must be added to the
  right component or the seam job goes red.
- **Measurements land in PROBE-NOTES** with their conditions stated, following
  `01-01-PROBE-NOTES.md`. A number without its conditions is how the 0.34 s seam figure misled.

### Integration Points
- The spike's warp stub is the first code in this repo that Foundry talks to, and the first HTTP
  surface. Nothing else depends on it — by design, since it is discarded.
- `.github/foundry-version` is new and **permanent**, consumed by CI, the spike runner, and
  (Phase 8) the Solidity header generator.

</code_context>

<deferred>
## Deferred Ideas

- **Detecting when the consumer moves their Foundry pin** — an integration concern; belongs to
  Phase 10, not the spike.
- **Verifying the `guess_local_url` / `HTTP_PROXY` trap by observation** rather than by reading
  alloy source — Phase 6, where SRV-01 lands. Flagged as a `[S]`-provenance item, the same class
  that produced the `vm.rpcJson` error.
- **Propagating the container decision into ROADMAP Phases 6 and 10** and the affected requirements
  — carried forward unresolved from `01-CONTEXT.md`. Must happen before Phase 6 is planned or those
  phases will be planned against a stale model.
- **Amending PROJECT.md's Key Decisions** for the `json-rpc` adoption — needed, but a PROJECT-level
  edit rather than a Phase 2 deliverable.
- **Phase 3 boundary-value inputs, contributed by `gams-evm-transport` (2026-08-28).** Their
  published artifact carries `uint160`/`uint128` as decimal STRINGS. `PITFALLS.md:63` already
  measures that branch — a numeric string **under** u64 stays Solidity `string`, at or **above**
  u64 becomes `uint256`/`int256` — so quoting does not escape the coercion, it only relocates the
  same 2^64 boundary. Phase 3 criterion 2 should therefore measure **three encodings of the same
  value** — `0x` hex blob, decimal string, raw number — across the boundary classes, not just the
  hex path. Their open ask, still genuinely [UNVERIFIED] here: **arrays and signed values**.
  Report results back to them.
- **Removing `libcairo2-dev` from `ci.yml`** if upstream's two-package restructure merges.
- **Opening the fork → upstream promotion PR** for Phase 1's work; branch protection now requires
  `seam`, `build`, `image`.
- **Wider audit of ROADMAP success criteria for the criterion-3 defect** (criteria naming a
  mechanism that cannot do the job) — the user chose the narrow amendment; the sweep is available
  later.

</deferred>

---

*Phase: 02-transport-spike-throwaway*
*Context gathered: 2026-08-28*
