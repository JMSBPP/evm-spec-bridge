---
phase: 01-repo-skeleton-component-seams-ci-floor
plan: 01-04
status: complete
completed: 2026-08-27
requirements-completed: [CFMM-01]
duration: not-instrumented
---

> **BACK-FILLED 2026-08-28**, reconstructed from git history and PROBE-NOTES. This is NOT a contemporaneous record — the plan was executed inline with the user and no summary was written at the time. Measurements quoted here are sourced from the phase notebook; nothing is reconstructed from memory.

# 01-04 Summary — The guard was seen to fire, and the proof was proven able to fail

**Three layers, each verifying the one below: `scripts/seam-guard.sh` catches violations,
`scripts/seam-negative-test.sh` proves the guard fires, and a meta-check proves the negative test
can go red.**

## Performance

- **Duration:** not-instrumented (executed inline; no timing was captured)
- **Started / Completed:** not recorded
- **Commits:** 1 (`885b589`)

## Task commits

1. **Seam guard + 3-stage negative test + meta-check, all verified** — `885b589` (feat)

## The three stages — measured

`scripts/seam-negative-test.sh` operates on a scratch copy and never mutates the tree.
`PASS` in **3.8 s** warm.

| Stage | Asserts | Result |
|---|---|---|
| CONTROL | clean tree resolves under `stack-core.yaml` | pass |
| NEGATIVE | injected edge dies with `S-4804`, naming package, dependency and config file | pass |
| CONTRAST | the same violated tree DOES resolve under the full `stack.yaml` | pass |

CONTRAST is what separates "the guard fired" from "the package name was bad" — without it, a typo
in the injected name would produce an identical red.

## The meta-check

Deliberate sabotage: `stack-core.yaml` was given the spec extra-dep, making it semantically
identical to `stack.yaml` — a guard that cannot fire.

```
FAIL(negative): guard did NOT fire on an injected spec dependency
exit=1
```

It broke **at the NEGATIVE stage**, which is the whole point: breaking at CONTROL would have meant
a broken environment, not a vacuous guard. Restoration was confirmed by a **sha256 match** on the
config, and the test re-run to `PASS`.

Only the third layer makes the first two evidence rather than assertion.

## Scope of what this proves — recorded because it was later misread

The guard runs `stack build --dry-run`. That resolves a build plan; **it does not compile code.**
The green here is a true statement about resolvability and says nothing about correctness. Four
plans later the CI `build` job found a type error in `cfmm-adapter` that this guard had been
reporting green over (see 01-02 and 01-07). The guard was not wrong — its scope was quietly widened
in the reader's head from "resolves" to "works".

## Files created

- `scripts/seam-guard.sh` — the positive control
- `scripts/seam-negative-test.sh` — the three-stage proof
- `.gitignore` entries for the scratch artifacts

## Requirements

- **CFMM-01** — acceptance evidence obtained. The forbidden edge was added and the build went red
  for the right reason, and the instrument that showed it was itself falsified and restored.
