---
phase: 03-three-outcome-protocol-core-and-hex-abi-envelope
plan: 03
subsystem: abi-codec
tags: [haskell, abi, envelope, PROTO-03, golden-vector]

requires:
  - phase: 03-02
    provides: Hex0x newtype and hex rendering
provides:
  - encodeEnvelope / decodeEnvelope over SpecOutcome ByteString
  - Tag constants 0x01/0x02/0x03 with 0x00 reserved
  - Golden vector for GuardStrikeOutOfRange (fromEnum 3)
  - Tasty round-trip, parity, version, tag-0x00, golden tests
affects: [03-05, 03-06]

tech-stack:
  added: [web3-solidity, memory]
  patterns: [version-first tuple encode, asserted even-nibble parity]

key-files:
  created:
    - components/abi-codec/src/Bridge/AbiCodec/Envelope.hs
    - components/abi-codec/test/Main.hs
  modified:
    - components/abi-codec/package.yaml
    - components/abi-codec/evm-spec-bridge-abi-codec.cabal
    - components/abi-codec/src/Bridge/AbiCodec.hs
    - .planning/phases/03-three-outcome-protocol-core-and-hex-abi-envelope/03-01-PROBE-NOTES.md

key-decisions:
  - "Tags 0x01 success, 0x02 rejection, 0x03 fault; 0x00 reserved (PITFALLS.md:164)"
  - "Layout abi.encode(uint16 version, uint8 tag, bytes body) — version FIRST"
  - "Odd-nibble assertion returns Left OddNibbleEmitted — web3-solidity named suspect if it fires"

requirements-completed: [PROTO-03]

duration: 45min
completed: 2026-08-28
status: complete
---

# Phase 03 Plan 03 Summary

**Hex-ABI envelope encodes three outcomes as version-first, tag-second even-nibble hex; golden vector pinned for Solidity comparison**

## Accomplishments

- `Bridge.AbiCodec.Envelope` — encode/decode with named `EnvelopeError` variants
- Five tasty tests: round-trip, even-nibble, protocolVersion, tag 0x00 rejection, golden vector
- Golden vector recorded in 03-01-PROBE-NOTES (160 bytes, 320 nibbles, matches expected 5-word layout)

## Human Checkpoint

User approved via execute-phase orchestrator (03-03-T5).

---
*Phase: 03-three-outcome-protocol-core-and-hex-abi-envelope*
*Completed: 2026-08-28*
