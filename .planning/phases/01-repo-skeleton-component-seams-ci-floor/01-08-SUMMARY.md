---
phase: 01-repo-skeleton-component-seams-ci-floor
plan: 01-08
status: complete
completed: 2026-08-27
requirements-completed: [DIST-04]
duration: not-instrumented
---

> **BACK-FILLED 2026-08-28**, reconstructed from git history and PROBE-NOTES. This is NOT a contemporaneous record — the plan was executed inline with the user and no summary was written at the time. Measurements quoted here are sourced from the phase notebook; nothing is reconstructed from memory.

# 01-08 Summary — Image published to GHCR and pulled with no credentials

**The `image` job builds on every trigger and pushes only on `push` events; the published image was
pulled anonymously with a verified-empty credential directory.**

## Performance

- **Duration:** not-instrumented (executed inline; no timing was captured)
- **Started / Completed:** not recorded
- **Commits:** 2 (`8a754f2`, `ad7cd2b`)

## Task commits

1. **GHCR image job — lowercase ref, slash-free tag, push only on push events** — `8a754f2` (feat)
2. **Image published and anonymously pullable; GHCR private-by-default did not hold** — `ad7cd2b` (chore)

## What was built

The permission asymmetry the plan was written around is real: a `pull_request` from the `JMSBPP`
fork into `d2p-finance` runs with a read-only token, `packages: write` is silently downgraded, and
an unconditional push would 403. So the job **builds always and pushes only on `push` events**, with
a hardcoded lowercase image reference and a slash-free tag, plus the
`org.opencontainers.image.source` label linking the package to the repository.

## Measured — run `33127963832`, all three jobs green

Published and pulled **anonymously with an empty `DOCKER_CONFIG`**:

```
ghcr.io/jmsbpp/evm-spec-bridge:develop        129MB
ghcr.io/jmsbpp/evm-spec-bridge:sha-b3c5621…   129MB
$ docker run --rm ghcr.io/jmsbpp/evm-spec-bridge:develop --version
evm-spec-bridge-transport 0.1.0.0
```

## A research prediction that did NOT hold

RESEARCH.md and this plan's own `user_setup` block both state that a newly published GHCR package
is **private by default**, requiring a one-time irreversible manual visibility flip that no
workflow can perform. It was carried as Phase 1's single human-action checkpoint.

**Observed: the package was public immediately.** Two anonymous pulls, fresh empty `DOCKER_CONFIG`
directories confirmed to contain no credentials, both succeeded. **The mechanism is not known and
has not been invented** — only the outcome is recorded. The manual dashboard step in this plan's
`user_setup` was therefore never needed.

Worth noting the asymmetry: a predicted blocker that failed to appear is the harmless direction.
Assuming public and finding private would have 403'd the consumer's first pull with no obvious cause.

## Instrument failure — the 404 that meant something else

`gh api user/packages/container/evm-spec-bridge` returned **404 Package not found**, which reads as
"nothing was published". After refreshing scope it returned **403: You need at least read:packages
scope**. The 404 was an authorization artefact wearing the costume of an existence claim. Had the
verdict been taken from it, the conclusion would have been "the image job silently failed to
publish" — about a package that was published, public and pullable. Settled instead by the
credential-free `docker pull`, which asks the question directly.

## Files modified

- `.github/workflows/ci.yml` — the `image` job, 54 lines added

## Requirements

- **DIST-04** — the image is built and published to GHCR, and anonymous pullability is proven
  rather than assumed. DIST-04 remains **partial** overall: generated Solidity is not yet in the
  gate and completes in Phase 8.
