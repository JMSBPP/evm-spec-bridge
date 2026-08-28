---
phase: 03-three-outcome-protocol-core-and-hex-abi-envelope
plan: 01
subsystem: protocol
tags: [haskell, adt, abi, web3-solidity, stackage, seam]
requires:
  - phase: 02-transport-spike-throwaway
    provides: "measured vm.rpc wire behaviour and the pinned Foundry toolchain"
provides:
  - "SpecOutcome: three constructors no partial function can map between"
  - "GuardId: a closed, named, Bounded/Enum cfmm guard enum in a spec-free core component"
  - "protocolVersion, defined once"
  - "web3-solidity in abi-codec, with its build cost measured"
affects: [03-02, 03-03, 03-07, phase-08-codegen, phase-11-cfmm-adapter]
tech-stack:
  added: [web3-solidity-1.1.0.0]
  patterns:
    - "Outcomes are constructors, never a status field"
    - "Domain vocabulary in core is allowed; a domain PACKAGE dependency is not"
key-files:
  created: []
  modified:
    - components/protocol/src/Bridge/Protocol.hs
    - components/protocol/package.yaml
    - components/abi-codec/package.yaml
key-decisions:
  - "web3-solidity lives in abi-codec, NOT protocol — protocol imports only Data.Word"
  - "protocolVersion = 1"
  - "GuardId index 3 = GuardStrikeOutOfRange is the golden guard for 03-03/03-05"
  - "FaultCode 0 left unassigned, mirroring the reserved 0x00 tag"
patterns-established:
  - "Every measurement carries its conditions, including host memory state"
  - "Acceptance criteria must test properties, not source text"
requirements-completed: [PROTO-01, PROTO-07, INTEG-02]
duration: not-instrumented
completed: 2026-08-28
---

# 03-01 Summary — Types, the ABI dependency, and the seam under a real third-party dep

**Three outcomes are now three constructors, and the guard enum is closed — in a core component
that still cannot see the spec.**

## What was built

`Bridge/Protocol.hs`, replacing the Phase 1 placeholder:

```haskell
data SpecOutcome a = SpecSuccess a | SpecRejection GuardId | SpecTransportFault FaultCode
data GuardId = ...7 named cfmm guards...   deriving (Eq, Show, Enum, Bounded)
newtype FaultCode = FaultCode Word16       -- 5 named constants; 0 left unassigned
protocolVersion :: Word16
protocolVersion = 1
```

Single import: `Data.Word`. `-Wincomplete-patterns` added to the component and clean.

**Three constructors, not a record with a status field** — a status field permits
`outcome { status = Success }` over rejection data. `Bounded`+`Enum` on `GuardId` let a later test
enumerate every guard and assert total coverage. `FaultCode 0` is deliberately unassigned, mirroring
the reserved `0x00` tag (`PITFALLS.md:164` measured a JSON `null` returning 32 zero bytes with
`success == true` — a zero-valued tag would decode as a valid success).

## Requirement verdicts — honest, not rounded up

| Req | Verdict | Why |
|---|---|---|
| **PROTO-01** | **Met** | Three constructors; `-Wincomplete-patterns` clean, so no partial function maps one to another |
| **PROTO-07** | **Partial** | `protocolVersion` exists and is defined once. "Every response CARRIES it" needs the envelope (03-03) and is verified in 03-07 |
| **INTEG-02** | **Partial** | The enum is closed, named and enumerable. "Adding a guard is a compile error at every consuming site" lands in `cfmm-adapter`'s exhaustive mapping — **Phase 11**, not here |

## The dependency cost — MEASURED, conditions first

**Conditions:** cold, scratch `STACK_ROOT` *and* scratch `--work-dir` per run; full `stack.yaml`
(7 components + spec); `set -o pipefail` inside a subshell so the exit status is the build's and not
`tee`'s; 12 cores; GHC 9.10.3; Stack 3.11.1; LTS 24.55; host, not container.

**Both runs executed under EXHAUSTED SWAP** (`SwapFree` 136 kB, `Committed_AS` ≈3.6× `CommitLimit`),
15 seconds apart with near-identical free memory.

| Run | wall | CPU (user) | pkgs |
|---|---|---|---|
| BEFORE | 308.5 s | 692.9 s | 61 |
| AFTER | 356.7 s | 1282.3 s | 89 |
| **Δ** | **+48.2 s (+15.6%)** | **+589.4 s (+85.1%)** | **+28** |

**The CPU delta is the honest number** — wall clock under-reports because 28 extra packages
parallelise across 12 cores, and CI has fewer.

**These absolutes are NOT comparable to Phase 1's 427-440 s hosted or 281 s local figures**, both
taken on a machine that was not swapping. The delta survives the pressure because both runs shared
it; the absolutes do not.

## Three things nobody predicted

**1. The transitive list was wrong in both directions.** `vector`, `parsec`, `template-haskell`,
`OneTuple`, `tagged` and `data-default` were *already* present before `web3-solidity`. **`aeson` and
`QuickCheck` were unpredicted arrivals** — `aeson` landing here makes 03-04 cheaper than planned.

**2. We avoided Polkadot less than we claimed.** The `stack-core.yaml` build plan contains
`scale-1.1.0.0` and `bitvec-1.1.6.0` — the **Substrate SCALE codec**, arriving through
`web3-crypto`, which `web3-solidity` needs unconditionally. Choosing `web3-solidity` over the `web3`
meta-package did avoid `web3-polkadot` itself, but not its codec. Pure Haskell, no native deps, so
the container check still holds — but the claim was narrower than it sounded.

**3. What the seam guard actually asserts got clarified.** `stack-core.yaml` — the *spec-less*
config — resolves `web3-solidity` from the snapshot without complaint. The guard's proposition is
**"no core component depends on the SPEC"**, not "no core component has dependencies". Easy to
conflate when the only dependency it had ever seen was the spec.

## The seam still fires (03-01-T4)

`scripts/seam-negative-test.sh` run **unmodified** (`git diff --exit-code` clean), exit 0:

> `PASS: control resolved, guard fired with S-4804 naming the offender, contrast confirms it is the seam`

Identical to 01-04. Had the script needed modifying to accommodate the new dependency, that would
have been the finding.

## Corrections to our own acceptance criteria — the fourth occurrence of one defect

**`grep -c '^protocolVersion'` required to return 1 was IMPOSSIBLE.** The type signature and the
equation both begin at column 0, so the count is necessarily 2. Deleting the signature would satisfy
the criterion *and fail the build*, because `-Wall` enables `-Wmissing-signatures` and `--pedantic`
adds `-Werror`. **The criterion contradicted the project's own compiler flags.** Corrected to
`'^protocolVersion ='` in 03-01 and 03-07. The executing agent refused to work around it and
reported it — the correct handling.

**`grep -cE 'Data\.Aeson|Data\.Solidity'` required to return 0 was tripped by a haddock comment**
stating the module imports neither, and therefore containing both strings. The property was true;
the text was not.

**Both are the same defect as Phase 2's two occurrences** (`via_ir\|optimizer` tripped by a comment
explaining what we deliberately do not set; the "no typed `= vm.rpc(`" grep). `03-VALIDATION.md`
already carried the rule and these were written anyway. The rule is now stated with all four
instances and a concrete instruction: anchor greps to syntax prose cannot contain (`'^name ='`), and
**never write a criterion whose only failure mode is someone mentioning the thing.**

**A planning defect found before execution:** 03-01 originally put `web3-solidity` in
`components/protocol`, while its own next task required `Protocol.hs` to import nothing from
`Data.Solidity` — a dependency declared in a package that would never use it. Moved to `abi-codec`
and recorded in-plan rather than silently fixed (`cdf5450`).

## Commits

`cdf5450` plan fix · `a215391` dependency + measurement · `2a4a7d5` the types ·
`614d3f4` + `710320e` criteria corrections · `5cedec5` seam verification

## What this plan did NOT do

- No JSON encoding (03-02), no ABI envelope (03-03), no channel discipline (03-04)
- No Solidity — there is still **no forge project in the repo**; 03-05 creates one
- INTEG-02's compile error is **not** demonstrated: it lands in `cfmm-adapter`'s mapping, Phase 11
- The `web3-solidity` encoder's correctness is **assumed, not verified** — if a boundary class fails
  in 03-06, it is a suspect alongside our own code
