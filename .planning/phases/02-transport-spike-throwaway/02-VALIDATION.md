---
phase: 2
slug: transport-spike-throwaway
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-28
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

**Phase requirements:** DIST-06

**Note on this phase's character.** Phase 2 produces almost no durable code. Its output is
**measurements** plus one permanent artifact (the Foundry pin). That inverts the usual validation
question. Normally we ask "does the code do the right thing"; here we must ask **"is this
measurement true, and true under which conditions?"**

Phase 1 produced nine instrument failures — cases where a check could not detect what it was
pointed at. Every one of them was a measurement problem, not a code problem. So this phase's
validation strategy is largely a defence against repeating them.

**Written inline by the user's mandate — no researcher agent, no RESEARCH.md dependency.** Derived
directly from `02-CONTEXT.md`.

---

## The three rules this phase is validated against

1. **Exit code before greps.** Established in Phase 1 after `--progress=plain` (unknown flag on the
   legacy builder) and `set -o pipefail` (dash, not bash) both read as clean from greps alone.
   Check that a command *succeeded* before believing anything about its output.
2. **Every number carries its conditions.** The seam guard was measured at 0.34 s warm and quoted
   unqualified; cold it is 118 818 ms — a 350x difference that changed the CI design. A measurement
   without its conditions is folklore.
3. **A guard nobody has seen fire is a guard being trusted, not verified.** Carried from Phase 1.
   Applied here to the Content-Type probe: serving the *correct* header and seeing green proves
   only that the happy path works, not that anything is enforced.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `forge test` (Solidity side) + the existing `tasty` suite (Haskell side, untouched this phase) |
| **Toolchain** | `forge` **v1.5.1 / b0a9dd9ceda36f63e2326ce530c10e6916f4b8a2** — asserted, not assumed |
| **Server** | Locally built warp stub via `stack run`, bound to `127.0.0.1` |
| **Entry point** | A `just` recipe the user can re-run and modify |
| **Quick check** | The pin assertion — `forge --version \| grep -qF "$FOUNDRY_COMMIT"`, sub-second |
| **Estimated runtime** | Pin assertion <1 s. Stub build: UNMEASURED. `forge test`: UNMEASURED — both are deliverables, not estimates |

---

## Sampling Rate

- **Before any measurement is recorded:** the pin assertion must pass. A measurement taken on a
  drifted `forge` is not a measurement of anything.
- **After every task commit:** `stack build` exits 0 (the stub must still compile).
- **After every measurement:** the observation is written to PROBE-NOTES **with its conditions**
  in the same commit — not batched at phase end, where conditions get reconstructed from memory.
- **Max feedback latency:** the `just` recipe end-to-end. Target under a minute warm; measured, not
  assumed.

---

## Per-Task Verification Map

| Task ID | Plan | Requirement | Test Type | Automated Command | Status |
|---------|------|-------------|-----------|-------------------|--------|
| Pin file exists and is sourceable | 02-01 | DIST-06 | structural | `. ./.github/foundry-version && test -n "$FOUNDRY_COMMIT"` exits 0 | ⬜ pending |
| Pin values match the consumer's | 02-01 | DIST-06 | structural | `diff <(grep -E '^FOUNDRY' .github/foundry-version) <(grep -E '^FOUNDRY' <consumer path>)` — empty | ⬜ pending |
| **Pin assertion FIRES on a mismatch** | 02-01 | DIST-06 | **negative** | Temporarily corrupt `FOUNDRY_COMMIT` → assertion script exits **non-zero** and names the expected commit | ⬜ pending |
| Assertion runs in CI | 02-01 | DIST-06 | structural | `ci.yml` invokes the assertion script; workflow run is green | ⬜ pending |
| Assertion runs locally | 02-01 | DIST-06 | structural | The `just` recipe invokes the same script — same string, not a copy | ⬜ pending |
| Stub compiles | 02-02 | — | structural | `stack build` exits 0 | ⬜ pending |
| Stub answers on loopback | 02-02 | — | behavioural | `curl -s -X POST http://127.0.0.1:$PORT` returns a JSON-RPC body with the echoed `id` | ⬜ pending |
| Stub binds `127.0.0.1`, not `0.0.0.0` | 02-02 | — | structural | `ss -ltn` shows `127.0.0.1:$PORT`; source contains no `0.0.0.0` | ⬜ pending |
| **`forge test` GREEN through `vm.rpc`** | 02-03 | — | behavioural | `forge test` exits 0 with ≥1 passing test that called `vm.rpc` | ⬜ pending |
| **The green is not vacuous** | 02-03 | — | **negative** | Stop the server → the same test goes **RED**. A test that passes with no server proves nothing | ⬜ pending |
| Return-path shape recorded | 02-03 | — | measurement | PROBE-NOTES states whether returndata was wrapped, with the decode that worked | ⬜ pending |
| Content-Type: `application/json` | 02-04 | — | measurement | Call succeeds; row recorded | ⬜ pending |
| Content-Type: `text/plain` | 02-04 | — | **negative** | Outcome recorded either way — this row is the one that answers "is it enforced" | ⬜ pending |
| Content-Type: **absent** | 02-04 | — | **negative** | Outcome recorded; distinguishes "wrong type rejected" from "missing header rejected" | ⬜ pending |
| Hex envelope round-trips byte-exact | 02-04 | — | behavioural | Bytes decoded in Solidity are **identical** to bytes the stub encoded — asserted, not eyeballed | ⬜ pending |
| Spike deleted | 02-05 | — | structural | `git status --porcelain` clean; spike paths absent; `stack build` still exits 0 | ⬜ pending |
| Pin survives deletion | 02-05 | DIST-06 | structural | `.github/foundry-version` still present and CI still green after the spike is removed | ⬜ pending |
| Ledger updated | 02-05 | — | structural | ROADMAP shows 5/5 Complete; STATE names Phase 3 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `.github/foundry-version` with all three values, matching the consumer byte-for-byte
- [ ] An assertion script following the `scripts/*.sh` convention — exits non-zero, names what it
      expected, invoked by the identical string from `just` and from CI
- [ ] The local `forge` confirmed at `v1.5.1`/`b0a9dd9` **before** any measurement is taken

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| The user can explain the four layers | — | Pedagogical mandate: an artifact the user cannot explain has half-failed | User states where `Content-Type` sits, where Foundry's coercion sits, and why the hex envelope exists |
| The user can re-run the spike unaided | — | The `just` recipe is for the user, and only they can confirm it serves them | User runs the recipe themselves, changes the payload, and observes the test react |

---

## Known Validation Gaps

- **The Content-Type outcome is unknown in BOTH directions.** We do not know whether alloy enforces
  it. Do not write acceptance criteria that presuppose an answer — the criterion is *"the outcome
  is recorded with its conditions"*, not *"the call succeeds"*. A probe whose expected result is
  already written down is not a probe.
- **`guess_local_url` / `HTTP_PROXY` remains `[S]` — source-derived, never observed.** Deferred to
  Phase 6 by decision. Addressing as `127.0.0.1` means the spike is unaffected, but the trap is
  **not retired**, and this is the same provenance that produced the `vm.rpcJson` error.
- **One host, one OS.** Every measurement is taken on this box. Nothing here proves warp/alloy
  conformance on the consumer's runner. The container distribution is what closes that, in Phase 10.
- **A single green `forge test` is a single observation.** It proves the mechanism works once; it
  does not prove stability under load, concurrency, or repetition. Those are Phase 5's questions
  and must not be inferred from this phase's green.
- **Foundry install cost on a hosted runner is unmeasured** and must not be estimated. It only
  matters if a CI lane is ever added — deliberately not done here.

---
*Validation strategy created: 2026-08-28*
