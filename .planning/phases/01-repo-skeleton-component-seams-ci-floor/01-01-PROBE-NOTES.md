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

---

## Container image (01-06) — MEASURED

### `ldd` on the real binary, before deciding the runtime contents

```
libm.so.6  libgmp.so.10  libc.so.6  ld-linux-x86-64.so.2
```

No cairo, no pango. Binary is 1 078 320 bytes. Runtime stage is therefore
`debian:bookworm-slim` + `libgmp10` + `ca-certificates` — decided from evidence, not from a list.

**`ldd` does NOT cover locale.** `debian:bookworm-slim` ships none, GHC falls back to ASCII, and
the first non-ASCII byte written dies with `commitBuffer: invalid argument`. Phase 1's ASCII
`--version` would pass and the bug would surface in Phase 4-5 as a transport failure.
`ENV LANG=C.UTF-8` added. Worth stating plainly: `ldd` tells you which shared libraries are needed,
not everything that is needed.

### Result

| Fact | Value |
|---|---|
| Image size | **129 MB** |
| Shipped binary runs | ✓ `evm-spec-bridge-transport 0.1.0.0` |
| cairo/pango in runtime | **0** |
| cairo/pango in builder base | **0** |
| Build succeeded with NO cairo dev headers installed | ✓ |

### What this does and does not establish

**Does:** Phase 1's image needs no cairo. It builds only `evm-spec-bridge-transport`, which does not
depend on `cfmm-adapter` and therefore never reaches `cfmm-vol-markets-spec` or its `plot`
sublibrary.

**Does NOT:** that consuming the spec needs no cairo. That is a different claim, and conflating the
two is precisely the error made earlier today in `## Native deps`. A separate probe builds
`evm-spec-bridge-cfmm-adapter` in a cairo-free container to answer it — see below.

`.dockerignore` excludes `**/package.yaml` deliberately: without it, `COPY . .` carries all seven in
and the image's own hpack regenerates every `.cabal`. The must-have "hpack never runs inside the
image" is false without that line, and the criterion "no COPY line names package.yaml" passes
vacuously because `COPY . .` names nothing.

### The provisioning question, answered properly

Separate probe: build `evm-spec-bridge-cfmm-adapter` (the one component reaching the spec) in
`haskell:9.10.3-bookworm` with **no cairo dev headers installed**.

**RESULT: FAILS.**

```
[S-7011] While building package cairo-0.13.12.0 ... Process exited with code: ExitFailure 1
```

The Haskell `cairo-0.13.12.0` binding cannot configure without the native headers.

| Build | cairo headers needed? |
|---|---|
| `evm-spec-bridge-transport` only (Phase 1 image) | **No** — never reaches the spec |
| `evm-spec-bridge-cfmm-adapter` (Phase 11) | **YES — build fails without them** |

**Conclusion, and it confirms the earlier retraction.** `libcairo2-dev libpango1.0-dev
libglib2.0-dev pkg-config` MUST stay in any CI job or image stage that builds the adapter. They are
correctly absent from Phase 1's image, which builds only the transport exe — but that is a
statement about Phase 1's scope, not about the spec.

Upstream's core/plot split therefore does not remove the header requirement for a git-extra-dep
consumer, consistent with the earlier finding that Stack builds all components of a source package.

### A check that lied, again — worth recording

Grepping the failed build log for `cairo\.h|pkg-config|libcairo` returned **0 matches**, on a build
that died of cairo. The failure surfaces as a `cairo-0.13.12.0` *package configure* failure, not as
a literal header error. Had the verdict been taken from that grep, the conclusion would have been
"no cairo problems" about a build that failed for exactly that reason. Caught only by reading the
tail. Fourth instance in one session of an instrument that could not detect the thing it was
pointed at.

---

## The gate caught a real bug on its first run (01-07)

CI run `33126472689`, the first execution of our own gate:

```
overall: failure
  seam:  success      <- the seam is sound
  build: failure      <- the code was not
```

```
CfmmAdapter.hs:15:17: error: [GHC-83865]
  Couldn't match expected type 'Int' with actual type 'PanopticTokenId -> Int'
  Probable cause: 'fourLegNumLegs' is applied to too few arguments
```

`fourLegNumLegs` is a FUNCTION, not a constant. The line existed to prove the spec was genuinely
linked, and it had a type error in it.

### Why nothing caught it for four plans — a structural gap, not a slip

`cfmm-adapter` was **never compiled** before this. `protocol` and `transport` were built locally;
the adapter's only coverage was the seam guard, which runs `stack build --dry-run`.

**A dry run resolves a BUILD PLAN. It does not compile code.** The guard was correctly reporting
that the adapter's dependencies are satisfiable — a true statement about resolvability that says
nothing about correctness. Its green was read as evidence of something it never measured.

This is the fifth instrument failure of the session and the only structural one: not a mistaken
grep, but a guard whose scope was quietly widened in the reader's head from "resolves" to "works".

**Two things follow, both already true in the CI file:**
1. The `build` job runs `stack build --test --pedantic` over ALL packages, so the adapter is
   compiled every run. That is what caught this.
2. The seam job and the build job are answering different questions and neither substitutes for the
   other. The seam job passing while the build job failed is the system working correctly.

Fixed by keeping the real signature (`specNumLegs :: PanopticTokenId -> Int`) rather than deleting
the import — a placeholder that no longer touches the spec would reintroduce the vacuity the
import exists to prevent.

### Confirmed for upstream, separately

The spike probe (two-package layout, `subdirs: [core]`, cairo-free container) failed on THIS bug —
meaning it got **past** cairo. `Chart`, `Chart-cairo`, `gtk2hs-buildtools` and `cairo-0.13` were all
absent from a build that previously died on `[S-7011] cairo-0.13.12.0`. Their restructure works in
a real build, not just in `--dry-run`.

---

## CI gate — MEASURED on a hosted runner (run 33126990346, all green)

| Step | Duration |
|---|---|
| `haskell-actions/setup@v2` | **106 s** |
| cairo/pango apt provisioning | **14 s** |
| Cold build (`--test --no-run-tests --pedantic`) | **302 s** |
| Warm rebuild, identical flags | **~0 s** |
| Tests + hpack drift gate | ~1 s |
| **seam job total** | **125 s** |
| **build job total** | **440 s** |

These replace every build-time estimate in the planning tree. The 302 s cold figure matches the
281 s measured locally on 12 cores — the hosted runner is slower but not dramatically so.

### Three findings

**1. The warm rebuild is instant, which validates the `--pedantic` fix.** Keeping the flag on both
builds means the configure hash is unchanged and Stack has nothing to do. Had it been dropped for
the second build, all seven local packages would have recompiled and a full recompile would have
been reported as an incremental number.

**2. Provisioning is 4.4% of the cost** (14 s apt vs 302 s compile). Upstream warned the win might
be mostly provisioning; it is the reverse. Almost all the cost is compilation, which is exactly
what their core/plot restructure removes.

**3. The seam job's fail-fast advantage is smaller than D9 assumed.** It took 125 s, of which 106 s
is `haskell-actions/setup` — a cost BOTH jobs pay. The guard itself is sub-second warm. Splitting
the job saves the 302 s build, not the 106 s setup, so the honest claim is "fails before the
expensive build" rather than "fails in seconds". D9's rationale holds, but for a smaller margin
than the 0.34 s figure implied.

---

## Upstream two-package spike — CLEAN BUILD, measured

Built `evm-spec-bridge-cfmm-adapter` in `haskell:9.10.3-bookworm` with **no cairo/pango dev
headers**, against the upstream spike commit `c528f60` using `subdirs: [core]`.

```
exit=0
Compiling Bridge.CfmmAdapter
Registering library for evm-spec-bridge-cfmm-adapter
SPIKE_SECONDS=144
```

| | current pin `f2736e0` (internal sublibrary) | spike `c528f60` (two packages) |
|---|---|---|
| external packages built | **56** | **1** (`cfmm-vol-markets-spec`) |
| Chart / Chart-cairo / gtk2hs / lens | present | **absent** |
| cairo dev headers required | **YES** — build fails without | **NO** — built without them |
| adapter compiled | n/a (died on cairo first) | **yes** |
| wall clock | 281 s host / 302 s CI | **144 s container** |

### What is and is not comparable

**Solid:** the package count (56 → 1) and the cairo requirement (required → not required). Both are
categorical, measured in the same container image, and immune to machine noise.

**Not a controlled comparison:** the 144 s is a container build of one target; the 281 s/302 s
baselines are a host build and a CI build of a different target set. Same order of magnitude, but
do not quote "144 vs 302" as a speedup — the environments differ. The package count is the honest
headline.

### Consequence for this project

If upstream restructures canonically, **Phase 11's adapter build stops needing cairo entirely** and
the `libcairo2-dev libpango1.0-dev libglib2.0-dev pkg-config` apt step added in 01-07 can be
removed. Until then it stays — measured as required at our current pin.

Nothing here is adopted: `c528f60` is an unmerged local branch on someone else's repo. Our pin
remains `f2736e0`.

### Two more instrument failures while producing this number

- Run 1 died with `unknown flag: --progress` (legacy builder). Greps reported "cairo matches: 0" and
  "adapter not compiled" — indistinguishable from a clean cairo-free success. Caught only by reading
  the exit code first.
- Run 2 died with `/bin/sh: set: Illegal option -o pipefail` — Docker `RUN` uses dash. `pipefail`
  was the fix for this session's FIRST blocker, and adding it here broke the build. Fixed with
  `SHELL ["/bin/bash", "-o", "pipefail", "-c"]`.

Both would have read as clean results from the greps alone. **Exit code before greps** is now the
standing rule in this phase.

---

## DIST-03 acceptance evidence

Branch protection applied to `d2p-finance/evm-spec-bridge:main` and **read back** rather than
trusted:

```json
{"contexts":["seam","build","image"],"enforce_admins":true,"pr_required":true,"strict":true}
```

All three gate jobs are required. Requiring only `build` would have left CFMM-01 (the seam) and
DIST-04 (the image) advisory — a PR with a red seam job would still merge.

`enforce_admins: true` matters here specifically: without it the rule does not bind the person most
able to bypass it, which is the only person likely to.

### The refusal — this IS the evidence, not a side effect

```
remote: - Changes must be made through a pull request.
remote: - 3 of 3 required status checks are expected.
 ! [remote rejected] develop -> main (protected branch hook declined)
exit=1
```

`upstream/main` commit count before: **1**. After: **1**. Nothing landed.

Run behind a hard precondition asserting `enforce_admins.enabled == true` AND a non-empty
`required_status_checks.contexts` first. Without that gate, a silently-failed protection PUT would
have made this push **succeed**, landing 20 commits of planning history directly on canonical —
the exact violation the task exists to prove impossible. "If it succeeds, stop" is too late: by
then it has happened, and undoing it requires a second forbidden push.

The `-F` vs `-f` distinction was load-bearing in the PUT: `-f` sends strings, and
`required_approving_review_count=0` as a string 422s. Both were flagged in review and both were
real.

---

## DIST-04 image publish — and a research claim that did NOT hold

Run `33127963832`, all three jobs green (`seam`, `build`, `image`). Every step of the image job
succeeded including `Build (always) and push (push events only)`.

Published, and pulled **anonymously with an empty `DOCKER_CONFIG`**:

```
ghcr.io/jmsbpp/evm-spec-bridge:develop                    129MB
ghcr.io/jmsbpp/evm-spec-bridge:sha-b3c5621...             129MB
$ docker run --rm ghcr.io/jmsbpp/evm-spec-bridge:develop --version
evm-spec-bridge-transport 0.1.0.0
```

### The predicted manual gate did not materialise

RESEARCH.md and plan `01-08-T6` both state that a newly published GHCR package is **private by
default**, requiring a one-time irreversible manual UI flip that no workflow can perform. It was
carried as the single human-action checkpoint in Phase 1.

**Observed: the package was public immediately.** Two anonymous pulls, fresh empty `DOCKER_CONFIG`
directories confirmed to contain no credentials, both succeeded.

I do not know the mechanism and am not going to invent one — plausibly GHCR now inherits visibility
from a public linked repository when published via `GITHUB_TOKEN` with
`org.opencontainers.image.source` set, but that is a guess and is recorded as such. What is
measured is the outcome, not the cause.

The claim was sound research (GitHub's own docs say private-by-default) and it was simply not true
for this configuration. Worth noting the asymmetry: this is a predicted blocker that failed to
appear, which is the *harmless* direction. Had it gone the other way — assuming public and finding
private — the consumer's first pull would have 403'd with no obvious cause.

### The 404 that meant something else entirely

`gh api user/packages/container/evm-spec-bridge` first returned **404 Package not found**, which
reads as "nothing was published". After refreshing scope it returned **403: You need at least
read:packages scope**. The 404 was an authorization artefact, not a statement about existence.

Had the verdict been taken from that 404, the conclusion would have been "the image job silently
failed to publish" — about a package that was published, public, and pullable. The unambiguous test
was the credential-free `docker pull`, which asks the question directly instead of asking GitHub's
API a question it was not authorized to answer.
