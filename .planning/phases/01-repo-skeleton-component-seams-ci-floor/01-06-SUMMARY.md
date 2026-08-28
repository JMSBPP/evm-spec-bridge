---
phase: 01-repo-skeleton-component-seams-ci-floor
plan: 01-06
status: complete
completed: 2026-08-28
requirements-completed: [DIST-04]
duration: not-instrumented
---

> **BACK-FILLED 2026-08-28**, reconstructed from git history and PROBE-NOTES. This is NOT a contemporaneous record — the plan was executed inline with the user and no summary was written at the time. Measurements quoted here are sourced from the phase notebook; nothing is reconstructed from memory.

# 01-06 Summary — 129 MB runtime image, contents decided by `ldd` rather than by a list

**A trivial `evm-spec-bridge` executable and a two-stage `docker/Dockerfile`; the runtime stage is
`debian:bookworm-slim` + `libgmp10` + `ca-certificates` and contains no cairo.**

## Performance

- **Duration:** not-instrumented (executed inline; no timing was captured)
- **Started / Completed:** not recorded
- **Commits:** 3 (`8d9f630`, `a1a135d`, `a9e9b20`)

## Task commits

1. **Trivial exe + multi-stage image; ldd-derived runtime, 129MB, no cairo** — `8d9f630` (feat)
2. **Provisioning answered — adapter build fails without cairo headers** — `a1a135d` (chore)
3. **Add missing image/image-run just recipes; verify all just criteria** — `a9e9b20` (fix, 2026-08-28)

## Measured

`ldd` on the real binary, before deciding the runtime contents:

```
libm.so.6  libgmp.so.10  libc.so.6  ld-linux-x86-64.so.2
```

| Fact | Value |
|---|---|
| Binary size | 1 078 320 bytes |
| Image size | **129 MB** |
| Shipped binary runs | `evm-spec-bridge-transport 0.1.0.0` |
| cairo/pango in runtime | **0** |
| Build succeeded with no cairo dev headers | yes — *for this target only* |

**`ldd` does not cover locale.** `debian:bookworm-slim` ships none, GHC falls back to ASCII, and the
first non-ASCII byte written would die with `commitBuffer: invalid argument` — invisible behind a
Phase 1 ASCII `--version` and surfacing in Phase 4-5 as a transport failure. `ENV LANG=C.UTF-8` was
added. `ldd` tells you which shared libraries are needed, not everything that is needed.

`.dockerignore` excludes every `package.yaml` in the tree deliberately: without that line `COPY . .` carries all
seven in and the image's own hpack regenerates every `.cabal`. The "hpack never runs inside the
image" must-have is false without it, and the criterion "no COPY line names package.yaml" passes
vacuously because `COPY . .` names nothing.

## Retraction carried into this plan (`a1a135d`)

A separate probe built `evm-spec-bridge-cfmm-adapter` in `haskell:9.10.3-bookworm` with **no cairo
dev headers**. **It FAILS:** `[S-7011] While building package cairo-0.13.12.0`.

| Build | cairo headers needed? |
|---|---|
| transport exe only (this image) | **No** — never reaches the spec |
| `evm-spec-bridge-cfmm-adapter` | **YES — build fails without them** |

So `libcairo2-dev libpango1.0-dev libglib2.0-dev pkg-config` must stay in any job or stage that
builds the adapter. Their absence from this image is a statement about Phase 1's scope, not about
the spec — conflating the two is precisely the earlier error being retracted.

**Instrument failure recorded here:** grepping the failed build log for `cairo\.h|pkg-config|libcairo`
returned **0 matches**, on a build that died of cairo. Caught only by reading the tail. Exit code
before greps.

## The criterion that could not run — closed late, in `a9e9b20`

`01-06-PLAN.md:480` carries `just --list | grep -q 'image-run'` and `:485` requires that
`just --list` lists `image` and `image-run`. **Neither recipe existed**, for two phases, and the
gap was never flagged because `just` was not installed on the machine — absence produced silence
rather than an error, since no gate invokes `just`. No false claim was recorded; the criterion was
simply unverified. Closed on 2026-08-28: both recipes added, `just image` built from scratch
(exit 0) and `just image-run` verified **by execution**, printing `evm-spec-bridge-transport 0.1.0.0`.

**Rule now in force: a criterion phrased against a tool needs evidence the tool exists.**

## Files created

- `docker/Dockerfile`, `.dockerignore`
- `components/transport/app/Main.hs` and its package/`.cabal` updates
- `justfile` recipes `image` / `image-run` (added later, in `a9e9b20`)

## Requirements

- **DIST-04** — advanced: the distribution artifact builds and runs locally. Publishing is 01-08.
