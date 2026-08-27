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
