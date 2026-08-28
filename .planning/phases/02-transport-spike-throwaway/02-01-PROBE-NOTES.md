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
