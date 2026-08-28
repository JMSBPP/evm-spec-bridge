---
phase: 01-repo-skeleton-component-seams-ci-floor
plan: 01-02
status: complete
completed: 2026-08-27
requirements-completed: [CFMM-01]
duration: not-instrumented
---

> **BACK-FILLED 2026-08-28**, reconstructed from git history and PROBE-NOTES. This is NOT a contemporaneous record — the plan was executed inline with the user and no summary was written at the time. Measurements quoted here are sourced from the phase notebook; nothing is reconstructed from memory.

# 01-02 Summary — Seven component packages, one declared spec edge

**Seven Stack packages exist under `components/`, and `components/cfmm-adapter/package.yaml` is the
only one naming `cfmm-vol-markets-spec` — the seam is now a declared object rather than a diagram.**

## Performance

- **Duration:** not-instrumented (executed inline; no timing was captured)
- **Started / Completed:** not recorded
- **Commits:** 2 (`2b33087`, `050739a`)

## Task commits

1. **Seven component packages; cfmm-adapter declares the only spec edge** — `2b33087` (feat)
2. **cfmm-adapter type error caught by CI on the gate's first run** — `050739a` (fix)

`050739a` was made after 01-07's first CI run, not during this plan's own execution; it is tagged
`01-02` because it repairs this plan's file.

## What was established

One naming rule applied seven times, fixed before any file existed:

| dir | package | module |
|---|---|---|
| `protocol` `abi-codec` `jsonrpc` `registry` `transport` `codegen` | `evm-spec-bridge-<kebab>` | `Bridge.<Pascal>` |
| `cfmm-adapter` | `evm-spec-bridge-cfmm-adapter` | `Bridge.CfmmAdapter` |

Generated `.cabal` files are committed alongside their sources — e.g.
`components/protocol/package.yaml` beside `evm-spec-bridge-protocol.cabal` in the same directory.

## Decisions

- **D2: `seven-packages`** — not a preference. `internal-libraries:` was ruled out because the
  enclosing *package* carries an internal library's `build-depends`, so the spec-less config would
  fail for the whole package regardless of which library owned the edge; the guard would be
  permanently red and carry zero information. Stack 3.11.1 also cannot name an internal library as
  a build target (`[S-8506]`).
- **Anti-vacuity in the adapter.** `Bridge.CfmmAdapter` imports and *uses* `Panoptic.NId`. A
  declared-but-unused dependency is one the toolchain could drop, which would let the seam guard's
  positive control pass for the wrong reason.

## Correction — the type error the gate caught

CI run `33126472689`, the first execution of our own gate, reported `seam: success` beside
`build: failure`:

```
CfmmAdapter.hs:15:17: error: [GHC-83865]
  Couldn't match expected type 'Int' with actual type 'PanopticTokenId -> Int'
```

`fourLegNumLegs` is a function, not a constant. The anti-vacuity line written here had a type error
in it and survived four plans, because `cfmm-adapter` was never compiled locally — its only
coverage was the seam guard, and **a dry run resolves a build plan; it does not compile code.**

Fixed in `050739a` by keeping the real signature (`specNumLegs :: PanopticTokenId -> Int`) rather
than deleting the import — a placeholder that no longer touches the spec would have reintroduced
exactly the vacuity the import exists to prevent.

## Files created

- `components/{protocol,abi-codec,jsonrpc,registry,transport,codegen,cfmm-adapter}/package.yaml`
- one library module per package under `src/Bridge/`
- `.planning/config.json` was also touched in `2b33087`

## Requirements

- **CFMM-01** — advanced. The forbidden edge is now expressible and the permitted one is declared;
  the mechanism that *decides* it arrives in 01-03, and the proof that it fires in 01-04.
