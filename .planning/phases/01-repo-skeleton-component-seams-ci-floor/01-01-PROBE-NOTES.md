# Phase 1 — Probe Notes

Shared notebook for Phase 1. Values measured live during inline execution, recorded here so
later plans read them back rather than re-deriving or guessing.

**Staging rule:** every commit task in this phase must `git add` this file.

---

## Toolchain

Measured 2026-08-27 during `01-01-T1`.

| Value | Measured | Source |
|-------|----------|--------|
| GHC | `ghc-9.10.3` | `resolver.compiler` in the LTS 24.55 snapshot — **inherited, not chosen** |
| Stack | `3.11.1` | `stack --version` (Git rev `2352d78a8ac5b42d021c8064b8f64ac1c8b8b3d5`) |
| hpack | `hpack-0.39.6` | bundled with Stack 3.11.1 |
| Snapshot sha256 | `1c2140555bdf61c30a893b3ec1033987d01eda75ce82a1dda033e8fb6f8b322c` | `sha256sum /tmp/lts2455.yaml` |
| Snapshot size | `732456` | `stat -c '%s'` |

**Snapshot URL (pinned, identical to the spec's):**
`https://raw.githubusercontent.com/commercialhaskell/stackage-snapshots/master/lts/24/55.yaml`

Verified byte-for-byte against
`/home/jmsbpp/cfmms-playground/cfmm-wt/vol-markets/spec/stack.yaml` — the spec pins this exact
URL, which is why the URL form is used rather than the `lts-24.55` shorthand. A shorthand would
let the two repos drift onto different snapshot revisions silently.

**Why this matters downstream:** `ghc-9.10.3` now determines the CI `ghc-version:` input and the
Docker builder base tag (`haskell:9.10.3-bookworm`). Three places, one source of truth — they
cannot disagree without this line changing.
