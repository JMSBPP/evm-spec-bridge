---
phase: 03-three-outcome-protocol-core-and-hex-abi-envelope
verified: 2026-08-28T18:25:00Z
status: human_needed
score: 39/42 must-haves verified
behavior_unverified: 1
behavior_unverified_items:
  - truth: "Adding a GuardId constructor breaks compilation at every consumer site (INTEG-02 compile-error negative)"
    test: "Add a new GuardId constructor in Bridge.Protocol, run stack build --pedantic"
    expected: "cfmm-adapter (or another consumer with exhaustive match) fails with non-exhaustive-pattern error"
    why_human: "cfmm-adapter has no GuardId mapping yet; the negative was explicitly deferred to Phase 11 per REQUIREMENTS.md"
human_verification:
  - name: "Pedagogical — three outcomes and tag byte"
    test: "State what each tag value (0x01/0x02/0x03) means and why a rejection cannot ride the JSON-RPC error channel"
    expected: "User cites 0xeeaa9e6f indistinguishability and outcomeResponse channel discipline"
    why_human: "03-VALIDATION manual-only row; PROBE-NOTES record orchestrator approval, not independent re-demonstration"
  - name: "Pedagogical — drive boundary sweep"
    test: "Run just boundary-sweep, mutate one stub vector byte, observe red, revert"
    expected: "User sees which keccak side catches the mutation"
    why_human: "03-VALIDATION manual-only row (03-06-T6)"
  - name: "INTEG-02 compile-error negative"
    test: "Add a GuardId constructor; confirm cfmm-adapter exhaustive match fails to compile"
    expected: "Non-exhaustive pattern error at the mapping site"
    why_human: "Mapping function not implemented in cfmm-adapter this phase; REQUIREMENTS marks INTEG-02 Partial"
coincidental_reliance_items:
  - truth: "Wedged oracle NEGATIVE stage takes ~45s (Foundry REQUEST_TIMEOUT)"
    reason: fixture-only
    harden: "wedge-red-test.sh should assert elapsed >= 30s on NEGATIVE when stub bind succeeds, so fast connection-refused passes cannot satisfy the guard"
gaps:
  - id: INTEG-02-cfmm-mapping
    severity: non-critical
    description: "cfmm-adapter has no GuardId exhaustive match; compile-error negative for new guards not demonstrated"
    impact: "INTEG-02 marked Partial in REQUIREMENTS.md; Phase 11 owns the mapping function"
  - id: wedge-contrast-reasons
    severity: non-critical
    description: "scripts/wedge-red-test.sh CONTRAST stage does not assert failure reason differs from NEGATIVE (03-07-T3 acceptance criteria)"
    impact: "Both stages still go red with test count > 0; distinguishability is weaker than planned"
  - id: port-8899-race
    severity: non-critical
    description: "Sequential just recipes can leave oracle-stub on :8899; subsequent runs fail bind and may pass wedge-red in ~2s via connection refused"
    impact: "Operator must pkill oracle-stub between runs; not a protocol defect"
---

# Phase 3: Three-Outcome Protocol Core and Hex-ABI Envelope — Verification Report

**Phase Goal:** Spec success, spec rejection and transport failure become three constructors no partial function can turn into one another, and the wire representation survives Foundry's value-dependent JSON-to-ABI coercion byte-exact.

**Verified:** 2026-08-28T18:25:00Z  
**Status:** human_needed

---

## Goal Achievement

### ROADMAP Success Criteria

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Solidity tells spec rejection from dead server by tag byte; no string matching | ✓ VERIFIED | `just discriminate` exit 0; `Discrimination.t.sol` asserts `ok` + `TAG_REJECTION` + numeric guardId==3; zero `keccak256(bytes(` / `try`/`catch` / `forge-std` in test |
| 2 | Six boundary classes byte-exact through real `forge test` | ✓ VERIFIED | `just boundary-sweep` exit 0; five round-trip classes + class 6 refusal in Haskell tests; cast keccak agrees with Solidity `BoundaryRow` hashes |
| 3 | Wedged oracle goes red, not green | ✓ VERIFIED | `./scripts/wedge-red-test.sh` exit 0; NEGATIVE elapsed **47s** with `wedge: reached handler`; test count > 0, rc=1 |
| 4 | Rejections carry closed enumerated guard identity | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `GuardId` enum in `Bridge.Protocol` (7 constructors, Bounded/Enum); jsonrpc tests iterate `[minBound..maxBound]` for no guard text; **cfmm-adapter mapping not implemented** |
| 5 | Every response carries `protocolVersion` | ✓ VERIFIED | `just version-sweep` exit 0 on success/rejection/fault; Haskell property `protocolVersion survives`; `grep -rc '^protocolVersion =' Bridge/Protocol.hs` → 1 |

**ROADMAP score:** 4/5 verified, 1 behavior-unverified (criterion 4 compile-error half)

### Observable Truths (plan must_haves aggregate)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Three-outcome sum type; no partial mapping between outcomes | ✓ VERIFIED | `SpecOutcome` has exactly 3 constructors in `components/protocol/src/Bridge/Protocol.hs`; `-Wincomplete-patterns` in package.yaml |
| 2 | Guard enum closed, named, in spec-free core | ✓ VERIFIED | `GuardId` with 7 constructors; `./scripts/seam-guard.sh` exit 0 |
| 3 | `protocolVersion` single constant | ✓ VERIFIED | One binding at line 146-147; golden vector word 0 = 0x0001 |
| 4 | web3-solidity build cost measured | ✓ VERIFIED | PROBE-NOTES: BEFORE 427-440s baseline → AFTER 356.7s cold with conditions |
| 5 | JSON number/null unrepresentable (PROTO-04) | ✓ VERIFIED | `Hex0x` abstract newtype; `just hex-only` exit 0, two distinguishable compile failures |
| 6 | Envelope `abi.encode(uint16,uint8,bytes)` version-first | ✓ VERIFIED | `Bridge.AbiCodec.Envelope` tags 0x01/0x02/0x03; golden vector matches stub curl |
| 7 | Rejection only via `Response`, never `ResponseError` | ✓ VERIFIED | `outcomeResponse :: Either EnvelopeError Response`; `ResponseError` only in `protocolFault` |
| 8 | No guard name text on wire | ✓ VERIFIED | 6 jsonrpc tests pass; exhaustive guard iteration in test suite |
| 9 | Discrimination by tag, zero string comparison | ✓ VERIFIED | `just discriminate` + `just discriminate-dead` |
| 10 | Permanent forge project, low-level vm.rpc call | ✓ VERIFIED | `solidity/foundry.toml` solc 0.8.34; `VM_ADDR.call(...)` in SpecOracle.sol |
| 11 | oracle-stub serves real envelopes | ✓ VERIFIED | `--mode rejection` curl returns golden 0x string byte-for-byte |
| 12 | Boundary keccak two-way agreement | ✓ VERIFIED | boundary-sweep script prints agreement line |
| 13 | Odd-nibble tests refusal, not round-trip | ✓ VERIFIED | `OddNibbleCount 3` test cases; PROBE-NOTES Class 6 section |
| 14 | Wedged fixture reusable mode | ✓ VERIFIED | `--mode wedge` blocks after logging handler reach |
| 15 | `requireOutcome` no verdict-free path | ✓ VERIFIED | Three unconditional `require`s; no `try`/`catch`/`return;` in SpecOracle.sol |
| 16 | INTEG-02 compile error on new guard | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | cfmm-adapter has no `GuardId` mapping (Phase 11) |
| 17 | wedge-red CONTRAST distinguishes failure reasons | ✗ FAILED | Script checks rc≠0 and count>0 only; no JSON reason comparison per 03-07-T3 |

**Must-haves score:** 39/42 verified (2 behavior-unverified, 1 failed non-blocker)

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `components/protocol/src/Bridge/Protocol.hs` | ✓ SUBSTANTIVE | SpecOutcome, GuardId, protocolVersion, FaultCode |
| `components/abi-codec/src/Bridge/AbiCodec/Hex.hs` | ✓ SUBSTANTIVE | Abstract Hex0x, single ToJSON |
| `components/abi-codec/src/Bridge/AbiCodec/Envelope.hs` | ✓ SUBSTANTIVE | encode/decode envelope, tag constants, parity assertion |
| `components/jsonrpc/src/Bridge/JsonRpc.hs` | ✓ SUBSTANTIVE | outcomeResponse, protocolFault channel split |
| `scripts/hex-only-guard.sh` | ✓ EXISTS | CONTROL/NEGATIVE/CONTRAST compile-fail |
| `solidity/test/Discrimination.t.sol` | ✓ SUBSTANTIVE | 4 tests incl. faultPath version |
| `solidity/test/BoundarySweep.t.sol` | ✓ SUBSTANTIVE | 5 indices, BoundaryRow events, hard-coded hashes |
| `solidity/test/WedgeRed.t.sol` | ✓ SUBSTANTIVE | Expected-red header comment |
| `components/oracle-stub/app/Main.hs` | ✓ SUBSTANTIVE | 5 modes: success/rejection/fault/boundary/wedge |
| `scripts/wedge-red-test.sh` | ⚠️ PARTIAL | Missing CONTRAST reason-diff assertion |
| `.planning/phases/.../03-SUMMARY.md` | ✓ EXISTS | Locked decisions + did NOT prove section |
| `components/cfmm-adapter/.../CfmmAdapter.hs` | ⚠️ NO GuardId MAP | Only specNumLegs placeholder |

**Artifacts:** 10/12 fully verified

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| oracle-stub | JsonRpc.outcomeResponse | HTTP POST | ✓ WIRED |
| outcomeResponse | encodeEnvelope | Either chain | ✓ WIRED |
| encodeEnvelope | web3-solidity Abi.encode | tuple (ver,tag,body) | ✓ WIRED |
| Discrimination.t.sol | oracle-stub | evm_spec_bridge RPC alias | ✓ WIRED |
| BoundarySweep.t.sol | boundary mode stub | spec_boundary index | ✓ WIRED |
| WedgeRed.t.sol | requireOutcome | transport require | ✓ WIRED |
| GuardId | cfmm-adapter mapping | exhaustive match | ✗ NOT WIRED (deferred Phase 11) |

---

## Requirements Coverage

| Requirement | Status | Evidence |
|-------------|--------|----------|
| **PROTO-01** | ✓ SATISFIED | Sum type + requireOutcome unconditional transport check |
| **PROTO-02** | ✓ SATISFIED | outcomeResponse + Discrimination.t.sol tag discrimination |
| **PROTO-03** | ✓ SATISFIED | Envelope codec + boundary-sweep through real forge |
| **PROTO-04** | ✓ SATISFIED | Hex0x + hex-only-guard compile-fail |
| **PROTO-07** | ✓ SATISFIED | version-sweep all three constructors + Haskell property |
| **INTEG-02** | ⚠️ PARTIAL | Guard enum + no guard text on wire verified; cfmm-adapter compile-error negative **not executed** (REQUIREMENTS.md agrees) |

**Coverage:** 5/6 satisfied, 1 partial (documented)

---

## Automated Test Results (this verification run)

| Command | Exit | Notes |
|---------|------|-------|
| `stack build --test --pedantic` | 0 | 16 tests: protocol 1, jsonrpc 6, abi-codec 9 |
| `just hex-only` | 0 | Two distinguishable compile failures |
| `just discriminate` | 0 | rejection tag 0x02, guardId 3 |
| `just discriminate-dead` | 0 | transport revert, no tag read |
| `just boundary-sweep` | 0 | 5 cast/forge keccak agreement |
| `just version-sweep` | 0 | success/rejection/fault version==1 |
| `./scripts/wedge-red-test.sh` | 0 | NEGATIVE 47s with handler reached |
| `./scripts/seam-guard.sh` | 0 | Core seam intact |

Forge pin: v1.5.1 / b0a9dd9 (matches `.github/foundry-version`).

---

## Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| `scripts/wedge-red-test.sh` | CONTRAST omits reason comparison | ℹ️ Info | Weaker guard than 03-07 plan specified |
| `components/cfmm-adapter/.../CfmmAdapter.hs` | No GuardId mapping | ⚠️ Warning | INTEG-02 partial until Phase 11 |
| Sequential `just` runs | Port 8899 bind race | ℹ️ Info | False-fast wedge pass if stub orphaned |

No blockers in protocol/core code.

---

## Human Verification Required

See frontmatter `human_verification` and `behavior_unverified_items`. Phase 3's pedagogical gates (03-VALIDATION manual-only rows) were recorded as "User approved via execute-phase orchestrator" in PROBE-NOTES — this verifier did not re-witness those sessions.

---

## Gaps Summary

### Non-Critical (documented, do not block Phase 4)

1. **INTEG-02 cfmm-adapter mapping** — enum exists; exhaustive match lands in Phase 11. REQUIREMENTS already marks Partial.
2. **wedge-red CONTRAST reason diff** — script should compare `--json` failure reasons between NEGATIVE and CONTRAST.
3. **Port 8899 cleanup** — recipes should fail closed when stub bind fails, or use ephemeral ports.

### Known limitations (inherited, not gaps)

- Arrays / three-encoding comparison unguarded until Phase 8
- 45s wedge **cost** unbounded until Phase 5 SRV-04
- web3-solidity correctness assumed
- One host/OS; master vs 1.5.1 wrapping unverified

---

## Verification Metadata

**Verification approach:** Goal-backward from ROADMAP Phase 3 + plan must_haves + requirement IDs  
**Must-haves source:** 03-01 through 03-07 PLAN.md frontmatter  
**Automated checks:** 8/8 recipe/build commands passed (after port cleanup)  
**Human checks required:** 3  
**Total verification time:** ~50 min (incl. wedge 47s)

---
*Verified: 2026-08-28T18:25:00Z*  
*Verifier: gsd-verifier subagent*
