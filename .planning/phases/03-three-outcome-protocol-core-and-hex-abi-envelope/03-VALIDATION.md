---
phase: 3
slug: three-outcome-protocol-core-and-hex-abi-envelope
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-28
---

# Phase 3 — Validation Strategy

**Phase requirements:** PROTO-01, PROTO-02, PROTO-03, PROTO-04, PROTO-07, INTEG-02

**Note on this phase's character.** Phases 1 and 2 were validated by *measurement* — does it build,
does the guard fire, what bytes come back. Phase 3 is validated by **impossibility**: the claim is
not "the encoder does the right thing" but "the encoder **cannot** do the wrong thing".

That inverts the test design. A passing test proves a property holds *today*. A type that makes the
illegal state unrepresentable proves it holds for every program that compiles. Where we can reach
the second, we must — and where we reach it, the corresponding property test becomes **vacuous**,
which this project treats as an artifact to remove rather than reassurance to keep.

Written inline by the user's mandate — no researcher agent.

---

## The rules this phase is validated against

Carried from Phases 1-2, all earned:

1. **Exit code before greps** — including when the grep is a pager (`head` swallowed an exit code
   in 02-04).
2. **Every number carries its conditions.**
3. **A guard nobody has seen fire is being trusted, not verified** — and it must fail in **two
   distinguishable ways**, or "it fired" is indistinguishable from "it fires at anything".
4. **A criterion phrased against a tool needs evidence the tool exists.**
5. **A measurement is scoped to its CODE PATH as much as to its version** — `vm.rpc` and
   `vm.parseJson` disagree on identical JSON because `convert_to_bytes` runs on the rpc path only.
6. **A criterion must test a PROPERTY, not source text.** This has now failed four times and is
   the most reliable defect in our own criteria:
   - Phase 2: `grep -c 'via_ir\|optimizer'` tripped by a comment explaining what we deliberately
     do NOT set — cleared by rewording the comment, not by changing configuration.
   - Phase 2: the "no typed `= vm.rpc(`" grep, same shape.
   - Phase 3: `grep -c '^protocolVersion'` required to be 1 — **impossible**, because the type
     signature and the equation both begin at column 0, and deleting the signature fails
     `-Wmissing-signatures` under `--pedantic`. The criterion contradicted the project's own flags.
   - Phase 3: `grep -cE 'Data\.Aeson|Data\.Solidity'` required to be 0 — tripped by a haddock
     comment *stating that the module imports neither*. The property was true; the text was not.

   **Rule:** prefer a compile result, a type signature check, effective config (`forge config
   --json`, `stack ls dependencies`), or an assertion on EMITTED output. When a `grep` is genuinely
   the right instrument, anchor it to syntax that cannot appear in prose — `'^name ='`, not
   `'^name'`; and never write a criterion whose only failure mode is someone mentioning the thing.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Haskell** | `tasty` in `components/protocol/test/Main.hs` (exists, runs in the gate) |
| **Solidity** | `forge test`, **pinned v1.5.1 / `b0a9dd9`** — asserted by `./scripts/foundry-pin.sh` before ANY measurement |
| **ABI** | `web3-solidity-1.1.0.0` (`Data.Solidity.Abi.Codec`), snapshot-resident, no native deps |
| **Entry points** | `just` recipes; the spike recipes were removed in 02-05 and need re-creating |
| **Runtime** | Haskell suite: UNMEASURED. `forge test`: ~350-620 ms wall in Phase 2 for 2 tests. Build cost of adding `web3-solidity`: **UNMEASURED — a deliverable of 03-01, not an estimate** |

---

## Sampling Rate

- **Before any Solidity measurement:** `./scripts/foundry-pin.sh` exits 0.
- **After every task commit:** `stack build --test` exits 0 and `./scripts/hpack-drift.sh` exits 0
  (the drift gate globs `*.cabal` repo-wide; a new dependency regenerates a `.cabal`).
- **After every plan:** `./scripts/seam-guard.sh` exits 0 — no core component may gain a spec edge.
- **Max feedback latency:** Haskell suite target under a minute warm; measured, not assumed.

---

## Per-Task Verification Map

| Task | Req | Test type | Automated check | Status |
|---|---|---|---|---|
| Result is a sum type; no partial function maps one outcome to another | PROTO-01 | structural | Type has 3 constructors; **no `fromJust`/`head`/incomplete case** in the outcome path — `-Wincomplete-patterns` clean | ⬜ |
| **A JSON number or `null` is UNREPRESENTABLE in a result** | PROTO-04 | **type-level** | The result's `ToJSON` can only emit a `0x` string, evidenced by the type. See "compile-fail" below | ⬜ |
| Guard enum is closed and named | INTEG-02 | structural | Enum in `protocol`; `protocol` has NO spec dependency (`seam-guard.sh` exit 0) | ⬜ |
| **Adding a guard breaks the build** | INTEG-02 | **negative** | Add a constructor to the spec-facing side → `cfmm-adapter` mapping fails to compile with a non-exhaustive-pattern error | ⬜ |
| No free-text guard string on the wire | INTEG-02 | structural | Serialised rejection contains no guard name as text — assert on the emitted JSON, not on source | ⬜ |
| Envelope is `abi.encode(uint16, uint8, bytes)` | PROTO-03 | behavioural | Haskell-encoded bytes decode in Solidity to the same three values | ⬜ |
| `protocolVersion` present on every response | PROTO-07 | property | Over generated outcomes: decoded version == the constant, for all three constructors | ⬜ |
| **Six boundary classes round-trip byte-exact through REAL forge** | PROTO-03 | behavioural | zero, >2^64, negative, empty, 32-byte, odd-nibble — `keccak256` equality both sides | ⬜ |
| Rejection travels in `result`, never `error` | PROTO-02 | structural | A rejection can only be built as `Response`, never `ResponseError` — by constructor, not convention | ⬜ |
| **Solidity tells rejection from dead server by tag byte** | PROTO-02 | behavioural | Test asserts on the tag; **zero string comparison** anywhere in the path | ⬜ |
| **Wedged oracle goes RED** | — | **negative** | Never-answer fixture → `forge test` exits NON-zero, test count > 0 | ⬜ |
| Transport failure fails unconditionally | INTEG-05 | structural | No `try`/`catch` that continues; call site has no path returning without a verdict | ⬜ |
| `web3-solidity` build cost | — | **measurement** | Cold build time before vs after the dependency, recorded with conditions | ⬜ |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `web3-solidity` added to the right component's `package.yaml`, `.cabal` regenerated AND
      committed (drift gate is repo-wide)
- [ ] `./scripts/seam-guard.sh` still exits 0 — the new dependency must not be mistaken for, or
      enable, a spec edge
- [ ] A forge project exists again (`spike/` was deleted in 02-05) and `./scripts/foundry-pin.sh`
      passes before any Solidity measurement

---

## How the type-level claim is evidenced

PROTO-04's guarantee is that a JSON number or `null` cannot be emitted. A test asserting this is
vacuous once the type holds. Two acceptable forms of evidence, in preference order:

1. **A compile-fail check** — a source snippet that attempts to emit a JSON number for a domain
   value and is asserted NOT to compile. This is the type-level analogue of the negative test, and
   it is the only form that proves the guarantee rather than restating it.
2. **The type definition itself**, cited by file:line in the summary, with an argument for why no
   other `ToJSON` path exists.

If (1) is impractical, (2) plus a note that the guarantee is unenforced against future edits.

---

## Manual-Only Verifications

| Behavior | Why manual | Instructions |
|---|---|---|
| The user can explain the three outcomes and why the tag byte exists | Pedagogical mandate: an artifact the user cannot explain has half-failed | User states what each tag value means and why a rejection cannot ride the `error` channel |
| The user can re-run the boundary sweep and change a value | The recipe is the deliverable | User runs it, alters a boundary value, observes the result change |

---

## Known Validation Gaps

- **Arrays and the three-encoding comparison are OUT of this phase** (deferred to Phase 8's
  conformance fixture). On our untyped path a wrong-branch array decode **cannot revert** — the one
  class where silence is the failure mode. It stays unguarded until Phase 8.
- **The `master`-vs-`1.5.1` wrapping difference remains unverified.** All Solidity work here is
  scoped to `1.5.1`/`b0a9dd9`.
- **One host, one OS.** Nothing here proves behaviour on the consumer's runner.
- **`guess_local_url` / `HTTP_PROXY` is still `[S]`**, never observed — Phase 6, SRV-01.
- **The wedge fixture proves the CALL SITE goes red. It does not bound the COST** — that is
  Phase 5's SRV-04 server-side deadline. A wedged oracle still costs 45 s after this phase.
- **`web3-solidity` is a third-party encoder between our types and the wire.** Its correctness is
  assumed, not verified here. If a boundary class fails, the encoder is a suspect alongside our own
  code — record which was at fault rather than assuming ours.

---
*Validation strategy created: 2026-08-28*
