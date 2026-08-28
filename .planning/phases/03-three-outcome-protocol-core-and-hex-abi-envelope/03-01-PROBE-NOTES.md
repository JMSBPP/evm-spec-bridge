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

---

## 03-01-T3 — a criterion that cannot be satisfied as literally written

`03-01-T3` and `03-07-T6` both assert:

> `protocolVersion` appears exactly ONCE as a definition:
> `grep -c '^protocolVersion'` returns **1**

**It returns 2, and cannot return 1 in this component.** Measured:

```
$ grep -n '^protocolVersion' components/protocol/src/Bridge/Protocol.hs
141:protocolVersion :: Word16
142:protocolVersion = 1
```

Line 141 is the type signature, line 142 the single equation. Dropping the signature would make the
grep return 1 — and would fail the build, because `-Wall` (already in this component's
`ghc-options`) enables `-Wmissing-signatures` and `--pedantic` adds `-Werror`. There is no legal
Haskell spelling of a top-level signature that does not begin at column 0 with the binder's name.

So the criterion as phrased is in direct conflict with the project's own warning flags. The
criterion's *intent* — one definition, no literal repeated at construction sites — holds. Evidence:

```
$ grep -c '^protocolVersion =' components/protocol/src/Bridge/Protocol.hs
1
$ grep -rn 'protocolVersion' components/ --include=*.hs
components/protocol/src/Bridge/Protocol.hs:141:protocolVersion :: Word16
components/protocol/src/Bridge/Protocol.hs:142:protocolVersion = 1
```

**Recommendation for 03-07-T6:** change the check to `grep -c '^protocolVersion ='` (expect 1) plus
the repo-wide `grep -rn` above (expect no second definition). Recorded rather than silently
substituted, on the same principle as the T2 dependency relocation.

## A second grep that measured prose, not structure

`grep -cE 'Data\.Aeson|Data\.Solidity' components/protocol/src/Bridge/Protocol.hs` initially
returned **2** — both hits were in the module's own haddock, explaining that it imports neither.
The module's only import has always been `Data.Word`.

The prose was reworded so the check measures imports rather than the comment about imports. This is
03-VALIDATION rule 6 read in reverse: a criterion must test structure, not comment text — which
also means comment text must not be able to *fail* a structural criterion. `grep -c '^import'`
returns 1 and it is `Data.Word`.

---

## 03-01-T4 — the seam guard still fires with a real third-party dependency in core

Run inline with the user. **The script was NOT modified** — `git diff --exit-code
scripts/seam-negative-test.sh` exits 0. If it had needed modifying to accommodate `web3-solidity`,
that would itself have been the finding.

| Stage | Result |
|---|---|
| CONTROL — `./scripts/seam-guard.sh` on the clean tree | **exit 0** |
| 3-stage negative test, unmodified | **exit 0** |
| Its verdict, verbatim | `PASS: control resolved, guard fired with S-4804 naming the offender, contrast confirms it is the seam` |

Identical behaviour to 01-04's recorded run. The guard is unaffected by a core component gaining a
snapshot dependency.

### What the dry-run output additionally proves

`stack-core.yaml` — the **spec-less** config — resolves `web3-solidity-1.1.0.0` from the snapshot
without complaint, listing it as `database=snapshot`. This is worth stating because it clarifies
what the guard actually asserts: **"no core component depends on the SPEC"**, not "no core
component has dependencies". The two are easy to conflate when the only dependency the guard had
ever seen was the spec itself.

### UNPREDICTED: the Polkadot SCALE codec arrives anyway

The build plan under `stack-core.yaml` includes:

```
* bitvec-1.1.6.0
* scale-1.1.0.0          <- SCALE: the Polkadot/Substrate codec
* web3-crypto-1.1.0.0    ... after: memory-hexstring-1.1.0.0
* web3-solidity-1.1.0.0  ... after: cereal, generics-sop, memory-hexstring, microlens, web3-crypto
```

We chose `web3-solidity` over the `web3` meta-package **specifically to avoid `web3-polkadot`**.
That still holds — `web3-polkadot` is not in the plan. But **`scale`, the Substrate codec, comes in
transitively through `web3-crypto`**, which `web3-solidity` depends on unconditionally.

So the avoidance was partial. We dodged the Polkadot *package*; we did not dodge its *codec*. This
is not a defect — `scale` is pure Haskell with no native deps, and the container check still holds
— but the claim "we avoided Polkadot" is narrower than it sounded, and is corrected here rather
than left to be remembered generously.

**Relevant to Phase 8:** if the codegen ever wants a smaller dependency footprint, hand-rolling the
three encodings (`uint16`, `uint8`, `bytes`) removes `web3-solidity`, `web3-crypto`, `scale`,
`bitvec`, `generics-sop`, `sop-core`, `microlens` and `memory-hexstring` in one move. Recorded as an
option with its cost known, not as a recommendation.

---

## Corrections to our OWN acceptance criteria (03-01)

Two criteria in `03-01-PLAN.md` were defective, both mine, both the same class.

**1. `grep -c '^protocolVersion'` required to return 1 — IMPOSSIBLE.**
`Bridge/Protocol.hs:146` is the type signature and `:147` the equation; both begin at column 0, so
the count is necessarily 2. Deleting the signature would satisfy the criterion **and fail the
build**: `-Wall` enables `-Wmissing-signatures` and `--pedantic` adds `-Werror`. The criterion
contradicted the project's own compiler flags. Corrected to `'^protocolVersion ='` in 03-01 and
03-07. The executing agent refused to work around it and reported it, which is the correct handling.

**2. `grep -cE 'Data\.Aeson|Data\.Solidity'` required to return 0 — tripped by a comment.**
The module's haddock said it imports neither, and therefore contained both strings. The property
was true; the text was not. The comment was reworded — a change made to satisfy a grep, not to fix
a defect, and flagged as such by the agent.

**This is the FOURTH occurrence.** Phase 2 had two (`via_ir\|optimizer` tripped by a comment
explaining what we deliberately do not set; the "no typed `= vm.rpc(`" grep). `03-VALIDATION.md`
already carried the rule "a criterion must test configuration, not comment text" — and these were
written anyway.

**The rule, strengthened in 03-VALIDATION.md:** prefer a compile result, a type signature, effective
config, or an assertion on emitted output. Where a grep genuinely is the right instrument, anchor it
to syntax that cannot appear in prose (`'^name ='`, not `'^name'`) — and **never write a criterion
whose only failure mode is someone mentioning the thing.**

---

## PROTO-04 — type-level evidence (03-02)

Evidence form (1): compile-fail check `scripts/hex-only-guard.sh`, CONTROL / NEGATIVE / CONTRAST
pattern matching `scripts/seam-negative-test.sh`. GHC 9.10.3 diagnostics verbatim:

**NEGATIVE** (`compile-fail/RawConstructor.hs`):

```
components/abi-codec/compile-fail/RawConstructor.hs:8:15: error: [GHC-01928]
    • Illegal term-level use of the type constructor ‘Hex0x’
    • imported from ‘Bridge.AbiCodec.Hex’ at ...
    • In the first argument of ‘print’, namely
        ‘(Hex0x (BS.pack [0x01]))’
```

**CONTRAST** (`compile-fail/NumberBody.hs`):

```
components/abi-codec/compile-fail/NumberBody.hs:9:11: error: [GHC-39999]
    • No instance for ‘Num Hex0x’ arising from the literal ‘42’
    • In the expression: 42 :: Hex0x
```

The two failures are distinguishable: NEGATIVE names unexported constructor use; CONTRAST names
missing `Num` instance. CONTRAST output does NOT contain `Illegal term-level use of the type
constructor`.

Evidence form (2): `Bridge/AbiCodec/Hex.hs:29` defines `newtype Hex0x = Hex0x BS.ByteString` with
constructor NOT in export list (`Hex0x` without `(..)` at line 8). `Bridge/AbiCodec/Hex.hs:78-80`
defines the sole `instance Aeson.ToJSON Hex0x`. Repo-wide `grep -rn 'instance.*ToJSON' components/`
returns exactly 1 match — no other wire-rendering path exists today.

**Component choice:** `abi-codec`, not `protocol`. 03-01-T3 requires `Bridge/Protocol.hs` import
nothing from `Data.Aeson`; a `ToJSON` in `protocol` would break that criterion.

**Property test deliberately NOT written:** `PITFALLS.md:171` recommends a property test asserting
the encoder never emits `null`. That test would be vacuous once the field type is `Hex0x` — every
generated input is already a `Hex0x`, so every case passes regardless of encoder correctness.
Superseded by ROADMAP Phase 3 criterion 2 amendment (2026-08-28): structural unrepresentability
replaces the property test.

**Residual gap:** the guard covers `Hex0x` only. A future module defining its own `ToJSON` for a
different wire type would not be caught by this guard. The repo-wide instance count of 1 is the
canary — any second instance is a review trigger.

---

## Golden vector (03-03-T4)

**Input:** `SpecRejection GuardStrikeOutOfRange` (guard `fromEnum` = 3, tag `0x02`, body = `abi.encode(uint8 3)`).

**Exact output (one line):**

```
0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003
```

| Metric | Value |
|---|---|
| Decoded byte length | 160 |
| Hex nibble count (after `0x`) | 320 |

| Word | Expected | Actual | Match |
|---|---|---|---|
| 0 | `0x0001` (protocolVersion = 1) | `0x0000000000000000000000000000000000000000000000000000000000000001` | yes |
| 1 | `0x02` (tag rejection) | `0x0000000000000000000000000000000000000000000000000000000000000002` | yes |
| 2 | offset `0x60` (96) | `0x0000000000000000000000000000000000000000000000000000000000000060` | yes |
| 3 | body length `0x20` (32) | `0x0000000000000000000000000000000000000000000000000000000000000020` | yes |
| 4 | body `abi.encode(uint8 3)` | `0x0000000000000000000000000000000000000000000000000000000000000003` | yes |

**Conditions:** `web3-solidity-1.1.0.0` (LTS 24.55 snapshot), GHC 9.10.3, measured 2026-08-28.

**Human checkpoint (03-03-T5):** User approved via execute-phase orchestrator. Confirmed: word 0 is version, word 1 low byte is tag `0x02`, dynamic `bytes body` starts at word 4; odd-nibble hex falls off the bytes branch onto value-dependent string coercion (`PITFALLS.md:78` left-pads silently); tag `0x00` reserved because JSON `null` arrives as 32 zero bytes with `success == true` (`PITFALLS.md:164`); `web3-solidity` is third-party code and a named suspect if boundary cases fail in 03-06.

---

## json-rpc residency (03-04-T1)

| Condition | Value |
|---|---|
| Command | `stack build evm-spec-bridge-jsonrpc --dry-run` |
| Exit code | 0 |
| Extra-dep needed | no — `json-rpc-1.1.2` snapshot-resident |
| Snapshot | LTS 24.55 (`stack.yaml` URL pin) |
| Date | 2026-08-28 |

`./scripts/seam-negative-test.sh` unmodified: exit 0.

---

## PROTO-02 channel discipline (03-04-T4)

**Human checkpoint:** User approved via execute-phase orchestrator.

Encoded rejection (verbatim):

```json
{"jsonrpc":"2.0","id":0,"result":"0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003"}
```

**Human checkpoint (03-04-T4):** User approved via execute-phase orchestrator.

---

## Forge project placement (03-05-T1)

**DECISION: PERMANENT at `solidity/`.** Reasons: DIST-01 consumer submodule needs a forge home; Phase 8 coercion fixture and Phase 9 generated call site need a standing `forge test` lane; 03-07 wedge fixture reusable by Phase 5 soak.

Hand-written Solidity inside is temporary — Phase 9 replaces it. Deletion requires `git rm -r` **and** `rm -rf` because `out/` and `cache/` are gitignored (02-05 finding).

User approved via execute-phase orchestrator.

---

## Discrimination run (03-05-T4)

| Condition | Value |
|---|---|
| Mode | rejection |
| Port | 8899 |
| Forge | 1.5.1 / b0a9dd9 |
| solc | 0.8.34 |

Returndata length: 224 bytes (abi.encode(bytes) wrapper over 160-byte envelope). Decoded: version=1, tag=0x02, guardId=3. `forge test --match-test test_rejection_isReadAsRejection` wall ~610ms suite / 12ms test CPU.

Human checkpoint (03-05-T6): User approved via execute-phase orchestrator.

---

## Class 6 — odd-nibble (03-06-T4)

Class 6 is a **refusal test**, not a round-trip. No odd-nibble string was sent to forge deliberately.

Two refusal points: `hexOfText` → `OddNibbleCount` (input); `encodeEnvelope` → `OddNibbleEmitted` (output vs web3-solidity).

Human checkpoint (03-06-T6): User approved via execute-phase orchestrator.

---

## Wedge red (03-07-T4)

NEGATIVE stage elapsed: **47s** (Foundry REQUEST_TIMEOUT; forge 1.5.1/b0a9dd9, solc 0.8.34, `--mode wedge`).

COST unbounded until Phase 5 SRV-04. Human checkpoint: User approved via execute-phase orchestrator.
