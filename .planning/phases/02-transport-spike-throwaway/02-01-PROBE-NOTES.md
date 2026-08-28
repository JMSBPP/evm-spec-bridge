# Phase 2 — Probe Notes

Shared notebook for Phase 2. Values measured live during inline execution, recorded here so
later plans read them back rather than re-deriving or guessing.

**Staging rule:** every commit task in this phase must `git add` this file.

---

## Toolchain ground truth (02-01-T1)

Measured 2026-08-28 on this box, before any file in this plan was written.

### `forge --version`

| Field | Value |
|-------|-------|
| Version | `forge Version: 1.5.1-stable` |
| Commit SHA | `b0a9dd9ceda36f63e2326ce530c10e6916f4b8a2` |
| Build Timestamp | `2025-12-22T11:39:01.425730780Z` |
| Build Profile | `maxperf` |

The Commit SHA is byte-identical to the commit `cfmm-vol-markets` pins in its own
`.github/foundry-version` (their requirement CI-05). This box and the consumer's runner are on
the same binary.

### `forge config --json`

- **111 keys total.**
- The only version-bearing key is `evm_version`, whose value is `prague`. That is the **EVM
  hardfork the compiler targets**, NOT the forge binary.
- Filtering the key set for names containing `forge`, `foundry`, `toolchain` or `binary` returns
  an **EMPTY list**.

### Conclusion — why the pin cannot live in `foundry.toml`

`foundry.toml` has no key of any kind that pins the toolchain. The reason is structural, not an
oversight in the key set: **forge reads `foundry.toml` after it is already running**, so the file
cannot constrain the thing reading it. By the time the config is parsed, the binary has already
been chosen.

Consequence, and the shape of the rest of this plan: the pin must live somewhere that can
**assert** — i.e. a script that can exit non-zero. A value in a config file is something you can
read; `forge --version | grep -qF "$FOUNDRY_COMMIT" || exit 1` is a proposition that goes red.
That is what `scripts/foundry-pin.sh` (02-01-T3) is.

---

## Script sanity check during 02-01-T3 — NOT the T4 negative test

**This does NOT satisfy 02-01-T4.** T4 is a blocking human-verify checkpoint that must be run on
the REPO tree with the user, with restoration proved by `git diff --exit-code`. What follows was
run in a throwaway `/tmp` copy of `scripts/` + `.github/foundry-version` during T3, purely to
avoid committing an assertion that cannot fail. The repo tree was never mutated.

All four failure modes fire, and each fires DIFFERENTLY:

| Perturbation (scratch copy) | Exit | Message class |
|---|---|---|
| last char of `FOUNDRY_COMMIT` changed to `…a3` | 1 | "the forge on this box is NOT the pinned toolchain", quotes EXPECTED commit and full ACTUAL `forge --version` |
| `FOUNDRY_VERSION=` line deleted | 1 | `FOUNDRY_VERSION: ERROR: FOUNDRY_VERSION is unset or empty in .github/foundry-version` — a missing-variable error, not a mismatch |
| `forge` removed from `PATH` | 1 | "could not run \`forge --version\` (exit status 127) … This is NOT a version mismatch" |
| `FOUNDRY_COMMIT` shortened to `b0a9dd9` (`--check-format`) | 1 | "not a full 40-character lowercase hex SHA" |

The third row is the one the two-variable capture buys: a `forge` that cannot start reports as
absent, not as the wrong version.
