---
phase: 02-transport-spike-throwaway
plan: 02-01
status: complete
completed: 2026-08-28
requirements-completed: [DIST-06]
duration: not-instrumented
---

> **BACK-FILLED 2026-08-28**, reconstructed from git history and PROBE-NOTES. This is NOT a contemporaneous record — the plan was executed inline with the user and no summary was written at the time. Measurements quoted here are sourced from the phase notebook; nothing is reconstructed from memory.

# 02-01 Summary — An enforceable Foundry pin, observed failing two distinguishable ways

**`scripts/foundry-pin.sh` asserts the binary locally and well-formedness in CI, against a pin file
that mirrors the consumer's byte-for-byte. It is the one artifact of Phase 2 that outlives Phase 2.**

## Performance

- **Duration:** not-instrumented (executed inline; no timing was captured)
- **Started / Completed:** not recorded
- **Commits:** 6 (`cd75acf`, `2ef20f2`, `5c1866c`, `04f5366`, `aed92a1`, `ee861fd`)

## Task commits

1. **Add `.github/foundry-version` mirroring cfmm-vol-markets CI-05** — `cd75acf` (feat)
2. **Add the script with `--check-format` and binary assertion modes** — `2ef20f2` (feat)
3. **Wire foundry-pin into justfile and the CI seam job** — `5c1866c` (feat)
4. **Correct CI step line numbers recorded in probe notes** — `04f5366` (feat)
5. **Pin assertion made to fire on the repo tree; record the just gap in phase 1** — `aed92a1` (feat)
6. **CI green, pin step costs 0 s; record gh repo-resolution trap** — `ee861fd` (feat)

## Toolchain ground truth, measured before anything was written

| Field | Value |
|---|---|
| Version | `forge Version: 1.5.1-stable` |
| Commit SHA | `b0a9dd9ceda36f63e2326ce530c10e6916f4b8a2` |
| Build profile | `maxperf` |

Byte-identical to the commit `cfmm-vol-markets` pins in its own pin file (their requirement CI-05).
This box and the consumer's runner are on the same binary.

**Why the pin cannot live in `foundry.toml`:** 111 config keys, the only version-bearing one is
`evm_version` (`prague` — the EVM hardfork the compiler targets, not the binary). Filtering the key
set for `forge`/`foundry`/`toolchain`/`binary` returns an empty list. The reason is structural, not
an oversight: **forge reads the config after it is already running**, so the file cannot constrain
the thing reading it. A value in a config file is something you can read; a script that exits
non-zero is a proposition that goes red.

## The assertion was made to FIRE, on the repo tree

| Stage | Tree state | exit | Failure class |
|---|---|---|---|
| CONTROL | clean | **0** | PASS |
| NEGATIVE | last char of the pinned commit changed | **1** | version mismatch, prints EXPECTED vs ACTUAL |
| CONTRAST | the version line deleted | **1** | **unset-variable — a different error** |
| CONTRAST (`--check-format`) | same | **1** | same error, so CI catches it too |
| RESTORE | `git checkout` | — | `git diff --exit-code` = 0 |

CONTRAST is the stage that matters: NEGATIVE alone cannot distinguish "the guard fired for the
reason we think" from "the guard exits 1 at anything". A `forge` removed from `PATH` reports as
absent (exit 127 path), not as the wrong version — that is what the two-variable capture buys.

The error message tells the reader to install the pin rather than edit it, because editing silently
re-scopes every measurement in the repo.

## CI — run `33171542201`, all three jobs success

| Job | Duration | Phase 1 baseline |
|---|---|---|
| seam | 145 s | 125 s |
| build | 427 s | 440 s |
| image | 56 s | — |

The pin runs as step 3, immediately after checkout and **before** the 117 s toolchain setup, and
costs **0 s**. The seam job's rise over baseline is `haskell-actions/setup` at 117 s this run
against 106 s previously — **runner variance in a step both jobs already paid for**, not a cost the
pin introduced. Recorded this way because the job-level number alone would have supported the wrong
conclusion.

## Two instrument failures recorded here

- **#10 — `just` was not installed on this box, and Phase 1 never noticed.** The T5 criterion
  "`just foundry-pin` exits 0" was **unverified**, not satisfied. Phase 1 also carried `just`-based
  criteria for `image` / `image-run` recipes that did not exist. No false claim had been recorded —
  the gap is an unverified criterion, not a fabricated result. Deliberately **not** fixed inside
  Phase 2; recorded in STATE blockers and closed later under 01-06 (`a9e9b20`).
- **#11 — `gh run list` returned `[]`, which reads as "CI did not run".** `gh` resolves this
  checkout to canonical `d2p-finance`, where nothing is ever pushed by DIST-03's design. Same shape
  as Phase 1's `gh api` 404. **Rule: every `gh` invocation here passes `--repo JMSBPP/evm-spec-bridge`.**

## Requirements

- **DIST-06** — the *enforceable* half is met and the mechanism has been observed to fail. The
  *"published as part of the integration contract"* half is not met: the consumer maintains their
  own pin and consumes nothing of ours. Completes at Phase 10.
