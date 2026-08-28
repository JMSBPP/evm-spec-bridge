# 03-01 Probe Notes

Phase 3, plan 01. Every number below carries its conditions; a number without them is not a
measurement, and this file exists so nobody has to reconstruct them later.

---

## web3-solidity build cost — MEASURED 2026-08-28 (03-01-T2)

### Conditions — READ THESE BEFORE COMPARING ANYTHING

| Condition | Value |
|---|---|
| Host | Arch Linux, kernel 7.0.12-arch1-1 (not a container, not CI) |
| Cores | 12 (`nproc`) |
| GHC | 9.10.3 (ghcup, on PATH; `system-ghc: true`, `install-ghc: false`) |
| Stack | 3.11.1 (hpack 0.39.6) |
| Snapshot | LTS 24.55, pinned by URL in `stack.yaml` |
| Command | `stack build --test --no-run-tests --pedantic` (full `stack.yaml`, all 7 components + spec) |
| Warm or cold | **COLD** — scratch `STACK_ROOT` (`mktemp -d`) AND scratch `--work-dir` per run |
| Exit capture | `( set -o pipefail; { time …; } 2>&1 \| tee log )` — Phase 1 MEASURED that without `pipefail` the pipeline reports **tee's** status, not the build's |
| **Memory state** | **SWAP EXHAUSTED throughout both runs.** See below. |

**Memory pressure — a stated condition, not a footnote.** Both runs executed on a host whose swap
was effectively zero and whose commit charge was ~3.6x the commit limit, with a browser, two
`python3` processes, emacs and five concurrent `claude` sessions resident. None were ours to kill.

Reported by the coordinator during the BEFORE run:

```
MemTotal      24,288,564 kB
MemAvailable   4,476,784 kB
SwapTotal      8,388,604 kB
SwapFree             240 kB      <- effectively zero
CommitLimit   20,532,884 kB
Committed_AS  75,133,440 kB      <- 3.6x overcommitted
```

`free -k` snapshots taken at the run boundaries (the BEFORE run's *opening* snapshot was not
captured — the memory condition was flagged mid-run; the reading above stands in for it):

| Moment | free (Mem used / avail) | SwapFree |
|---|---|---|
| immediately after BEFORE build, before any edit (11:54:23) | 19,529,140 / 4,759,424 kB | 136 kB |
| immediately before AFTER build (11:54:38) | 19,631,712 / 4,656,852 kB | 136 kB |
| immediately after AFTER build | 19,202,640 / 5,085,924 kB | 4 kB |

The two runs were 15 seconds apart with near-identical free/available memory and identically
exhausted swap, so the **delta** below is meaningful. The **absolute** numbers are not.

### The numbers

| Run | `components/abi-codec` deps | wall (`real`) | CPU (`user`) | `sys` | exit | pkgs registered |
|---|---|---|---|---|---|---|
| **BEFORE** | `base` only | **308.5 s** (5m08.457s) | 692.9 s (11m32.955s) | 59.7 s | **0** | 61 |
| **AFTER** | `base`, `web3-solidity` | **356.7 s** (5m56.696s) | 1282.3 s (21m22.335s) | 95.9 s | **0** | 89 |
| **Delta** | | **+48.2 s (+15.6 %)** | **+589.4 s (+85.1 %)** | +36.2 s | | **+28** |

**Prefer the CPU-time delta over the wall delta.** Wall clock on a 12-core box under memory
pressure is the least stable of the three; `user` time counts the compilation work actually done
and is ~2x. The wall figure is smaller than the CPU figure because the extra packages parallelise.

### NOT comparable to the Phase 1 baselines

Phase 1's figures are recorded here only so nobody goes looking for them, **not** as a like-for-like
row:

- **427-440 s** — build job total on a hosted GitHub runner (`01-01-PROBE-NOTES.md`, run
  33126990346), of which 302 s was the cold build and 106 s `haskell-actions/setup`.
- **281 s** — cold spec-only build, local, 12 cores, scratch `STACK_ROOT`, **no swap pressure**.

Neither was taken on a swapping machine, and neither built this repo's seven components plus the
spec. Placing 308.5 s next to 281 s as a delta would be reading two different code paths on two
different machine states as one trend — the exact error the "every number carries its conditions"
rule exists to prevent.

**What CI should expect:** the honest transferable claim is the *ratio*, not the seconds — roughly
**+16 % wall, +85 % CPU, +28 packages** on a cold build. Applied to Phase 1's 302 s hosted cold
build that is order **+50 s**, but that projection is arithmetic, not a measurement, and Phase 3's
CI run should replace it.

### 28 transitive packages — MEASURED, and wider than the plan predicted

Registered in AFTER and not in BEFORE:

```
QuickCheck aeson basement bitvec cereal character-ps crypton data-fix dlist
generics-sop integer-conversion integer-logarithms memory memory-hexstring
microlens network-uri scale scientific semialign sop-core text-iso8601
text-short th-compat time-compat uuid-types web3-crypto web3-solidity
witherable
```

Two corrections to `03-01-PLAN.md`'s `<verified_values>` transitive list:

1. **`vector`, `parsec`, `template-haskell`, `OneTuple`, `tagged` and `data-default` were already
   present** in the BEFORE set — they are not additions attributable to `web3-solidity`.
2. **`aeson` and `QuickCheck` were NOT predicted and are real additions.** `aeson` arriving here is
   worth noting: 03-04 needs it anyway for `json-rpc`, so the marginal cost of that plan just got
   smaller. It also means `abi-codec` now transitively *has* `aeson` in scope — which does not
   weaken 03-01-T3's rule that `Bridge.Protocol` imports nothing from `Data.Aeson`, because
   `protocol` still declares `base` only.

No `extra-deps` entry was needed: `web3-solidity-1.1.0.0` is snapshot-resident in LTS 24.55.
`git diff --exit-code stack.yaml` exits 0.

### Seam (CFMM-01) unaffected

`./scripts/seam-guard.sh` exits 0 with the dependency present. `web3-solidity` is not the spec, so
it does not trip the `stack-core.yaml` proposition. The full 3-stage negative test is 03-01-T4's
job, not this task's — this line records only that the cheap guard is green.
