---
phase: 03-three-outcome-protocol-core-and-hex-abi-envelope
plan: 02
subsystem: protocol
tags: [haskell, aeson, hex, compile-fail, PROTO-04, type-safety]

requires:
  - phase: 03-01
    provides: SpecOutcome sum type and guard enum in protocol component
provides:
  - Abstract Hex0x newtype with sole ToJSON instance in abi-codec
  - compile-fail guard proving JSON number and raw construction are unrepresentable
affects: [03-03, 03-04, 03-05]

tech-stack:
  added: [aeson, bytestring, text, base16-bytestring]
  patterns: [abstract newtype with unexported constructor, CONTROL/NEGATIVE/CONTRAST compile-fail guard]

key-files:
  created:
    - components/abi-codec/src/Bridge/AbiCodec/Hex.hs
    - scripts/hex-only-guard.sh
    - components/abi-codec/compile-fail/Control.hs
    - components/abi-codec/compile-fail/RawConstructor.hs
    - components/abi-codec/compile-fail/NumberBody.hs
  modified:
    - components/abi-codec/package.yaml
    - components/abi-codec/src/Bridge/AbiCodec.hs
    - justfile

key-decisions:
  - "Hex wire rendering lives in abi-codec not protocol — protocol must stay aeson-free per 03-01-T3"
  - "GHC 9.10 diagnostic for unexported constructor differs from plan text — guard updated to match actual output"
  - "PITFALLS.md:171 null-property test deliberately superseded by structural guarantee"

patterns-established:
  - "Pattern: compile-fail guard with CONTROL/NEGATIVE/CONTRAST stages for type-level claims"

requirements-completed: [PROTO-04]

coverage:
  - id: D1
    description: "Hex0x abstract newtype — sole ToJSON in repo renders 0x-prefixed hex"
    requirement: PROTO-04
    verification:
      - kind: unit
        ref: "grep -rn 'instance.*ToJSON' components/ | wc -l == 1"
        status: pass
      - kind: other
        ref: "./scripts/hex-only-guard.sh"
        status: pass
    human_judgment: false
  - id: D2
    description: "User witnessed compile-fail guard firing in two distinguishable ways"
    verification: []
    human_judgment: true
    rationale: "Pedagogical gate 03-02-T3 — compile-fail evidence requires human confirmation"

duration: 15min
completed: 2026-08-28
status: complete
---

# Phase 03 Plan 02 Summary

**Abstract Hex0x newtype makes JSON numbers and null structurally unrepresentable — one ToJSON in the repo, compile-fail guard proves it**

## Performance

- **Duration:** ~15 min
- **Tasks:** 4
- **Files modified:** 9

## Accomplishments

- `Bridge.AbiCodec.Hex` — abstract newtype with unexported constructor, smart constructors only
- Sole `ToJSON` instance in the entire repo (exactly 1 match)
- `scripts/hex-only-guard.sh` — CONTROL/NEGATIVE/CONTRAST compile-fail check
- PROTO-04 evidence recorded in 03-01-PROBE-NOTES; vacuous null-property test explicitly not written

## Task Commits

1. **Task 1: Hex0x newtype** - `38336e2` (feat)
2. **Task 2: hex-only-guard.sh** - `0c0ff4b` (test)
3. **Task 3: Human checkpoint** - approved by user
4. **Task 4: PROBE-NOTES evidence** - (this commit)

## Deviations from Plan

### Auto-fixed Issues

**1. GHC 9.10 diagnostic wording**
- **Issue:** Plan expected `not in scope: Hex0x`; GHC 9.10 emits `Illegal term-level use of the type constructor`
- **Fix:** Updated guard script to match actual diagnostic; recorded verbatim in PROBE-NOTES

**2. Unquoted package name in bash**
- **Issue:** `evm-spec-bridge-abi-codec` parsed as arithmetic subtraction
- **Fix:** Quoted package name in `stack build` invocation

## Next Phase Readiness

- Hex0x ready for envelope encoding in 03-03
- `hexOfBytes` / `hexText` available for ABI layer

---
*Phase: 03-three-outcome-protocol-core-and-hex-abi-envelope*
*Completed: 2026-08-28*
