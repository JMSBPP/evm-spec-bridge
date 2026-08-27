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

---

## Spec pin

Read live 2026-08-27 during `01-01-T2`.

- commit: `93fe3acfd2aa13dd28b54d5d44022dc9c10b6341`
- package: `cfmm-scratchpad` version `0.1.0.0`
- branch: `main`
- **repository pinned: `https://github.com/d2p-finance/cfmm-vol-markets-spec.git` (CANONICAL)**

Matches the SHA RESEARCH.md recorded — the spec has not moved since research.

### Deviation from the plan text, and why

`01-01-T2` as written checks the FORK, `https://github.com/JMSBPP/cfmm-vol-markets-spec.git`, and
its acceptance criterion names that URL. Both remotes were queried and both are at
`93fe3acf…` today, so the choice costs nothing right now — but **the pin goes to canonical**,
because PROJECT.md makes `d2p-finance/cfmm-vol-markets-spec` the dependency and because a
published container image must not depend on an unreviewed fork. If the fork later runs ahead of
canonical, pinning the fork would silently ship un-merged spec code inside our artifact.

Both URLs recorded here so downstream greps resolve either way:
- canonical (PINNED): `https://github.com/d2p-finance/cfmm-vol-markets-spec.git`
- fork (reference only): `https://github.com/JMSBPP/cfmm-vol-markets-spec.git`

---

## D1 — does Phase 1 carry the cfmm-scratchpad extra-dep?

**DECISION: add-now**

Rationale: a guard is only a guard if the thing it forbids is possible. With `extra-deps: []` in
both configs, `stack.yaml` and `stack-core.yaml` would be semantically identical — the negative
test would go red for *any* unresolvable package name rather than because of the seam, and would
measure nothing. Cairo is also unprovable without it, since cairo enters the build graph only
through `cfmm-scratchpad`.

### Naming trap discovered during this task

**The repository is `cfmm-vol-markets-spec`. The Haskell package inside it is `cfmm-scratchpad`.**
Almost certainly a leftover from `stack new cfmm-scratchpad`; the package `description` even reads
"Haskell twin of cfmm-vol-markets-spec". There is exactly one package in the repo.

Both names are correct, in different places — do not "fix" one into the other:

| Written in | Value |
|---|---|
| git URL in `extra-deps` | `https://github.com/d2p-finance/cfmm-vol-markets-spec.git` (the REPO) |
| `build-depends:` | `cfmm-scratchpad` (the PACKAGE) |
| seam-guard / negative-test greps | `cfmm-scratchpad` — must match what a violating `build-depends` would say |

### What `add-now` actually costs — measured, not assumed

- `src/Volatility/VolOrder.hs` and `src/Panoptic/NId.hs` — the only modules this bridge will call —
  import Chart **zero** times.
- **19 other modules** import `Graphics.Rendering.Chart`, spread across `Payoffs/`, `Greeks/`,
  `Pricing/`, `Liquidity/`, `Volatility/` and `Plotting/`.
- `Chart`, `Chart-cairo` and `colour` are declared at **package level**, so the library inherits
  them regardless of use.
- `library:` is a single stanza (`source-dirs: src`), so depending on the library compiles the
  WHOLE tree — all 19 Chart users included.

Net: we compile a plotting library, cairo and pango to reach a bit-packing function that needs
none of them. Accepted for Phase 1 — Task 5 measures the real number, which converts this from an
argument into evidence.

### Follow-up worth carrying (NOT blocking Phase 1)

Moving `Chart` / `Chart-cairo` / `colour` from package-level dependencies into the spec's
executable stanza would make the library plot-free and cut build time for every consumer. That is
a `JMSBPP` → `d2p-finance/cfmm-vol-markets-spec` PR. It also bears on the consumer's OPEN Phase 6
packaging decision, which currently frames cairo as an *executable* cost when it is in fact a
*library* cost — their "new exe vs mode on cfmm-scratchpad-exe" choice does not avoid cairo either
way.

---

## Spec pin — SUPERSEDED and repinned 2026-08-27

**The `## Spec pin` and `## D1` sections above are historically accurate but no longer the pin.**

Upstream merged two changes after this phase began, in response to the rename + cairo requests
sent from this session:

| SHA | Change |
|---|---|
| `5d1fb16bfecf685de501055e970c44166802f5c9` | package renamed `cfmm-scratchpad` → `cfmm-vol-markets-spec` |
| `f2736e058cfde1a03708f34772bfc2bb47c55cf6` | Chart/Chart-cairo/colour split out of the library |

**ACTIVE PIN:**

```yaml
extra-deps:
- git: https://github.com/d2p-finance/cfmm-vol-markets-spec.git
  commit: f2736e058cfde1a03708f34772bfc2bb47c55cf6
```

`build-depends: cfmm-vol-markets-spec` · binary is now `cfmm-vol-markets-spec-exe`.

### Verified independently, not taken on trust

- `f2736e0` is HEAD of `d2p-finance/cfmm-vol-markets-spec` ✓
- `package.yaml` and the generated `.cabal` both read `name: cfmm-vol-markets-spec` ✓
- Core library `build-depends` = `base >=4.7 && <5`, `mwc-random`, `vector` — **no Chart** ✓
- **0 of 58** `src/` modules import `Graphics.Rendering.Chart` ✓
- Plotting relocated to 22 modules under `plot/`, an *internal* sublibrary — invisible to external
  `build-depends`, so nothing for this bridge to configure ✓

### CORRECTION to the D1 cost analysis above — my measurement was wrong

The `## D1` section claims `VolOrder.hs` and `NId.hs` "import Chart zero times" and that 19
modules were affected. **Direct imports were the wrong instrument.** Verified against the old
commit:

- `src/Panoptic/NId.hs:26` → `import Pricing.PriceDeformation (uniswapMaxTick, uniswapMinTick)`,
  and `PriceDeformation` imports Chart. The bit-packing function was **two hops** from cairo.
- `src/Volatility/VolOrder.hs:21` → `import Payoffs.VolatilityCall`, which imports Chart.
- Transitive closure before the fix: **49 of 62 modules tainted, 13 clean** — not 19.

The remedy this session proposed (move the three deps into `executables:`) **would not have
compiled**: `src/TickPath.hs:77` exported `tickPathLayout :: TickPath -> Layout Double Double`,
a Chart type in a public signature beside the path math. Upstream's core/plot split was required.

**Lesson, and it is the same one this phase is built around:** a grep for direct imports is a
check that runs, produces output, and proves nothing about the property it appears to measure.
Reachability questions need transitive closure, not one hop.

### Measurement conditions to report back upstream

They asked for two things so the number is comparable:
1. State the environment — cold `~/.stack` or warm, container or host, GHC version (they are on 9.10.3).
2. **Keep libcairo/libpango dev-header PROVISIONING cost separate from COMPILE cost.** Their change
   removes only the second. If most of the old number was `apt-get install`, the win will be
   smaller than it looks.

Two-point comparison available on the canonical repo, package name identical on both sides, only
the split varying: **before `5d1fb16`** vs **after `f2736e0`**.

---

## Native deps

### The task's premise no longer holds — recorded, not repeated

`01-01-T4` instructs pointing out that cairo is a **package-level** dependency "so the library
inherits it — meaning anything that links the spec library needs these headers". **That was true at
`93fe3acf`. It is false at our pin `f2736e0`.** Executing the task as written would have taught a
fact that stopped being true two hours earlier — the same stale-rationale failure just corrected
upstream.

Verified at `f2736e0`, from the spec's own `package.yaml`:

```yaml
# Package-level deps are the PURE numeric core only.  Chart/Chart-cairo/colour
# drag in cairo/pango.  Downstream consumers (e.g. evm-spec-bridge, ...)
internal-libraries:
  plot:
    source-dirs: plot
    dependencies: [cfmm-vol-markets-spec, Chart, Chart-cairo, colour]
```

Chart/Chart-cairo/colour appear ONLY in the `plot` internal library and the executable. This
bridge depends on the core library only, so it is a **plot-free consumer**.

### Consequence: our cairo provisioning cost is ZERO

A plot-free consumer needs no cairo/pango **including dev headers**. Anything building the `plot`
sublibrary — the spec's exe or test suite — still does; that is not us.

**Therefore `libcairo2-dev libpango1.0-dev libglib2.0-dev` should be REMOVED from this project's
CI workflow (01-07) and Dockerfile (01-06).** Both currently install them, inherited from research
written against the old pin. Confirm empirically in Task 5: a clean build of the core library must
succeed with those headers absent.

### Name sets, recorded for completeness

- **Debian/CI/Docker (what the SPEC's own CI installs, still correct for anything building `plot`):**
  `libcairo2-dev libpango1.0-dev libglib2.0-dev pkg-config`
- **Arch (this host)**: `cairo pango glib2 pkgconf`

Local `pkg-config --modversion`, measured 2026-08-27:

| Library | Version |
|---|---|
| cairo | 1.18.4 |
| pango | 1.57.1 |
| glib-2.0 | 2.88.1 |

All three present on this host — which means the host CANNOT prove headers are unnecessary by
their absence. The honest test is a container without them, deferred to the image build (01-06).

---

## Spec compile probe — MEASURED (01-01-T5)

Two-point cold comparison. Same host, same snapshot, same package name both sides; only the
core/plot split varies.

**Conditions:** host (not container) · Arch Linux · 12 cores, `-j4` · GHC 9.10.3 (ghcup, on PATH,
`system-ghc: true`) · Stack 3.11.1 · LTS 24.55 · scratch `STACK_ROOT` per variant (genuinely cold)
· cairo 1.18.4 / pango 1.57.1 / glib 2.88.1 already present on the host.

| Variant | Commit | exit | seconds | STACK_ROOT | pkgs | Chart built? |
|---|---|---|---|---|---|---|
| before split | `5d1fb16` | 0 | **301** | 229M | 56 | **YES** |
| after split | `f2736e0` | 0 | **281** | 229M | 56 | **YES** |

Exit statuses captured via `set -o pipefail`, not read off a transcript.

### Result: the split delivers ~nothing to a git `extra-deps` consumer

`comm` on the two package sets differs only by the probe project's own name. Identical
`STACK_ROOT` size. 20 s = 6.6%, within cold-build noise.

**Cause: for a source dependency, Stack builds ALL components of the package — including internal
sublibraries.** Our probe depends only on the core library, yet `Chart-1.9.5` and
`Chart-cairo-1.9.4.1` were configured, compiled and registered, along with `lens` (85 modules),
`gtk2hs-buildtools`, `colour`, `data-default`, `operational`, `StateVar`, `old-locale`.

The split is still correct and would pay off for a consumer resolving the package from a package
database (Hackage/Stackage), where only the public library is installed. It is specifically the
**git-source-dependency path** that defeats it — which is the path this bridge uses.

### RETRACTION — the "provisioning cost is ZERO" claim in `## Native deps` above is WRONG

That section concluded a plot-free consumer "needs no cairo/pango including dev headers" and that
`libcairo2-dev` should be dropped from CI and the Dockerfile. The measurement refutes it:
`gtk2hs-buildtools` and `Chart-cairo` were built here, and they need cairo dev headers. The build
succeeded only because this host already has them — exactly the confound that section flagged
("the host CANNOT prove headers are unnecessary by their absence") and then failed to respect.

**Do NOT remove `libcairo2-dev libpango1.0-dev libglib2.0-dev pkg-config` from 01-06/01-07.**
Second time in one session that a conclusion about this dependency was drawn from evidence that
could not support it. The honest test remains a container without the headers — deferred to 01-06,
and now it is a real test rather than a formality.

### Open question this raises for the roadmap

If Chart compiles regardless via the source-dep path, the ~5-minute cold cost is unavoidable while
we consume the spec by git commit. Alternatives worth weighing later (NOT Phase 1): vendoring only
the modules needed, or consuming a published package rather than a git ref. Recorded, not acted on.

---

## Verdict

**GREEN — proceed to 01-02**

`cfmm-vol-markets-spec` at `f2736e0` **compiles** as a Stack git extra-dep. Exit 0, wall-clock
**281 s** cold on this host. Resolution is not compilation, and compilation is now proven — the
phase's highest-value unknown is retired at the cheapest possible moment, before any repository
structure exists.

This is the first measured build number in the project. Every estimate in the planning tree
before this line was folklore.

### Corroborated upstream with a stronger instrument

The spec's own session independently ran `stack build --dry-run` against `f2736e0` on a cold
scratch root, with a probe importing the same two modules. The **build plan** contains
`Chart-1.9.5`, `Chart-cairo-1.9.4.1`, `colour-2.3.7`, `gtk2hs-buildtools-0.13.12.0`, `lens-5.3.6`
— 57 packages planned.

`--dry-run` is the better instrument: it is Stack's *intent* before compilation, so it cannot be
caching, machine noise, or the 6.6% delta this session was unwilling to call signal. Two
independent methods, same conclusion. Worth remembering for later phases — when the question is
"what will be built", ask the planner, not the clock.

### Untested hypothesis recorded, not adopted

Upstream proposes that making `plot/` a separate **package** (not an internal sublibrary) would let
consumers write `subdirs: [core]` in the git extra-dep and never see the plot package — because
packages, not sublibraries, are the unit Stack selects. They explicitly declined to assert it
without testing, which is the right call given the day's record. **Not adopted, not depended on.**
If it is measured and works, revisit the pin.

Scratch build trees removed after recording. Retained: the two `.log` files and `.result` files are
NOT retained either — the numbers above are the artifact.

---

## Hosted CI smoke

Run 2026-08-27 during `01-01-T7` on a throwaway branch that never touched `develop`.

- Actions permissions — fork `JMSBPP/evm-spec-bridge`: `{"enabled":true,"allowed_actions":"all"}`
- Actions permissions — canonical `d2p-finance/evm-spec-bridge`: `{"enabled":true,"allowed_actions":"all"}`
- Run id `33125024351`, `status=completed`, **conclusion: success**
- Runner: `Linux runnervmgx7h7 6.17.0-1022-azure #22-Ubuntu SMP Mon Jul 27 17:24:03 UTC 2026 x86_64`
- Disk on `/`: `145G` total, **`87G` available** (41% used)

### What this retires, and what it does not

**Retires:** the `tao-plank-vault` hosted-CI billing concern PROJECT.md has carried since
initialization. A billing block presents as a workflow that queues and is immediately cancelled —
not as a settings flag being off. The settings flag was already verified in research; this is the
first evidence a runner *executes*. Combined with Actions being free for public repositories on
standard runners, and both repos being public, the concern is closed.

**Does not retire:** anything about the *self-hosted* runner belonging to `cfmm-vol-markets`. That
is a different machine with an unverified Haskell toolchain, and it is out of scope for this repo.

Headroom check: 87 GB free against a measured 229 MB Stack root plus a GHC bindist and
`.stack-work`. Not a constraint. Note this is the ephemeral hosted runner — the persistent
self-hosted case is where disk and leaked state actually bite, and that is Phase 10's problem.

Throwaway branch and workflow deleted locally and remotely after recording.

---

## Naming convention

Fixed in `01-02-T2`, before any file existed. One rule, applied seven times.

- Directory: `components/<kebab-name>/`
- Package: `evm-spec-bridge-<kebab-name>`
- Library source dir: `src`
- Module: `Bridge.<PascalName>`
- Generated cabal: `components/<kebab-name>/evm-spec-bridge-<kebab-name>.cabal`, **committed**

| dir | package | module |
|---|---|---|
| `protocol` | `evm-spec-bridge-protocol` | `Bridge.Protocol` |
| `abi-codec` | `evm-spec-bridge-abi-codec` | `Bridge.AbiCodec` |
| `jsonrpc` | `evm-spec-bridge-jsonrpc` | `Bridge.JsonRpc` |
| `registry` | `evm-spec-bridge-registry` | `Bridge.Registry` |
| `transport` | `evm-spec-bridge-transport` | `Bridge.Transport` |
| `codegen` | `evm-spec-bridge-codegen` | `Bridge.Codegen` |
| `cfmm-adapter` | `evm-spec-bridge-cfmm-adapter` | `Bridge.CfmmAdapter` |

**D2 decision: `seven-packages`.** Not a preference — `internal-libraries:` was ruled out because
the enclosing *package* carries an internal library's `build-depends`, so the spec-less config
would fail for the whole package regardless of which library owned the edge. The guard would be
permanently red and carry zero information. Stack 3.11.1 also cannot name an internal library as a
build target (`[S-8506]`).

**Anti-vacuity in the adapter.** `Bridge.CfmmAdapter` imports `Panoptic.NId (fourLegNumLegs)` and
uses it. A declared-but-unused dependency is one the toolchain could drop, which would let the
seam guard's positive control pass for the wrong reason.

---

## Seam guard — MEASURED both directions (01-03)

`stack --stack-yaml stack-core.yaml build --dry-run`

| Case | Tree state | exit | time |
|---|---|---|---|
| positive control (clean) | warm | 0 | **303–326 ms** |
| negative (protocol gains the spec) | warm | **1** | **302 ms** |
| negative (protocol gains the spec) | **cold scratch copy** | 1 | **118 818 ms** |

The guard fires and names all three things needed to act on it:

```
In the dependencies for evm-spec-bridge-protocol-0.1.0.0:
  * cfmm-vol-markets-spec needed, but no version is in the Stack configuration
    ... or an omission from the packages list in .../stack-core.yaml
The above is/are needed since evm-spec-bridge-protocol is a build target.
```

### The cold number is a finding, not noise — it changes the CI argument

RESEARCH.md measured **0.34 s** and 01-07's D9 rationale ("three jobs; fail-fast on the cheap one")
rests on it. That figure is a **warm** measurement. Reproduced here at 303 ms warm — but a cold tree
with no `.stack-work` and no hpack output takes **119 s**, a 350× difference.

**Every CI run starts from a fresh checkout.** So the seam job is only cheap if `.stack-work` is
restored from cache; otherwise it costs two minutes and is no longer meaningfully "fail-fast"
relative to the build job it precedes.

**Action for 01-07:** the cache step must be restored BEFORE the seam job (or the seam job must
carry its own cache restore), and D9's teaching must state warm-vs-cold rather than quoting 0.34 s
unqualified. Do not repeat the bare number — it is true only under a condition CI does not start in.

This is the same shape as the day's other corrections: a real measurement, taken under conditions
that differ from where it will be applied, generalised without stating the condition.

---

## Negative test + meta-check (01-04) — the guard is verified, not trusted

`scripts/seam-negative-test.sh`, three stages, scratch copy, never mutates the tree.

| Stage | Asserts | Result |
|---|---|---|
| CONTROL | clean tree resolves under `stack-core.yaml` | ✓ |
| NEGATIVE | injected edge fails with `S-4804` naming package, dependency and config file | ✓ |
| CONTRAST | the same tree DOES resolve under full `stack.yaml` | ✓ |

`PASS` in **3.8 s** warm. CONTRAST is what separates "the guard fired" from "the package name was
bad" — without it, a typo in the injected name would produce the same red.

### Meta-check: the negative test was made to FAIL, deliberately

Sabotage: gave `stack-core.yaml` the spec extra-dep, making it semantically identical to
`stack.yaml` — a guard that cannot fire.

```
FAIL(negative): guard did NOT fire on an injected spec dependency
exit=1
```

It failed **at the NEGATIVE stage**, which is the whole point: failing at CONTROL would have meant
a broken environment, not a vacuous guard. Restored afterwards with a **sha256 match** confirming
byte-identical restoration, then re-run: `PASS`.

Three layers, each verifying the one below: the guard catches violations; the negative test proves
the guard fires; the meta-check proves the negative test can fail. Only the third makes the first
two evidence rather than assertion.
