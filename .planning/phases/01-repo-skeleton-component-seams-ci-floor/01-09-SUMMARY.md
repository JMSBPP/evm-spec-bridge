---
phase: 01-repo-skeleton-component-seams-ci-floor
plan: 01-09
status: complete
completed: 2026-08-27
requirements-completed: [DIST-03, DIST-04]
duration: not-instrumented
---

> **BACK-FILLED 2026-08-28**, reconstructed from git history and PROBE-NOTES. This is NOT a contemporaneous record — the plan was executed inline with the user and no summary was written at the time. Measurements quoted here are sourced from the phase notebook; nothing is reconstructed from memory.

# 01-09 Summary — DIST-03 becomes a mechanism: a direct push to canonical was refused

**Branch protection on `d2p-finance/evm-spec-bridge:main` requires all three gate jobs and binds
admins; a direct push was attempted and rejected, and that refusal is the acceptance evidence.**

## Performance

- **Duration:** not-instrumented (executed inline; no timing was captured)
- **Started / Completed:** not recorded
- **Commits:** 1 (`b3c5621`)

## Task commits

1. **Branch protection on canonical; direct push refused (DIST-03 evidence)** — `b3c5621` (feat)

`b3c5621` changed only the phase notebook. The mechanism it records lives in GitHub repository
settings, not in the tree.

## The protection, read back rather than trusted

```json
{"contexts":["seam","build","image"],"enforce_admins":true,"pr_required":true,"strict":true}
```

All three gate jobs are required. Requiring only `build` would have left CFMM-01 (the seam) and
DIST-04 (the image) advisory — a PR with a red seam job would still merge. `enforce_admins: true`
matters specifically because without it the rule does not bind the person most able to bypass it,
which is the only person likely to.

## The refusal — this IS the evidence

```
remote: - Changes must be made through a pull request.
remote: - 3 of 3 required status checks are expected.
 ! [remote rejected] develop -> main (protected branch hook declined)
exit=1
```

`upstream/main` commit count before: **1**. After: **1**. Nothing landed.

The push was run behind a hard precondition asserting `enforce_admins.enabled == true` AND a
non-empty `required_status_checks.contexts`. Without that gate, a silently-failed protection PUT
would have made this push **succeed**, landing 20 commits of planning history directly on canonical
— the exact violation the task exists to prove impossible. "If it succeeds, stop" is too late: by
then it has happened, and undoing it requires a second forbidden push.

The `-F` vs `-f` distinction was load-bearing in the PUT: `-f` sends strings, and
`required_approving_review_count=0` as a string 422s.

## What this plan did NOT deliver

- **The fork-PR CI observation did not happen.** The plan's must-haves included a PR from
  `JMSBPP:develop` to `d2p-finance:main` running the gate, with the image job building but not
  pushing and not 403-ing. The phase summary records the promotion PR as **available but not yet
  opened**, so that read-only-token context remains designed-for (01-08) and unobserved.
- **`README.md` was not modified.** The plan named it in `files_modified` and required it to state
  the pins, the seam guard's scope and the deferred publish path. `git log -- README.md` shows the
  file unchanged since the repository's initial commit.
- **`.planning/STATE.md` was not updated in this plan.** The ledger was patched afterwards by hand
  in `41eb40c`, which is exactly the failure 02-05 was later written to prevent.

## Requirements

- **DIST-03** — **Met.** Direct push refused by branch protection; canonical `main` unchanged.
- **DIST-04** — advanced, not completed here; see 01-07 / 01-08 and Phase 8.
