---
phase: 02-transport-spike-throwaway
plan: 02-05
status: complete
completed: 2026-08-28
requirements-completed: [DIST-06]
duration: not-instrumented
---

> **BACK-FILLED 2026-08-28**, reconstructed from git history and PROBE-NOTES. This is NOT a contemporaneous record — the plan was executed inline with the user and no summary was written at the time. Measurements quoted here are sourced from the phase notebook; nothing is reconstructed from memory.

**Note on paths.** The spike directory was deleted by this plan, so paths named below no longer
exist on disk. The durable record is
`.planning/phases/02-transport-spike-throwaway/02-01-PROBE-NOTES.md`; the surviving artifact is
`scripts/foundry-pin.sh`.

# 02-05 Summary — The spike deleted, the pin and the measurements kept, the ledger updated in-plan

**The deletion claim inherited from 02-02 was tested rather than assumed, and it was falsified
twice.**

## Performance

- **Duration:** not-instrumented (executed inline; no timing was captured)
- **Started / Completed:** not recorded
- **Commits:** 4 (`8a61638`, `405a57f`, `267c3f0`, `24be1e0`)

## Task commits

1. **Phase 2 summary — written before deletion** — `8a61638` (docs)
2. **Delete the spike — `git rm` left 46 MB of gitignored artifacts** — `405a57f` (feat)
3. **Close phase 2 — roadmap 5/5, DIST-06 partial with reason, state advanced to phase 3** — `267c3f0` (docs)
4. **CI green after deletion (run `33178908276`)** — `24be1e0` (docs)

## The deletion claim, falsified twice

02-02 claimed deletion would be "`rm -rf spike/` and nothing else". This plan existed to test that.

**1. `git rm -r` is not the deletion.** It removes *tracked* files and leaves every gitignored
build artifact behind. After `git rm -r`, the directory was **still on disk at 46 MB** —
`.stack-work` in two places plus the forge `out/` and `cache/` trees — showing in `git status` as
untracked. Both `git rm -r` (for the reviewable diff) **and** `rm -rf` (for the artifacts) were
required.

**2. The drift gate went RED on the staged deletion.** `scripts/hpack-drift.sh` exited 1 reporting
"untracked or unstaged .cabal files" over a `D ` entry — which is a **staged deletion**, neither
untracked nor unstaged. The gate's condition fires on *any* `.cabal` state change; its message
describes a narrower condition than the one it detects. Transient — green immediately after the
commit — and not worth changing, but it would mislead anyone hitting it cold.

**The isolation claim was directionally right and literally wrong.** The spike genuinely never
touched `stack.yaml`, `stack-core.yaml`, the components, or `.github/workflows/ci.yml` — the
deletion diff is nine file deletions plus one `justfile` edit and nothing else. But "deletion is
one command" was not true, and the only reason we know is that a task was written to check it.

## Verified after the deletion commit (`405a57f`)

| check | exit |
|---|---|
| `stack build` | 0 |
| `scripts/seam-guard.sh` | 0 |
| `scripts/hpack-drift.sh` | 0 |
| **`scripts/foundry-pin.sh`** | **0 — the pin survived** |
| pin still byte-identical to the consumer's | identical |
| `just --list` spike recipes remaining | 0 |
| residue outside `.planning/` | none |
| **CI run `33178908276`, post-deletion** | seam / build / image all success |

## The ledger was updated inside this plan, deliberately

This plan exists in this shape because Phase 1's ledger was never updated by its own work: ROADMAP
read `0/9` and STATE said "Ready to plan" while nine plans sat committed, and it had to be patched
by hand afterwards in `41eb40c`. Here ROADMAP was set to 5/5, DIST-06 marked **partial with the
reason written out**, and STATE advanced to Phase 3 — as a task with acceptance criteria rather
than a step someone remembers.

## What was still missing, and is what this back-fill repairs

The ledger update covered ROADMAP, REQUIREMENTS and STATE, but **no per-plan summaries were written
for any inline-executed plan in Phases 1 or 2** — only the two phase-level summaries and the shared
notebooks. That left `summaries < plans` on disk for both phases, which mis-routes progress
tooling. These thirteen back-filled files close that gap.

## Requirements

- **DIST-06** — recorded as **partial, with the reason stated**: the *enforceable* half is met
  (`.github/foundry-version` mirrors the consumer's byte-for-byte; `scripts/foundry-pin.sh` was
  observed failing two distinguishable ways; CI asserts well-formedness at 0 s). The *"published as
  part of the integration contract"* half is not met — the consumer maintains their own pin and
  consumes nothing of ours. Completes at Phase 10.
