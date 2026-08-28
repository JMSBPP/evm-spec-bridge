---
phase: 01-repo-skeleton-component-seams-ci-floor
plan: 01-07
status: complete
completed: 2026-08-27
requirements-completed: [DIST-04]
duration: not-instrumented
---

> **BACK-FILLED 2026-08-28**, reconstructed from git history and PROBE-NOTES. This is NOT a contemporaneous record — the plan was executed inline with the user and no summary was written at the time. Measurements quoted here are sourced from the phase notebook; nothing is reconstructed from memory.

# 01-07 Summary — The gate exists, and it caught a real bug on its first run

**`.github/workflows/ci.yml` runs a `seam` job and a `build` job on push and pull_request; the
first execution went `seam: success` / `build: failure` on a genuine type error.**

## Performance

- **Duration:** not-instrumented (executed inline; no timing was captured)
- **Started / Completed:** not recorded
- **Commits:** 2 (`b4dc2cb`, `fae39e5`)

## Task commits

1. **CI gate on push+PR — cache before seam, immutable-safe key, measured cairo deps** — `b4dc2cb` (feat)
2. **CI green; record measured gate timings** — `fae39e5` (chore)

## The first run found something

Run `33126472689` — the first execution of our own gate:

```
overall: failure
  seam:  success      <- the seam is sound
  build: failure      <- the code was not
```

The `build` job runs `stack build --test --pedantic` over **all** packages, so `cfmm-adapter` was
compiled for the first time and its `[GHC-83865]` type error surfaced. The seam job passing while
the build job failed is the system working correctly: the two jobs answer different questions and
neither substitutes for the other. Fix committed under 01-02 (`050739a`).

## Measured on a hosted runner — run `33126990346`, all green

| Step | Duration |
|---|---|
| `haskell-actions/setup@v2` | **106 s** |
| cairo/pango apt provisioning | **14 s** |
| Cold build (`--test --no-run-tests --pedantic`) | **302 s** |
| Warm rebuild, identical flags | **~0 s** |
| Tests + hpack drift gate | ~1 s |
| **seam job total** | **125 s** |
| **build job total** | **440 s** |

These replace every build-time estimate in the planning tree. The 302 s hosted figure sits beside
281 s measured locally on 12 cores.

### Three findings

1. **The warm rebuild is instant, which validates keeping `--pedantic` on both builds.** Dropping
   it for the second build would have recompiled all seven packages and reported a full recompile
   as an incremental number.
2. **Provisioning is 4.4% of the cost** (14 s apt vs 302 s compile). The upstream warning that the
   win would be mostly provisioning is the reverse of what was measured: almost all the cost is
   compilation.
3. **The seam job's fail-fast advantage is smaller than assumed.** 125 s, of which 106 s is
   `haskell-actions/setup` — a cost *both* jobs pay. Splitting saves the 302 s build, not the 106 s
   setup, so the honest claim is "fails before the expensive build", not "fails in seconds".

## Decisions carried in from 01-03

The cache restore runs **before** the seam guard, because the guard is 303 ms warm and 118 818 ms
cold and every CI run starts from a fresh checkout. The cache key uses `hashFiles` over
`stack.yaml`, `stack.yaml.lock` and the component `package.yaml` files, and is immutable-safe. The
workflow-level token is `contents: read` only.

## Files created

- `.github/workflows/ci.yml` — 117 lines, two jobs

## Requirements

- **DIST-04** — the hosted gate on push and pull request exists, builds every component, runs the
  suite and gates hpack drift. The image job is 01-08.
