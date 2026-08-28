---
phase: 4
slug: json-rpc-service-surface-and-fault-taxonomy
reviewer: bugbot
review_scope: uncommitted changes (pre-push)
depth: standard
created: 2026-08-28
status: resolved
---

# Phase 4 — Code Review

**Gate:** Replaces manual README UAT per D-01 amendment (2026-08-28). Re-run on
`origin/develop...HEAD` after push via `$gsd-code-review 4`.

## Findings

| Severity | Location | Finding | Resolution |
|----------|----------|---------|------------|
| Warning | `Bridge/Transport.hs:41-70` | Strict parse faults used `IdInt 0` even when request had valid `id` — breaks PROTO-09 id echo on error paths | Fixed: `lookupFaultId` + faultId threaded through parse helpers; test asserts `"id":42` on unknown-field fault |
| Warning | `justfile:38-41` | `just health` ran `foundry-pin.sh` though health smoke is stack+curl only | Fixed: removed foundry pin from `health` recipe |

## Scope reviewed

- `components/registry/src/Bridge/Registry.hs`
- `components/transport/src/Bridge/Transport.hs`
- `components/oracle-stub/app/Main.hs`
- `solidity/test/SpecFixtures.t.sol`
- `README.md`, `justfile`, health/fixtures scripts

## Verdict

No open Critical/Warning findings after fixes. Phase 4 criterion 6 (README + surface doc) satisfied by code review of pushed diff, not manual diagram inspection.

---

*Reviewer: Bugbot (inline). Re-verify after push with `$gsd-code-review 4`.*
