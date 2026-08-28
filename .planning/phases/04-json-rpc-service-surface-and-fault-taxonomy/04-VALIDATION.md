---
phase: 4
slug: json-rpc-service-surface-and-fault-taxonomy
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-28
---

# Phase 4 — Validation Strategy

**Phase requirements:** PROTO-05, PROTO-06, PROTO-08, PROTO-09, PROTO-10, SRV-06, SRV-07

**Phase character.** Phase 3 validated *impossibility* (types, tags, channels). Phase 4 validates
*behaviour of the service surface* — the right method returns the right shape, the wrong input returns
the right fault code, and repeatability is tested not assumed.

Written inline — no researcher agent.

---

## Rules carried forward

1. **Exit code before greps** — `forge test --json` for Solidity; `stack test` exit code for Haskell.
2. **Assert on emitted bytes/codes**, not source text — fault codes in JSON `-32601`, tag bytes in
   envelope `0x02`/`0x03`.
3. **Phase 3 recipes must stay green** after every plan — `just discriminate`, `boundary-sweep`,
   `wedge-red`, `version-sweep` are regression gates, not optional.
4. **Foundry pin before Solidity** — `./scripts/foundry-pin.sh` exits 0 first.
5. **Seam guard after structural changes** — `./scripts/seam-guard.sh` when components gain deps.

---

## Test infrastructure

| Property | Value |
|----------|-------|
| **Haskell** | `tasty` in `components/jsonrpc/test`, `components/registry/test` (new), `components/transport/test` (new) |
| **Solidity** | `forge test`, pinned v1.5.1 / `b0a9dd9` via `foundry-pin.sh` |
| **Stub** | `oracle-stub` on loopback; `scripts/run-with-stub.sh` for poll-and-run |
| **Entry points** | `just` recipes added in 04-02 (`health`, `fixtures`) and documented in README (04-06) |

---

## Sampling rate

- After every task commit: `stack build --test --pedantic` + `hpack-drift.sh`
- After 04-01+: Phase 3 regression suite (discriminate, boundary-sweep, wedge-red)
- After 04-02+: new `SpecFixtures.t.sol` in CI path via `just fixtures` (or equivalent script)
- After 04-04+: strict-decode negative cases in Haskell only (fast)
- Max feedback: Haskell suite < 60s warm (measured in execution, not assumed)

---

## Per-criterion verification map

| ROADMAP # | Criterion | Primary evidence |
|-----------|-----------|------------------|
| 1 | `spec_health` same envelope shape as domain | Haskell: decode health `result` → tag `0x01`, version word; Solidity: fixture test decodes envelope |
| 2 | Fixture methods + Solidity CI | `SpecFixtures.t.sol` asserts rejection tag + fault tag; `just fixtures` exits 0 |
| 3 | `-32601` + typed decode faults | Haskell tests on encoded JSON for unknown method, unknown field, bad param |
| 4 | Id echo; reject notification/batch | Haskell tests: string id echoed; `null` id / batch array → fault |
| 5 | Repeat request → same bytes | QuickCheck or duplicate POST property test in transport/registry test |
| 6 | README human review (D-01) | 04-VERIFICATION.md checklist; diagrams present; run commands work |

---

## Requirement traceability (plans → reqs)

| Requirement | Plan | Verification artifact |
|-------------|------|----------------------|
| SRV-06 | 04-01 | `spec_health` test + envelope decode |
| SRV-07 | 04-02 | `SpecFixtures.t.sol` |
| PROTO-05 | 04-03 | strict decode test group |
| PROTO-08 | 04-03 | `protocolFaultCodes` extended / fault code assertions |
| PROTO-06 | 04-04 | `eth_call` → `-32601` test |
| PROTO-09 | 04-04 | id echo + batch/notification tests |
| PROTO-10 | 04-05 | purity property test + haddock invariant |
| D-01 | 04-06 | README + 04-VERIFICATION human gate |

---

| 6 | README + surface doc (D-01) | `04-REVIEW.md` from `$gsd-code-review 4` on pushed diff |

---

## Code review gate (replaces manual UAT)

After Phase 4 commits are pushed to `origin/develop`:

```bash
$gsd-code-review 4 --depth=standard
# or: Bugbot on Diff: branch changes (base develop)
```

Scope: `registry`, `transport`, `oracle-stub`, `README.md`, `SpecFixtures.t.sol`, scripts.

Criterion 6 passes when the review report has no unresolved Critical/Warning findings.
Info items are advisory.

---

*Phase: 04-json-rpc-service-surface-and-fault-taxonomy*
