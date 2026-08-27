# Phase 1: Repo Skeleton, Component Seams, CI Floor - Research

**Researched:** 2026-08-27
**Domain:** Multi-package Haskell Stack/hpack project layout, build-plan-level component seam enforcement, GitHub Actions CI on a fork→canonical topology, multi-stage Docker + GHCR publishing
**Confidence:** HIGH on the seam mechanism, the toolchain versions, the Docker base images and the fork/GHCR permission model (all verified by local execution or official sources). MEDIUM on CI wall-clock numbers (unmeasured by construction — measuring them is a Phase 1 deliverable).

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Execution model — GOVERNING, applies to this phase and beyond**

- **Plans are executed INLINE, in conversation — not delegated to background executor agents.**
  The user is present for the work.
- Execution carries **heavy user intervention**: stop to ask, surface decision points rather
  than silently resolving them, explain the reasoning as the work happens.
- **The phase is explicitly a learning exercise for the user**, not only a deliverable. A step
  that produces the right artifact while leaving the user unable to explain it has half-failed.
- Consequence for the planner: prefer more, smaller tasks over few large ones; put explicit
  teaching/checkpoint moments where a non-obvious choice is made; never bundle several
  independent decisions into one task.
- `plan_checker` stays disabled — the user is the check.

**Component structure**

- **Seven components exist from day one**: `protocol`, `abi-codec`, `jsonrpc`, `registry`,
  `transport`, `codegen` (core) plus `cfmm-adapter`.
- Rationale: every later phase drops into a component that already exists, and the dependency
  graph is declared before anyone can accidentally violate it. Accepts seven near-empty stanzas
  as the cost.
- `cfmm-adapter` is the ONLY component permitted to depend on the spec package
  (`cfmm-scratchpad`).

**Build system**

- **Stack + hpack**, snapshot matching the spec's exactly (LTS 24.55).
- Spec arrives as a Stack `extra-deps` git entry pinned to a commit — not a submodule.
- **The generated `.cabal` IS committed**, matching the spec repo's convention, so consumers can
  build without hpack installed. CI runs hpack and fails on a diff — the same
  `git diff --exit-code` treatment the generated Solidity gets later, so both generated-artifact
  gates are one habit rather than two.

**Seam enforcement**

- Enforced by a **spec-less Stack configuration** (`stack-core.yaml` or equivalent) that omits
  the `cfmm-scratchpad` extra-dep entirely and builds only the six core components.
- Mechanism: a core component that gains a spec dependency **fails to resolve** — a hard,
  unambiguous error, not a slow build or an inferred signal.
- This was chosen deliberately over "build core targets only" against the normal config, which
  would NOT fail: Stack would simply resolve the spec from `extra-deps` and build it. That guard
  would have been decorative.
- **A negative test proves the guard fires**: deliberately add the forbidden edge in a scratch
  copy and assert the build goes red. A guard nobody has seen fire is a guard being trusted, not
  verified — and untested guards producing false greens is this project's central failure mode.

**CI gate**

- Runs on **push AND pull request** (deliberately broader than the consumer's PR-only gate, so
  work in a `feat/*` worktree is validated while it happens rather than at promotion time).
- Green requires: every component compiles, the seam guard passes, the negative test confirms
  the guard fires, and the hpack drift check is clean.
- **Test framework is `tasty`** — a test scaffold exists and runs from Phase 1 so later phases
  add cases rather than also wiring up a runner. (This overrides the `hspec` recommendation in
  `.planning/research/STACK.md`.)
- **Cold and warm build times are printed and recorded** by a CI step, with the numbers written
  into the phase summary. All current build-time estimates are unmeasured; this converts folklore
  into a number.

**Distribution — Docker**

- **The container image is the artifact.** The bridge is built and published as an image by our
  gate (GHCR, public, anonymous pull). The consumer runs it rather than building it.
- This **replaces the self-hosted-runner probe**.
- **Phase 1 builds and publishes a minimal multi-stage image** carrying a trivial binary — proving
  GHC-in-a-container, cairo resolution and the GHCR publish while there is almost no code, so a
  failure is cheap to diagnose.
- `docker-hub` MCP was unavailable this session; GHCR is the registry.

**Repository topology**

- `d2p-finance/evm-spec-bridge` canonical, receives PRs only. `JMSBPP/evm-spec-bridge` is the
  fork; `develop` is the integration branch and the fork's default.
- One git worktree per plan on a `feat/*` branch.
- Both repos exist and are wired; `develop` carries the planning history. Upstream `main` holds
  only its initialization commit.

### Claude's Discretion

- Exact directory naming under each component and module layout within them.
- Dockerfile base image choice and multi-stage split specifics.
- CI job decomposition (one job vs several) provided the green conditions above hold.
- Whether a `justfile`/`Makefile` wraps the common commands.

### Deferred Ideas (OUT OF SCOPE)

- **Propagating the Docker decision into ROADMAP.md phases 6 and 10** and the affected
  requirements (SRV-01, SRV-08, DIST-05, DIST-01). Should happen before Phase 6 is planned.
- Splitting the core into finer components than the six chosen, or merging them — revisit when
  real modules exist and boundaries are known from code rather than predicted.
- `hlint` / formatter checks in the gate — considered and deferred; another thing that can go red
  for reasons unrelated to correctness, on a gate that runs on every push.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| **CFMM-01** | `cfmm-adapter` is a separate component, and no core component `build-depends` on the spec package `cfmm-scratchpad` — enforced by a build that fails if that edge is added | §"Verified Mechanisms" M1–M4: the spec-less-config guard is **verified working locally** with a hard `[S-4804]` error in 0.34s; §"Why not `internal-libraries`" proves the seven-package layout is *required*, not merely preferred; §"Code Examples" gives `stack.yaml` / `stack-core.yaml` / the negative-test script |
| **DIST-03** | Changes reach `d2p-finance/evm-spec-bridge` only via PR from the `JMSBPP` fork | §"Repository topology — verified state": both repos exist, Actions enabled on both, fork default `develop`, canonical default `main`; §"Branch protection & the PR path" gives the concrete settings and the `gh` commands |
| **DIST-04** | An own CI gate on hosted runners, triggered on push AND pull request, builds every component, the server, the generated Solidity, and the container image, and publishes the image to GHCR | §"The fork PR / GHCR permission problem" resolves the blocker (build always, publish on `push` only); §"Code Examples" gives the workflow; §"Build-time measurement" gives the cold/warm recording step. *Scope note: "the server" and "the generated Solidity" do not exist in Phase 1 — Phase 1 delivers the gate structure they later slot into.* |
</phase_requirements>

---

## Summary

Every load-bearing mechanism this phase depends on was **executed locally against Stack 3.11.1 and
the real LTS 24.55 snapshot**, not inferred. The headline result: the seam guard works exactly as
CONTEXT.md predicted, and it is far cheaper than anyone assumed. A core component that gains a
`cfmm-scratchpad` dependency causes `stack --stack-yaml stack-core.yaml build --dry-run` to fail
with `Error: [S-4804] Stack failed to construct a build plan`, naming the offending package, the
offending dependency, and the offending config file — in **0.34 seconds**, before a single module is
compiled. The same tree against the full `stack.yaml` resolves happily (it prints
`evm-spec-bridge-protocol ... after: cfmm-scratchpad`), which empirically confirms CONTEXT.md's
reason for rejecting the "build core targets only" alternative: that guard would have been
decorative.

Two design constraints fall out of the experiments that the planner must honour. First,
**`internal-libraries:` is incompatible with the locked seam mechanism** — verified: `packages:` in
`stack.yaml` selects at *package* granularity, an internal library's `build-depends` is carried by
its enclosing package, and Stack 3.11.1 cannot even name an internal library as a build target
(`[S-8506] Stack failed to parse the target(s)`). Seven separate packages is therefore the only
layout that expresses the seam. Second, **the seam guard must be `--dry-run`**, not a real build:
plan construction is where the error occurs, so `--dry-run` gets the full signal for free and avoids
compiling the core twice under two different Stack configurations.

Three external facts shape the CI and Docker work. `stack.yaml.lock` **does** record the git
extra-dep's resolved commit *and* a `pantry-tree` sha256 (verified against the real
`JMSBPP/cfmm-vol-markets-spec` repo), which retires PITFALLS.md's "a spec bump invalidates the build
without changing any lock file" warning — that warning was written against `cabal.project.freeze` +
submodules and does not transfer to Stack extra-deps. `haskell:9.10.3-bookworm` matches LTS 24.55's
compiler exactly (`resolver: compiler: ghc-9.10.3` in the snapshot) and already ships Stack with
`system-ghc: true`, making it the obvious builder base at 0.67 GB versus `fpco/stack-build:lts-24.55`
at 6.24 GB. And a GHCR package pushed from a workflow **defaults to private** and must be made public
by a one-time, irreversible manual UI action — an anonymous-pull requirement cannot be satisfied by
the workflow alone.

**Primary recommendation:** Seven `package.yaml`-per-directory Stack packages under `components/`,
two project configs (`stack.yaml` with the spec extra-dep, `stack-core.yaml` without it), a
`--dry-run`-based seam guard plus a scratch-copy negative test that asserts *both* the control-green
and the violation-red with an `S-4804` grep, an hpack drift gate keyed on a **pinned Stack version**,
and a CI workflow that always *builds* the image but only *pushes* it on `push` events — because a
fork PR's `GITHUB_TOKEN` cannot be granted `packages: write`.

---

## Verified Mechanisms

Everything in this section was **run on this machine on 2026-08-27** with `stack 3.11.1`
(`hpack-0.39.6`), GHC 9.10.3 from ghcup, against the live LTS 24.55 snapshot. Reproduction commands
are given so the user can re-run each during inline execution — several of these are the best
teaching moments in the phase.

### M0 — LTS 24.55 pins GHC 9.10.3

```bash
curl -sS https://raw.githubusercontent.com/commercialhaskell/stackage-snapshots/master/lts/24/55.yaml -o /tmp/lts2455.yaml
tail -5 /tmp/lts2455.yaml
```

```
    sha256: 033cef067d7a48b195b3aafaebff3a75e8779bac04981d7ccbabf70f3b3fafdc
    size: 6285
publish-time: 2026-08-16T10:03:09.478790353Z
resolver:
  compiler: ghc-9.10.3
```

Snapshot file: 732456 bytes, sha256 `1c2140555bdf61c30a893b3ec1033987d01eda75ce82a1dda033e8fb6f8b322c`
(matches the spec's committed `stack.yaml.lock` exactly). **Confidence: HIGH.**

Consequence: the Docker builder base and the CI GHC are both determined, not chosen —
`ghc-9.10.3`.

### M1 — `--stack-yaml` selects an alternate project config

`--stack-yaml` / `-w` is a **global** Stack option (confirmed in `stack --help`), so it precedes the
subcommand. `STACK_YAML` as an environment variable is the documented equivalent.

```bash
stack --stack-yaml stack-core.yaml build --dry-run
```

Against a clean tree (protocol has no spec dependency):

```
No packages would be unregistered.

Would build:
* evm-spec-bridge-protocol-0.1.0.0: database=local, source=/tmp/seamtest/components/protocol/

No executables to be installed.
```

Exit 0. **Confidence: HIGH — executed.**

### M2 — THE LOAD-BEARING RESULT: the seam guard fires, hard and legibly

The forbidden edge was added to a *core* package's `package.yaml`:

```yaml
name: evm-spec-bridge-protocol
dependencies:
- base >= 4.7 && < 5
- cfmm-scratchpad     # <-- the violation
```

Then, against the spec-less config:

```
Error: [S-4804]
       Stack failed to construct a build plan.

       While constructing the build plan, Stack encountered the following errors. The 'Stack
       configuration' refers to the set of package versions specified by the snapshot (after any
       dropped packages, or pruned GHC boot packages; if a boot package is replaced, Stack prunes
       all other such packages that depend on it) and any extra-deps:

       In the dependencies for evm-spec-bridge-protocol-0.1.0.0:
         * cfmm-scratchpad needed, but no version is in the Stack configuration (no matching package
           and version found. Perhaps there is an error in the specification of a package's
           dependencies or build-tools (Hpack) or build-depends, build-tools or build-tool-depends
           (Cabal file) or an omission from the packages list in /tmp/seamtest/stack-core.yaml
           (project-level configuration).)
       The above is/are needed since evm-spec-bridge-protocol is a build target.
```

Exit code **1**. **Confidence: HIGH — executed.**

Three properties worth teaching from this output:
1. It names the **offending package** (`evm-spec-bridge-protocol`), the **offending dependency**
   (`cfmm-scratchpad`) and the **offending config** (`stack-core.yaml`). This is the "fails for a
   reason a reader can *see*, not infer" property CONTEXT.md asked for.
2. It carries a **stable machine-greppable error code** `[S-4804]`. That is what makes the negative
   test able to assert *this* failure rather than *any* failure.
3. It happens at **plan construction**, before compilation. The guard costs no build time.

### M3 — the rejected alternative really is decorative

Same violated tree, but against the *full* `stack.yaml` (which has the spec in `extra-deps`):

```
Would build:
* cfmm-scratchpad-0.1.0.0: database=local, source=/tmp/seamtest/fakespec/
* evm-spec-bridge-cfmm-adapter-0.1.0.0: ... after: cfmm-scratchpad-0.1.0.0 and evm-spec-bridge-protocol-0.1.0.0.
* evm-spec-bridge-protocol-0.1.0.0: ... after: cfmm-scratchpad-0.1.0.0.
```

Exit **0**. Stack silently resolves the forbidden edge and reorders the build. CONTEXT.md's
reasoning is empirically confirmed. **Confidence: HIGH — executed.**

### M4 — the guard is essentially free

```
$ time stack --stack-yaml stack-core.yaml build --dry-run
real    0m0.334s
```

(and 0.338s for the violated scratch copy). Both with a warm Stack root. **Confidence: HIGH —
measured, though on a warm local Stack root; on a CI runner add snapshot/compiler setup time on a
cache miss.**

Planning consequence: the seam guard can be **its own fail-fast CI job placed before the build**,
costing seconds, not a step bolted onto a 20-minute build.

### M5 — `internal-libraries` cannot express the seam (Q1 answered decisively)

hpack *does* support `internal-libraries:` — verified, it emits `library <name>` stanzas into one
`.cabal`:

```
library abi-codec
  exposed-modules:
      AbiCodec
  hs-source-dirs:
      abi-codec
  build-depends:
      base >=4.7 && <5
    , protocol
```

But the seam breaks in two independent ways:

**(a) The dependency is carried by the enclosing package.** With `cfmm-adapter` as an internal
library depending on `cfmm-scratchpad`, the spec-less config fails for the *whole package*:

```
In the dependencies for evm-spec-bridge-0.1.0.0:
  * cfmm-scratchpad needed, but no version is in the Stack configuration ...
The above is/are needed since evm-spec-bridge is a build target.
```

The guard would be permanently red and could not distinguish "a core component gained the edge"
from "the adapter has its legitimate edge". It would carry zero information.

**(b) Stack cannot target an internal library.**

```
$ stack build --dry-run evm-spec-bridge:lib:protocol
Error: [S-8506]
       Stack failed to parse the target(s).
           Directory not found: evm-spec-bridge:lib:protocol.
```

So there is no escape hatch via targeting either. **Confidence: HIGH — both executed.**

**Verdict: seven separate packages, each with its own `package.yaml` and committed `.cabal`.** This
is not a style preference; it is what the locked seam mechanism requires.

### M6 — `stack build` regenerates `.cabal` and silently overwrites hand edits

A `DRIFTMARKER` was injected directly into a generated `.cabal`. After
`stack build --dry-run`, `grep -c DRIFTMARKER` returned **0** — hpack (bundled in Stack) regenerated
the file with no `--force` and no complaint. Modern hpack no longer writes the `-- hash:` line that
used to make it refuse.

Consequence: the drift gate is exactly

```bash
stack build --dry-run            # regenerates every .cabal for packages in this config
git diff --exit-code -- '**/*.cabal'
```

**Confidence: HIGH — executed.** Note `--dry-run` under `stack.yaml` (the full config) covers all
seven packages; `stack-core.yaml` would only regenerate the six it lists.

### M7 — `stack.yaml.lock` records the git extra-dep's commit (Q7 answered)

Run against the **real** spec repo:

```yaml
# stack.yaml
extra-deps:
- git: https://github.com/JMSBPP/cfmm-vol-markets-spec.git
  commit: 93fe3acfd2aa13dd28b54d5d44022dc9c10b6341
```

Produced `stack.yaml.lock`:

```yaml
packages:
- completed:
    commit: 93fe3acfd2aa13dd28b54d5d44022dc9c10b6341
    git: https://github.com/JMSBPP/cfmm-vol-markets-spec.git
    name: cfmm-scratchpad
    pantry-tree:
      sha256: 0790ed5df73b157db9b5012cad3154371c1e0d7a7f00237df4176373e748e27a
      size: 17428
    version: 0.1.0.0
  original:
    commit: 93fe3acfd2aa13dd28b54d5d44022dc9c10b6341
    git: https://github.com/JMSBPP/cfmm-vol-markets-spec.git
snapshots:
- completed:
    sha256: 1c2140555bdf61c30a893b3ec1033987d01eda75ce82a1dda033e8fb6f8b322c
    size: 732456
    url: https://raw.githubusercontent.com/commercialhaskell/stackage-snapshots/master/lts/24/55.yaml
```

**Confidence: HIGH — executed against the live repo.**

This is a **correction to PITFALLS.md #12**, which warned that "a spec submodule bump changes nothing
in the freeze file while invalidating the build". That is true for `cabal.project.freeze` +
submodules. It is **false** for Stack extra-deps: the commit appears in `stack.yaml` (you type it
there) *and* in `stack.yaml.lock` (twice), plus a content hash of the resolved tree. So
`hashFiles('stack.yaml', 'stack.yaml.lock')` is a **complete and correct** cache-key input for a spec
bump. Also usefully recorded here: the real spec HEAD as of research time is
`93fe3acfd2aa13dd28b54d5d44022dc9c10b6341`, package `cfmm-scratchpad-0.1.0.0`.

### M8 — Stack builds from a committed `.cabal` with no `package.yaml` present

All `package.yaml` files were deleted from a copy of the project tree, leaving only the generated
`.cabal` files; `stack build --dry-run` produced the identical plan, exit 0.
**Confidence: HIGH — executed.**

Consequence for the Dockerfile: the image can `COPY` only `stack.yaml`, `stack.yaml.lock` and the
`*.cabal` files for its dependency layer. hpack then never runs inside the image, so the image's
Stack version (3.3.1 in `haskell:9.10.3-bookworm`) is irrelevant to the drift gate. This kills an
entire class of confusing failure.

### M9 — a GHC 9.10.3 binary's runtime shared-library set (Q5 answered)

```
$ ghc-9.10.3 -O0 -threaded -rtsopts -o hellobin hello.hs && ldd hellobin
	linux-vdso.so.1
	libm.so.6 => /usr/lib/libm.so.6
	libgmp.so.10 => /usr/lib/libgmp.so.10
	libc.so.6 => /usr/lib/libc.so.6
	/lib64/ld-linux-x86-64.so.2
```

**Confidence: HIGH — measured.** `libffi` is statically linked by GHC 9.10.3; no `libtinfo`, no
`zlib` for a trivial binary.

So the Phase 1 runtime stage needs `debian:bookworm-slim` + `libgmp10` (+ `ca-certificates` if
anything ever speaks TLS). **Cairo/pango are needed at BUILD time only**, because the builder stage
compiles `cfmm-adapter` → `cfmm-scratchpad` → `Chart-cairo`. They are needed at *runtime* only once
the shipped executable actually links the adapter — which is Phase 11, not Phase 1. See "Decision
Points" D5.

### M10 — repository and Actions state (verified via `gh`)

| Fact | Value |
|---|---|
| `JMSBPP/evm-spec-bridge` | PUBLIC, `isFork: true`, parent `d2p-finance/evm-spec-bridge`, default branch `develop` |
| `d2p-finance/evm-spec-bridge` | PUBLIC, not a fork, default branch `main` |
| Actions on fork | `{"enabled":true,"allowed_actions":"all"}` — already enabled, no manual step needed |
| Actions on canonical | `{"enabled":true,"allowed_actions":"all"}` |
| Workflows present | `{"total_count":0}` on the fork — greenfield |
| Local remotes | `origin` → JMSBPP fork, `upstream` → d2p-finance; on branch `develop` |

**Confidence: HIGH — queried live.** Note this contradicts the usual "forks have Actions disabled by
default" assumption: it is already on here, so *do not* plan a task to enable it — plan a task to
*verify* it stayed on.

---

## Standard Stack

All versions below are read directly from the **pinned LTS 24.55 snapshot file**, so they are not
"latest on Hackage" guesses — they are what this project will actually resolve.

### Core toolchain

| Component | Version | Source of truth | Why |
|---|---|---|---|
| Stackage snapshot | `lts/24/55.yaml` by URL | spec's `stack.yaml` | PROJECT.md constraint: must match the spec exactly |
| GHC | **9.10.3** | `resolver.compiler` in the snapshot | Inherited, not chosen |
| Stack | **3.11.1** (local), pin the same in CI | `stack --version` | Bundles `hpack-0.39.6`; see Pitfall 2 |
| hpack | **0.39.6** (bundled in Stack 3.11.1) | `stack --version` | Never install standalone — use Stack's |

### Test stack (from LTS 24.55)

| Package | Version in LTS 24.55 | Purpose | Phase 1? |
|---|---|---|---|
| `tasty` | **1.5.4** | The runner (locked decision) | Yes |
| `tasty-hunit` | **0.10.2** | Unit assertions | Yes |
| `tasty-quickcheck` | **0.11.1** | Property tests | Add now, used Phase 3+ |
| `tasty-golden` | **2.3.6** | Golden files | Not yet — Phase 8 (GEN-06) |
| `tasty-hedgehog` | **1.4.0.2** | Alternative property lib | Not recommended — pick one |
| `tasty-discover` | **5.0.2** | Auto test discovery | **Not recommended** — see Pitfall 6 |
| `tasty-wai` | **0.1.2.0** | WAI handler testing | Not yet — Phase 4/5 |
| `tasty-expected-failure` | **0.12.3** | `expectFail` combinator | Not yet |

### Docker base images (verified against Docker Hub registry API, 2026-08-27)

| Image | Compressed size | Last updated | Verdict |
|---|---|---|---|
| **`haskell:9.10.3-bookworm`** | **0.67 GB** | 2026-08-25 | **RECOMMENDED builder.** Exact GHC match. Ships Stack 3.3.1, cabal 3.14.1.1, and pre-sets `system-ghc: true` / `install-ghc: false` |
| `haskell:9.10.3-slim-bookworm` | 0.62 GB | 2026-08-25 | Marginal saving, fewer build tools. Not worth the risk |
| `fpco/stack-build:lts-24.55` | 6.24 GB | 2026-08-16 | Exact snapshot match with deps prebuilt, but 10× the pull. Fallback only if cairo proves painful |
| `fpco/stack-build-small:lts-24.55` | 1.47 GB | 2026-08-16 | System libs, no prebuilt packages. Middle option |
| **`debian:bookworm-slim`** | **0.03 GB** | 2026-08-25 | **RECOMMENDED runtime stage** |

`haskell:9.10.3-bookworm` apt contents (from the official
[docker-haskell Dockerfile](https://github.com/haskell/docker-haskell)): `ca-certificates curl
dpkg-dev git gcc gnupg g++ libc6-dev libffi-dev libgmp-dev libnuma-dev libtinfo-dev make netbase
xz-utils zlib1g-dev`. **Missing and must be added for the spec:** `libcairo2-dev libpango1.0-dev
libglib2.0-dev pkg-config` — the exact set the spec repo's own CI installs.

### Alternatives considered

| Instead of | Could use | Tradeoff |
|---|---|---|
| Seven packages | One package + `internal-libraries` | **Ruled out by M5** — cannot express the seam. Would have saved six `package.yaml`/`.cabal` pairs |
| Seven packages | Two packages (core w/ internal libs + adapter) | *Would* work for the seam, and halves boilerplate. But internal libs are not addressable as build targets (M5b), so per-component `stack build`/`stack test` and per-component pedantic flags become impossible, and the six-way graph the roadmap wants to declare collapses into one stanza. Rejected, but this is the strongest alternative and worth explaining to the user |
| `haskell:9.10.3-bookworm` | `fpco/stack-build:lts-24.55` | Trades a 6.24 GB pull for zero apt fiddling and a warm package DB. Revisit only if the cairo apt step proves flaky |
| `tasty-discover` | Explicit `Main.hs` | Discovery magic vs a one-line edit per new module. **Explicit wins here** — see Pitfall 6 |
| `actions/cache` for Stack | `docker/build-push-action` GHA cache only | Would mean the fast gate has to build a container. Keep them separate |

---

## Architecture Patterns

### Recommended repository structure

```
evm-spec-bridge/
├── stack.yaml                 # full config: 7 packages + cfmm-scratchpad extra-dep
├── stack.yaml.lock            # committed; records the spec commit + pantry tree hash (M7)
├── stack-core.yaml            # SEAM GUARD: 6 packages, extra-deps: []  — no lock file needed
├── components/
│   ├── protocol/
│   │   ├── package.yaml
│   │   ├── evm-spec-bridge-protocol.cabal      # generated, COMMITTED
│   │   ├── src/Bridge/Protocol.hs
│   │   └── test/Main.hs
│   ├── abi-codec/
│   ├── jsonrpc/
│   ├── registry/
│   ├── transport/
│   ├── codegen/
│   └── cfmm-adapter/          # the ONLY one that may name cfmm-scratchpad
├── app/                       # or components/bridge-server/ — the trivial Phase 1 exe
├── scripts/
│   ├── seam-guard.sh          # positive control
│   └── seam-negative-test.sh  # proves the guard fires
├── docker/Dockerfile
└── .github/workflows/ci.yml
```

**Naming (discretion, but recommend):** package names `evm-spec-bridge-<component>`; module
namespace `Bridge.<Component>`. Rationale to explain to the user: Haskell package names are global
within a build plan, so `protocol` alone is a collision hazard against Hackage; the `Bridge.` module
prefix keeps `import` sites self-describing.

### Pattern 1: Two project configs, one source tree

**What:** `stack.yaml` is the real build; `stack-core.yaml` is a *proposition* about the dependency
graph expressed as a resolvable configuration.

**Why it works (the teaching point):** Stack constructs a build plan from `snapshot ∪ extra-deps ∪
packages`. If a package in `packages:` names a dependency outside that set, planning fails —
*structurally*, before compilation, with no way to opt out. So "the core does not depend on the spec"
stops being a convention and becomes a proposition the build system decides.

**When to use:** any time a forbidden edge is expressible as "this dependency is not in scope".

**Files:**

```yaml
# stack.yaml — the real build
snapshot:
  url: https://raw.githubusercontent.com/commercialhaskell/stackage-snapshots/master/lts/24/55.yaml
packages:
- components/protocol
- components/abi-codec
- components/jsonrpc
- components/registry
- components/transport
- components/codegen
- components/cfmm-adapter
extra-deps:
- git: https://github.com/JMSBPP/cfmm-vol-markets-spec.git
  commit: 93fe3acfd2aa13dd28b54d5d44022dc9c10b6341   # confirm at execution time
```

```yaml
# stack-core.yaml — the seam guard. The absence of extra-deps IS the guard.
#
# Deliberately omits `components/cfmm-adapter` and the cfmm-scratchpad extra-dep.
# A core component that gains a spec dependency fails to RESOLVE here:
#   Error: [S-4804] Stack failed to construct a build plan.
# Verified 2026-08-27. See scripts/seam-negative-test.sh, which proves this fires.
snapshot:
  url: https://raw.githubusercontent.com/commercialhaskell/stackage-snapshots/master/lts/24/55.yaml
packages:
- components/protocol
- components/abi-codec
- components/jsonrpc
- components/registry
- components/transport
- components/codegen
extra-deps: []
```

### Pattern 2: `package.yaml` skeleton for a core component

```yaml
# components/protocol/package.yaml
name:        evm-spec-bridge-protocol
version:     0.1.0.0
synopsis:    Wire protocol types for the evm-spec-bridge oracle
license:     BSD-3-Clause
author:      JMSBPP
maintainer:  juan.serranotmf@gmail.com
copyright:   2026 JMSBPP

# Mirrors the spec repo's flag set so both trees fail on the same things.
ghc-options:
- -Wall
- -Wcompat
- -Widentities
- -Wincomplete-record-updates
- -Wincomplete-uni-patterns
- -Wmissing-export-lists
- -Wmissing-home-modules
- -Wpartial-fields
- -Wredundant-constraints

dependencies:
- base >= 4.7 && < 5

library:
  source-dirs: src

tests:
  protocol-test:
    main:        Main.hs
    source-dirs: test
    ghc-options:
    - -threaded
    - -rtsopts
    - -with-rtsopts=-N
    dependencies:
    - evm-spec-bridge-protocol
    - tasty
    - tasty-hunit
```

And the one component allowed the edge:

```yaml
# components/cfmm-adapter/package.yaml
name:    evm-spec-bridge-cfmm-adapter
version: 0.1.0.0
dependencies:
- base >= 4.7 && < 5
- evm-spec-bridge-protocol
# The single permitted edge to the outside world. CFMM-01. Protected by
# stack-core.yaml, which omits this package AND the extra-dep that resolves it.
- cfmm-scratchpad
library:
  source-dirs: src
```

### Pattern 3: hpack drift gate

```bash
stack build --dry-run                      # regenerates all seven .cabal files (M6)
git diff --exit-code -- '**/*.cabal'       # red on any drift
```

Uses the *full* config so all seven packages are covered. Requires a **pinned Stack version** in CI
(Pitfall 2).

### Anti-patterns to avoid

- **`internal-libraries:` for the six core components** — verified incompatible with the seam (M5).
- **Making the seam guard a real `stack build`** — different `extra-deps` means a different Stack
  install hash, so the core would be compiled twice per CI run for zero extra signal. `--dry-run`
  gets the entire signal in 0.34 s.
- **Putting `system-ghc: true` in the committed `stack.yaml`** — it is correct inside the Docker
  builder (where GHC 9.10.3 is guaranteed) and wrong for a contributor whose local GHC is 9.6.
  Pass `--system-ghc --no-install-ghc` on the command line in the Dockerfile instead; both are
  global Stack flags (verified in `stack --help`).
- **Asserting the negative test on exit code alone** — see Pitfall 1.
- **Running the negative test as a `tasty` case** — see Pitfall 3.
- **`ghcr.io/${{ github.repository }}`** — see Pitfall 4.

---

## The Fork PR / GHCR Permission Problem (Q6)

This was the most likely blocker and it is real. Here is the resolved picture.

### What the docs say

> "You can use the `permissions` key to add and remove `read` permissions for forked repositories,
> but typically you can't grant `write` access. The exception to this behavior is where an admin user
> has selected the **Send write tokens to workflows from pull requests** option in the GitHub Actions
> settings."
> — GitHub Docs, workflow syntax `permissions`

Secrets are also not passed to fork-PR workflows. **Confidence: HIGH — official docs.**

### Applied to this exact topology

There are three distinct trigger contexts, and only one of them is a "fork PR":

| # | Event | Runs in repo | Token | Can push to GHCR? |
|---|---|---|---|---|
| 1 | `push` to `JMSBPP/evm-spec-bridge:develop` or `feat/*` | JMSBPP fork | **full**, `packages: write` honoured | **YES** |
| 2 | `pull_request` `feat/x` → `develop`, **same repo** | JMSBPP fork | full (head repo == base repo, not a fork PR) | YES, but don't |
| 3 | `pull_request` `JMSBPP:develop` → `d2p-finance:main` | **canonical** | **read-only, no secrets** | **NO — 403** |

Case 3 is exactly the DIST-03 promotion path. The failure is not a YAML parse error — the
`permissions:` block is silently downgraded and `docker/login-action` or the push fails at runtime
with a 403 (`denied: installation not allowed to Write organization package`). A workflow that
unconditionally pushes will make **every promotion PR red**.

### Recommended design

**Build the image on every trigger; push only on `push` events.**

```yaml
- uses: docker/build-push-action@v6
  with:
    push: ${{ github.event_name == 'push' }}
    load: ${{ github.event_name != 'push' }}
```

This keeps the Dockerfile genuinely gated on PRs (a broken Dockerfile still goes red) while never
attempting an operation the token cannot perform. It satisfies DIST-04 because every change lands on
the fork's `develop` via a push, and that push publishes.

**Registry cache has the same constraint**: `cache-to: type=registry` needs write. Use
`cache-from` unconditionally and `cache-to` only on push, or use `type=gha` (which uses the Actions
cache service, available read-only on fork PRs — writes will be skipped, not fatal).

### Two-tier publishing (recommended, and a decision point)

- **Fork `develop` push** → `ghcr.io/jmsbpp/evm-spec-bridge:develop` and `:sha-<short>`. This is the
  dev artifact; it exists from Phase 1.
- **Canonical `main` push (i.e. after a PR merges)** → `ghcr.io/d2p-finance/evm-spec-bridge:latest`,
  `:v<x.y.z>`. A merge into canonical `main` is an internal `push`, so the canonical repo's token
  *does* have `packages: write`. This is the artifact DIST-01 eventually points the consumer at.

Phase 1 needs the fork path *proven working*. Whether the canonical publish workflow ships in Phase 1
or Phase 10 is a decision point (D7).

### The manual step nobody can automate

A container package published to GHCR is **private by default**:

> "When you first publish a package that is scoped to your personal account, the default visibility
> is private and only you can see the package." … "To make the package visible to anyone, select
> **Public**." … "Once you make a package public, you cannot make it private again."
> — GitHub Docs, *Configuring a package's access control and visibility*

CONTEXT.md requires **public, anonymous pull**. Therefore the plan MUST contain an explicit manual
task: after the first successful push, go to the package settings and change visibility to Public,
then **verify anonymous pull works** by pulling with credentials removed:

```bash
docker logout ghcr.io
docker pull ghcr.io/jmsbpp/evm-spec-bridge:develop     # must succeed with no auth
```

That verification is the acceptance criterion, not the UI click. Add the OCI source label so the
package links to the repository:

```
labels: org.opencontainers.image.source=https://github.com/JMSBPP/evm-spec-bridge
```

---

## Don't Hand-Roll

| Problem | Don't build | Use instead | Why |
|---|---|---|---|
| Detecting a forbidden component dependency | A grep over `package.yaml` / a custom lint | The spec-less Stack config (M2) | A grep can't see transitive edges, can't see the `.cabal`, and is trivially defeated. Stack's plan construction sees the real graph |
| Regenerating `.cabal` in CI | A standalone `hpack` install | `stack build --dry-run` (M6) | Stack bundles hpack; a separate install introduces a *second* hpack version and a permanently red drift gate |
| Waiting for something in CI | `sleep` | `--retry-connrefused`, `docker run --rm` | Standing project rule (PITFALLS #11) |
| Copying the tree for the negative test | `git stash` / in-place edit + restore | `mktemp -d` + `cp -r` | An interrupted in-place edit leaves the working tree violated. Also lets the negative test run while the user watches, without touching their worktree |
| Cache key for a git source dep | A custom SHA-extraction script | `hashFiles('stack.yaml','stack.yaml.lock')` (M7) | The commit *and* a content hash are both already in those files |
| Lowercasing the image name | String munging in bash | Hardcode `ghcr.io/jmsbpp/evm-spec-bridge` | One less moving part, and it is greppable |
| Multi-arch images | `buildx` matrix | Don't. `linux/amd64` only | The consumer's runner is x86_64; arm64 doubles build time and Phase 1 is about proving the path |

**Key insight:** In this phase, almost every "guard" has a build-system-native expression that is
both cheaper and less defeatable than a script. Reach for the build system first, the shell second.

---

## Common Pitfalls

### Pitfall 1: The negative test passes because the build failed for the wrong reason

**What goes wrong:** `! stack --stack-yaml stack-core.yaml build` returns non-zero, the test says
"guard fired", and everyone is happy. But the failure was a typo in a `.hs` file, a network blip
fetching the snapshot, an out-of-disk, or a GHC that isn't installed. The guard is now *asserted*
green while being *actually* broken — the exact silent-false-green class this project exists to kill.

**Why it happens:** exit code 1 is the least informative signal a build system produces.

**How to avoid — a three-part assertion:**
1. **Positive control in the same run:** the *unmodified* tree must resolve green against
   `stack-core.yaml` first. If the control is red, abort with a distinct message — the environment is
   broken, not the guard.
2. **Grep the specific error:** require `[S-4804]` **and** `cfmm-scratchpad` **and** the name of the
   core package you violated in the output. Not merely non-zero.
3. **Assert the full config still resolves** with the violation in place (M3). This proves you
   measured the *seam*, not a broken tree.

**Warning signs:** a negative test with no positive control; a negative test that greps nothing; a
negative test that has never been seen to fail when the guard is deliberately disabled.

**Meta-check worth doing once, live, with the user:** temporarily replace `stack-core.yaml`'s
`extra-deps: []` with the spec extra-dep and confirm the negative test goes **red**. That is testing
the test — and it is the single most instructive 30 seconds in this phase.

### Pitfall 2: hpack version skew makes the drift gate red for a reason unrelated to drift

**What goes wrong:** the generated `.cabal` carries a version-stamped header:

```
-- This file has been generated from package.yaml by hpack version 0.39.6.
```

Local Stack 3.11.1 bundles hpack 0.39.6; `haskell:9.10.3-bookworm` bundles **Stack 3.3.1** (verified
from the official Dockerfile) with a different hpack. `haskell-actions/setup` with
`stack-version: latest` will drift on its own schedule. Any of these regenerates a *different first
line*, and `git diff --exit-code` goes red with no semantic change.

**Why it happens:** the gate compares bytes, which is what makes it trustworthy, and the header is
bytes.

**How to avoid:**
- **Pin `stack-version: '3.11.1'` in `haskell-actions/setup`** — never `latest`. (The spec repo's own
  CI uses `latest` and carries this latent bomb; worth mentioning to that repo's owner.)
- **Never run hpack inside the Docker image**: `COPY` the committed `.cabal` files and *not* the
  `package.yaml` files into the dependency layer (M8). Then the image's Stack version cannot matter.
- Record the pinned Stack version in the README next to the GHC version, and treat a Stack upgrade as
  a deliberate, coordinated commit that regenerates all seven `.cabal` files.
- **Do not** strip the header before diffing. That weakens a gate to work around a version pin.

**Warning signs:** a `.cabal` diff whose only hunk is line 3.

### Pitfall 3: Running the seam negative test inside `stack test`

**What goes wrong:** it seems natural to make the negative test a `tasty` case that shells out to
`stack`. Three problems:

1. **Circularity.** The test lives inside the build it is testing. If the seam is broken in a way
   that breaks the build, the test never runs — the gate reports a build failure, not a guard
   failure, and you have lost the very signal the test exists to produce.
2. **Nested Stack invocation.** A `stack` process spawned from inside `stack test` shares
   `STACK_ROOT` and may contend on the pantry/project locks. *(Confidence: MEDIUM — not tested here,
   but the circularity argument alone is decisive.)*
3. **Cost.** The tasty suite must then be built before the 0.34 s guard can run, converting a
   fail-fast job into a slow one.

**How to avoid:** the seam guard and its negative test are a **shell script invoked by a dedicated CI
job that runs before the build job**. `tasty` tests are for Haskell-level properties.

### Pitfall 4: `ghcr.io/${{ github.repository }}` is an invalid reference

**What goes wrong:** `github.repository` is `JMSBPP/evm-spec-bridge`. Docker reference grammar
requires the repository path to be **lowercase**; `docker push ghcr.io/JMSBPP/...` fails with
`invalid reference format: repository name must be lowercase`. This owner has capitals, so it *will*
happen.

**How to avoid:** hardcode `ghcr.io/jmsbpp/evm-spec-bridge`, or lowercase in a step
(`${GITHUB_REPOSITORY,,}`). Hardcoding is recommended: greppable, and there are exactly two of them.

### Pitfall 5: The Actions cache is 10 GB per repo, LRU, and expires in 7 days

> "By default, the limit is 10 GB per repository" … "the cache eviction policy will create space by
> deleting the caches in order of last access date, from oldest to most recent" … "GitHub will remove
> any cache entries that have not been accessed in over 7 days."
> — GitHub Docs, *Dependency caching*

**What goes wrong:** a Stack root for LTS 24.55 with `Chart-cairo` plus a GHC bindist plus the
`.stack-work` trees plus a `type=gha,mode=max` BuildKit cache can plausibly approach or exceed 10 GB.
Once it does, the caches evict each other round-robin and every run is cold — the classic "cache hit
reported, build time unchanged" symptom. The spec repo already hit this reasoning (its CI comments
say the 10 GB cap "would evict the Stack cache").

**How to avoid:**
- Do not use both `actions/cache` for `~/.stack` **and** `cache-to: type=gha,mode=max` at full size.
  Prefer `mode=min` for the Docker cache, or drop the Docker GHA cache entirely in Phase 1 (the image
  build is small).
- **Measure it**: the build-time step should also print `du -sh ~/.stack ~/.stack/* .stack-work`.
  Phase 1's job is to convert folklore into numbers; cache size is folklore too.
- Note the 7-day expiry means a quiet week produces a genuinely cold build. That is a *feature* for
  the cold-build measurement and a nuisance for gate latency.

### Pitfall 6: `tasty-discover` can produce a vacuously green suite

**What goes wrong:** `tasty-discover` finds tests by *filename and function-name prefix* (`unit_`,
`prop_`, `test_`, …). Get the prefix wrong, put a module in the wrong directory, or forget to add the
module to `other-modules`, and the suite runs **zero tests and exits 0**. In a project whose stated
characteristic failure mode is silent false-green, adding a preprocessor whose failure mode is
"silently tested nothing" is a poor trade for saving one line per module.

**How to avoid:** explicit `Main.hs` with an imported `testGroup` per module. Adding a test module is
one import plus one list entry — it is not "wiring up a runner", which is what CONTEXT.md was
guarding against. If `tasty-discover` is chosen anyway, pair it with a floor assertion on the test
count.

### Pitfall 7: The seam is vacuous if the spec extra-dep isn't there yet

**What goes wrong:** "spec wiring" is Phase 7, so it is tempting to leave `extra-deps: []` in
`stack.yaml` in Phase 1. But then `stack.yaml` and `stack-core.yaml` are semantically identical, the
guard distinguishes nothing, and the negative test passes for the wrong reason (any package would
fail to resolve).

**How to avoid:** Phase 1 **must** add the `cfmm-scratchpad` git extra-dep and give `cfmm-adapter` a
real `build-depends: cfmm-scratchpad` — even if the adapter module contains one trivial re-export.
CONTEXT.md already implies this ("proving … cairo resolution" in Phase 1 is only possible if the spec
is in the build). Phase 7 then wires *semantics* (INTEG-01's compile-time SHA stamp), not the
dependency. Flag this to the user as decision point D1.

### Pitfall 8: `permissions:` at workflow level is inherited, not per-job, unless you say so

**What goes wrong:** setting `permissions: {contents: read, packages: write}` at the top of the file
gives the write scope to the build and test jobs too, which do not need it. It also does nothing
useful on a fork PR (silently downgraded), so it reads as protection that isn't there.

**How to avoid:** `permissions: contents: read` at workflow level; add `packages: write` only on the
image job. Least privilege, and it documents which job is the one that publishes.

---

## Code Examples

### The seam guard + negative test script

```bash
#!/usr/bin/env bash
# scripts/seam-negative-test.sh
#
# CFMM-01. Proves the seam guard actually fires.
#
# A guard nobody has seen fire is a guard you are trusting, not one you have verified.
# So this asserts THREE things, not one:
#   (1) CONTROL: the real tree resolves green against the spec-less config
#   (2) NEGATIVE: a tree with the forbidden edge fails, with error S-4804 naming cfmm-scratchpad
#   (3) CONTRAST: that same violated tree still resolves against the FULL config
#       -> proving we measured the seam and not a broken tree
#
# Verified against stack 3.11.1 / LTS 24.55 on 2026-08-27.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VICTIM="components/protocol/package.yaml"   # any core component will do
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# --- (1) CONTROL -------------------------------------------------------------
echo "== control: unmodified core must resolve without the spec =="
if ! stack --stack-yaml "$REPO_ROOT/stack-core.yaml" build --dry-run >/dev/null 2>&1; then
  echo "FAIL(control): the core does NOT resolve against stack-core.yaml."
  echo "               The environment or the tree is broken -- the guard was not tested."
  stack --stack-yaml "$REPO_ROOT/stack-core.yaml" build --dry-run || true
  exit 1
fi
echo "ok: core resolves spec-less"

# --- build the violated scratch copy ----------------------------------------
tar -C "$REPO_ROOT" --exclude='.git' --exclude='.stack-work' --exclude='*/.stack-work' \
    -cf - . | tar -C "$SCRATCH" -xf -
printf '\n# INJECTED BY seam-negative-test.sh\n' >> "$SCRATCH/$VICTIM"
python3 - "$SCRATCH/$VICTIM" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'^dependencies:\n', 'dependencies:\n- cfmm-scratchpad\n', s, count=1, flags=re.M)
open(p, 'w').write(s)
PY
grep -q 'cfmm-scratchpad' "$SCRATCH/$VICTIM" || { echo "FAIL: injection did not take"; exit 1; }

# --- (2) NEGATIVE ------------------------------------------------------------
echo "== negative: the forbidden edge must fail to RESOLVE spec-less =="
set +e
OUT="$(cd "$SCRATCH" && stack --stack-yaml stack-core.yaml build --dry-run 2>&1)"
RC=$?
set -e

[ "$RC" -ne 0 ]                       || { echo "FAIL: guard did NOT fire (exit 0)"; echo "$OUT"; exit 1; }
grep -q 'S-4804'          <<<"$OUT"   || { echo "FAIL: red, but not the build-plan error we expect"; echo "$OUT"; exit 1; }
grep -q 'cfmm-scratchpad' <<<"$OUT"   || { echo "FAIL: red, but cfmm-scratchpad is not named"; echo "$OUT"; exit 1; }
grep -q 'evm-spec-bridge-protocol' <<<"$OUT" || { echo "FAIL: red, but the violating package is not named"; echo "$OUT"; exit 1; }
echo "ok: guard fired with [S-4804] naming cfmm-scratchpad in evm-spec-bridge-protocol"

# --- (3) CONTRAST ------------------------------------------------------------
echo "== contrast: the same violated tree still resolves against the FULL config =="
if ! (cd "$SCRATCH" && stack --stack-yaml stack.yaml build --dry-run >/dev/null 2>&1); then
  echo "FAIL(contrast): the violated tree fails under stack.yaml too."
  echo "                So the negative result above may not have been the seam."
  exit 1
fi
echo "ok: full config tolerates it -- the seam, and only the seam, produced the red"
echo
echo "SEAM GUARD VERIFIED"
```

*(Trade-off note for the user: the `tar | tar` copy is used instead of `cp -r` so the exclusions are
honoured on one line. `git worktree add` was considered and rejected — it requires the forbidden edge
to exist on a committed branch, which is exactly the state we do not want in the repo.)*

### `tasty` scaffold — minimal but genuinely running

```haskell
-- components/protocol/test/Main.hs
-- Phase 1 scaffold. Later phases add `testGroup`s to `tests` and modules under test/.
-- Deliberately explicit rather than tasty-discover: a discovery misconfiguration
-- exits 0 having run nothing, and a vacuously-green suite is this project's
-- characteristic failure mode.
module Main (main) where

import Test.Tasty       (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "evm-spec-bridge-protocol"
  [ scaffold
  -- Phase 3+ : , Bridge.Protocol.EnvelopeTest.tests
  ]

-- Proves the runner is wired: it compiles, links, executes and reports.
-- Delete this only when a real test in this group replaces it.
scaffold :: TestTree
scaffold = testGroup "scaffold"
  [ testCase "the test runner executes" $ (1 :: Int) + 1 @?= 2
  ]
```

Run with `stack test`, or `stack build --test --no-run-tests` to typecheck without executing.

### Multi-stage Dockerfile

```dockerfile
# syntax=docker/dockerfile:1.7
#
# Builder base is pinned to the compiler LTS 24.55 declares (resolver.compiler: ghc-9.10.3),
# so the image and CI cannot disagree about GHC. The image already sets
# system-ghc: true / install-ghc: false, so stack will not download a second GHC.
FROM haskell:9.10.3-bookworm AS builder

# cairo/pango arrive via cfmm-scratchpad's PACKAGE-level Chart-cairo dependency,
# which the LIBRARY inherits -- so anything linking the spec needs these headers.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libcairo2-dev libpango1.0-dev libglib2.0-dev pkg-config \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Dependency layer. Deliberately copies the COMMITTED .cabal files and NOT package.yaml,
# so hpack never runs in here and the image's stack version cannot cause .cabal drift.
COPY stack.yaml stack.yaml.lock ./
COPY components/protocol/*.cabal      components/protocol/
COPY components/abi-codec/*.cabal     components/abi-codec/
COPY components/jsonrpc/*.cabal       components/jsonrpc/
COPY components/registry/*.cabal      components/registry/
COPY components/transport/*.cabal     components/transport/
COPY components/codegen/*.cabal       components/codegen/
COPY components/cfmm-adapter/*.cabal  components/cfmm-adapter/
RUN --mount=type=cache,target=/root/.stack \
    stack --system-ghc --no-install-ghc build --only-dependencies

# Source layer -- invalidated by code changes, not by dependency changes.
COPY . .
RUN --mount=type=cache,target=/root/.stack \
    stack --system-ghc --no-install-ghc build --copy-bins --local-bin-path /out

# --- runtime -----------------------------------------------------------------
# ldd on a GHC 9.10.3 -threaded binary shows only libm, libgmp.so.10, libc and the loader
# (measured 2026-08-27). libffi is statically linked. No cairo at runtime while the shipped
# binary does not link cfmm-adapter -- revisit at Phase 11.
FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
      libgmp10 ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN useradd --system --uid 10001 bridge
COPY --from=builder /out/evm-spec-bridge /usr/local/bin/evm-spec-bridge
USER bridge
ENTRYPOINT ["/usr/local/bin/evm-spec-bridge"]
```

**Caveat (MEDIUM confidence):** `RUN --mount=type=cache` is a BuildKit cache mount. It speeds local
rebuilds but is **not** persisted by `docker/build-push-action`'s `cache-to: type=gha` — GHA caching
persists *layers*, not cache mounts. On CI the mount is empty every run. If CI image-build time is
the bottleneck, either drop the mounts and rely on layer caching (the `.cabal`-only dependency layer
is what makes that work), or use `reproducible-containers/buildkit-cache-dance`. For Phase 1's
trivial binary the difference is small; **measure before optimising**.

### CI workflow

```yaml
# .github/workflows/ci.yml
name: CI

# Broader than the consumer's PR-only gate on purpose: work in a feat/* worktree is
# validated while it happens, not at promotion time.
on:
  push:
  pull_request:

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

# Least privilege at workflow level. Only the image job widens it, and only on push --
# a pull_request from the JMSBPP fork into d2p-finance gets a READ-ONLY token no matter
# what this file says, so `packages: write` there would be decoration.
permissions:
  contents: read

env:
  IMAGE: ghcr.io/jmsbpp/evm-spec-bridge   # lowercase is mandatory; github.repository is not

jobs:
  seam:
    name: seam guard (CFMM-01)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: haskell-actions/setup@v2
        with:
          enable-stack: true
          stack-version: '3.11.1'     # PINNED: bundles hpack 0.39.6. Never `latest`.
          ghc-version: '9.10.3'       # matches LTS 24.55's resolver.compiler
      # Plan construction only -- no compilation. Measured at 0.34s locally.
      - name: core resolves WITHOUT the spec
        run: stack --system-ghc --no-install-ghc --stack-yaml stack-core.yaml build --dry-run
      - name: the guard actually fires
        run: ./scripts/seam-negative-test.sh

  build:
    name: build + test + hpack drift
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: system deps for Chart-cairo (arrives via the spec LIBRARY)
        run: |
          sudo apt-get update
          sudo apt-get install -y libcairo2-dev libpango1.0-dev libglib2.0-dev pkg-config
      - uses: haskell-actions/setup@v2
        with:
          enable-stack: true
          stack-version: '3.11.1'
          ghc-version: '9.10.3'
      # stack.yaml + stack.yaml.lock together carry the spec's git commit AND a pantry
      # tree hash (verified), so a spec bump DOES invalidate this key. PITFALLS.md #12's
      # "source dep changes nothing in the freeze file" trap is a cabal problem, not ours.
      - uses: actions/cache@v4
        id: stackcache
        with:
          path: |
            ~/.stack
            .stack-work
            components/*/.stack-work
          key: stack-${{ runner.os }}-ghc9.10.3-${{ hashFiles('stack.yaml', 'stack.yaml.lock', 'components/*/package.yaml') }}
          restore-keys: |
            stack-${{ runner.os }}-ghc9.10.3-
      - name: build (timed)
        run: |
          s=$(date +%s)
          stack --system-ghc --no-install-ghc build --test --no-run-tests --pedantic
          echo "T_BUILD=$(( $(date +%s) - s ))" >> "$GITHUB_ENV"
      - name: warm rebuild (timed)
        run: |
          s=$(date +%s)
          stack --system-ghc --no-install-ghc build --test --no-run-tests
          echo "T_WARM=$(( $(date +%s) - s ))" >> "$GITHUB_ENV"
      - name: tasty
        run: stack --system-ghc --no-install-ghc test
      # M6: stack's bundled hpack rewrites every .cabal; any diff is drift.
      - name: hpack drift gate
        run: |
          stack --system-ghc --no-install-ghc build --dry-run >/dev/null
          git diff --exit-code -- '**/*.cabal'
      - name: record build times and cache sizes
        if: always()
        run: |
          case "${{ steps.stackcache.outputs.cache-hit }}" in
            true) STATE="exact cache hit (warm)" ;;
            *)    if [ -n "${{ steps.stackcache.outputs.cache-matched-key }}" ]; then
                    STATE="partial restore-keys hit (lukewarm)"
                  else STATE="cache MISS (cold)"; fi ;;
          esac
          {
            echo "### Build times"
            echo ""
            echo "| measurement | value |"
            echo "|---|---|"
            echo "| cache state | $STATE |"
            echo "| first build in job | ${T_BUILD}s |"
            echo "| immediate rebuild | ${T_WARM}s |"
            echo "| \`~/.stack\` | $(du -sh ~/.stack 2>/dev/null | cut -f1) |"
            echo "| \`.stack-work\` (all) | $(du -sch .stack-work components/*/.stack-work 2>/dev/null | tail -1 | cut -f1) |"
          } >> "$GITHUB_STEP_SUMMARY"

  image:
    name: container image
    needs: [seam, build]
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write       # honoured on push; silently downgraded on a fork PR
    steps:
      - uses: actions/checkout@v5
      - uses: docker/setup-buildx-action@v3
      - name: Log in to GHCR
        if: github.event_name == 'push'
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Build (always) and push (push events only)
        id: build
        uses: docker/build-push-action@v6
        with:
          context: .
          file: docker/Dockerfile
          platforms: linux/amd64
          # A fork PR into d2p-finance cannot push. Build it anyway so a broken
          # Dockerfile still goes red at promotion time.
          push: ${{ github.event_name == 'push' }}
          load: ${{ github.event_name != 'push' }}
          tags: |
            ${{ env.IMAGE }}:sha-${{ github.sha }}
            ${{ env.IMAGE }}:${{ github.ref_name }}
          labels: |
            org.opencontainers.image.source=https://github.com/${{ github.repository }}
            org.opencontainers.image.revision=${{ github.sha }}
          cache-from: type=gha
          cache-to: ${{ github.event_name == 'push' && 'type=gha,mode=min' || '' }}
      # Proves the runtime stage actually has what the binary links (libgmp).
      # A Dockerfile that builds but produces a binary that cannot start is a false green.
      - name: smoke — the shipped binary runs
        run: docker run --rm ${{ env.IMAGE }}:sha-${{ github.sha }} --version
```

### Optional: a genuinely cold build measurement

`cache-hit` on a normal push is usually a partial restore, so the "cold" number above is
opportunistic. For a number you can quote, add a job that never restores:

```yaml
  cold-build-benchmark:
    if: github.event_name == 'workflow_dispatch' || github.event_name == 'schedule'
    runs-on: ubuntu-latest
    steps:
      # identical to `build`, but with NO actions/cache step at all
      # -> includes GHC download, snapshot resolution, and every dependency from source
```

with `on: { workflow_dispatch: , schedule: [{cron: '0 6 * * 1'}] }`. Run it once during Phase 1
execution and paste the number into the phase summary.

---

## State of the Art

| Old approach | Current approach | When changed | Impact here |
|---|---|---|---|
| hpack writes `-- hash:` into the `.cabal` and refuses to overwrite hand edits | No hash line; unconditional regeneration | hpack ≥ ~0.35 | The drift gate needs no `--force` and cannot be defeated by editing the `.cabal` (M6) |
| `resolver:` key in `stack.yaml` | `snapshot:` key (`resolver` still accepted) | Stack 2.15+ | Match the spec's file, which already uses `snapshot:` |
| `actions/checkout@v3`, `cache@v3` | `@v5` / `@v4`; v3 runners retired | 2024–2025 | Use current majors |
| Docker Hub as the default registry | GHCR, integrated with repo permissions | — | CONTEXT.md's choice; `docker-hub` MCP was unavailable anyway |
| `docker build` + separate `docker push` | `docker/build-push-action@v6` with `push:` as an expression | v5→v6, 2024 | Makes "build on PR, push on push" a one-line conditional |

**Superseded within this project's own research set:**
- `.planning/research/STACK.md`'s **`cabal` over `stack`** recommendation — overridden by PROJECT.md
  and CONTEXT.md.
- `.planning/research/STACK.md`'s **`hspec`** recommendation — overridden by CONTEXT.md (`tasty`).
- `.planning/research/STACK.md`'s **GHC 9.10.3 "primary, 9.12.4 in matrix"** — there is no matrix.
  The snapshot pins one compiler; a second GHC would mean the spec compiled twice differently, the
  exact skew problem PROJECT.md forbids.
- `.planning/research/PITFALLS.md` **#12's source-dependency cache-key trap** — does not apply to
  Stack extra-deps (M7). Its `cabal.project.freeze` advice is likewise moot; `stack.yaml.lock` is the
  equivalent and is committed.

---

## Decision Points to Surface During Execution

The execution model is inline, with heavy user intervention and an explicit learning goal. These are
the places where the planner should stop and explain rather than resolve silently. Each is marked
**instructive** (the user learns something transferable) or **mechanical** (just do it).

| # | Decision | Why it is a real decision | Recommendation |
|---|---|---|---|
| **D1** | Does Phase 1 add the `cfmm-scratchpad` git extra-dep, given spec wiring is Phase 7? | **Instructive.** Without it the seam is vacuous (Pitfall 7) and cairo is never proven. With it, Phase 1's build time jumps by the whole Chart/cairo tree | **Yes, add it.** Phase 7 wires *semantics* (the compile-time SHA), not the dependency |
| **D2** | Seven packages vs. two (core-with-internal-libs + adapter) | **Instructive** — this is where the user learns what a Stack "package" actually is and why `packages:` granularity is the whole seam mechanism | Seven. Walk through M5's two failure outputs live |
| **D3** | Does the seam guard `--dry-run` or really build? | **Instructive** — teaches that the error is a *planning* error, not a compile error | `--dry-run`. Show the 0.34 s timing |
| **D4** | Is the negative test a script or a tasty case? | **Instructive** — the circularity argument (Pitfall 3) is a genuinely transferable idea | Script, in a job that runs *before* the build |
| **D5** | Does Phase 1's runtime image include cairo? | **Instructive** — forces the question "what does this binary actually link?", answered with `ldd` | No cairo in Phase 1's runtime stage; write down that Phase 11 revisits it. Run `ldd` live |
| **D6** | Which component does the trivial Phase 1 executable live in? | Mechanical-ish, but determines whether the runtime image needs cairo | A core component (or a thin `app/`), so D5 holds |
| **D7** | Does the canonical repo get a publish workflow in Phase 1, or Phase 10? | **Instructive** — surfaces the three-context permission table | Phase 1 ships the fork path only; note the canonical path in the README |
| **D8** | Pinned Stack version everywhere vs. `latest` in CI | **Instructive** — the byte-diff gate meets a version-stamped header | Pin `3.11.1`. Demonstrate the drift by bumping and watching it go red |
| **D9** | One CI job or three? | Mechanical (explicit discretion in CONTEXT.md) | Three: `seam` (seconds), `build`, `image`. Fail-fast on the cheap one |
| **D10** | `justfile` / `Makefile` wrapper? | Mechanical (explicit discretion) | A `justfile` with `just seam`, `just drift`, `just build` — the CI steps and the local steps should be the same strings |
| **D11** | Branch protection on canonical `main` | **Instructive** — this is what makes DIST-03 structural rather than a promise | Require PR, require the CI check, disallow direct push (see below) |

### Branch protection & the PR path (DIST-03)

DIST-03 says changes reach canonical *only* via PR. A convention is not a mechanism. Make it one:

```bash
# on d2p-finance/evm-spec-bridge -- requires admin on the org repo
gh api -X PUT repos/d2p-finance/evm-spec-bridge/branches/main/protection \
  -f 'required_pull_request_reviews[required_approving_review_count]=0' \
  -F 'enforce_admins=true' \
  -F 'required_status_checks[strict]=true' \
  -f 'required_status_checks[contexts][]=build + test + hpack drift' \
  -F 'restrictions=null'
```

*(Confidence: MEDIUM on the exact flag spelling — the REST payload for branch protection is fiddly
and should be applied then read back with `gh api repos/.../branches/main/protection`. The
**intent** — required PR, required status check, `enforce_admins` so the owner cannot bypass — is
the part that matters.)*

The acceptance evidence for DIST-03 is not "we agreed to use PRs"; it is a **rejected direct push**:

```bash
git push upstream develop:main    # must be refused by the remote
```

That refusal, pasted into the phase summary, is the requirement being satisfied.

---

## Open Questions

1. **Actual cold build time with `Chart-cairo` in the plan.**
   - What we know: the spec's own CI builds this on `ubuntu-latest` with the four cairo apt packages
     and is green, so it is feasible.
   - What's unclear: the wall-clock number. Every estimate in the planning tree is folklore.
   - Recommendation: this is exactly what Phase 1's measurement step exists to answer. Do not
     estimate it in the plan; record it.

2. **Whether `~/.stack` + `.stack-work` fits under the 10 GB Actions cache cap.**
   - What we know: the cap, the LRU eviction and the 7-day expiry are documented (Pitfall 5); the
     spec repo's CI already reasons about it.
   - What's unclear: our actual size once `Chart-cairo` and its transitive tree are built.
   - Recommendation: print `du -sh` in the same step that prints build times. If it is over ~6 GB,
     drop `.stack-work` from the cache (it is the cheapest part to rebuild) before dropping `~/.stack`.

3. **Does BuildKit's `--mount=type=cache` survive `cache-to: type=gha`?**
   - What we know: GHA caching persists layers.
   - What's unclear (MEDIUM): whether cache mounts are included. Community consensus is *no* without
     `buildkit-cache-dance`.
   - Recommendation: keep the mounts (they help local iteration), do not depend on them in CI, and
     rely on the `.cabal`-only dependency layer for CI caching.

4. **Exact hpack version bundled in Stack 3.3.1 (`haskell:9.10.3-bookworm`).**
   - What we know: the image's Stack is 3.3.1 (official Dockerfile); local is 3.11.1 / hpack 0.39.6.
     A `docker run` to read it exactly was attempted and did not complete this session.
   - What's unclear: the precise number.
   - Recommendation: irrelevant if the Dockerfile copies only `.cabal` files (M8). If someone
     later copies `package.yaml` into the image, this becomes load-bearing — leave the comment in the
     Dockerfile explaining why it doesn't.

5. **`stack --stack-yaml stack-core.yaml build` (a real build) and `.stack-work` sharing.**
   - What we know: different `extra-deps` sets normally produce different Stack install hashes, which
     would mean compiling the core twice.
   - What's unclear: only one install hash directory appeared in the local experiment; not conclusive
     because `--dry-run` does not populate them.
   - Recommendation: moot under the `--dry-run` guard. If anyone ever proposes making the guard a
     real build, measure this first.

6. **Whether the spec's `cfmm-scratchpad` library actually compiles cleanly under our `-Wall`
   settings when pulled as an extra-dep.**
   - What we know: `stack build --dry-run` resolved it fine against the real repo at
     `93fe3acf...`; extra-deps are not built with `--pedantic`, so its warnings are not ours.
   - What's unclear: whether the full compile succeeds on a fresh runner with the cairo apt set.
   - Recommendation: this is the single highest-value thing to attempt early in execution. If it
     fails, everything downstream is blocked and Phase 1 is precisely the cheapest place to find out.

---

## Validation Architecture

### Test framework

| Property | Value |
|---|---|
| Framework | `tasty` 1.5.4 + `tasty-hunit` 0.10.2 (from LTS 24.55) |
| Config file | none yet — created in Wave 0 (`components/*/package.yaml` `tests:` stanza + `test/Main.hs`) |
| Quick run command | `stack --system-ghc --no-install-ghc test evm-spec-bridge-protocol` |
| Full suite command | `stack --system-ghc --no-install-ghc test` |
| Build-system assertions | shell scripts under `scripts/`, run by CI **outside** the Haskell build (Pitfall 3) |

A deliberate note: most of Phase 1's success criteria are **properties of the build system, not of
Haskell code**, so most of its validation is shell-level, not `tasty`-level. `tasty` exists in Phase 1
to prove the runner is wired, not to carry this phase's assertions.

### Phase requirements / success criteria → test map

| Req / Criterion | Behaviour | Test type | Automated command | Exists? |
|---|---|---|---|---|
| CFMM-01 (a) | Six core packages resolve with **no** spec in scope | build-plan | `stack --stack-yaml stack-core.yaml build --dry-run` | ❌ Wave 0 |
| CFMM-01 (b) | A core package gaining `cfmm-scratchpad` fails with `[S-4804]` naming it | build-plan (negative) | `./scripts/seam-negative-test.sh` | ❌ Wave 0 |
| CFMM-01 (c) | The same violation is **tolerated** by the full config (proves the guard, not a broken tree) | build-plan (contrast) | included in `seam-negative-test.sh` step 3 | ❌ Wave 0 |
| CFMM-01 (d) | `cfmm-adapter` really does depend on the spec (the seam is non-vacuous) | grep + plan | `grep -q cfmm-scratchpad components/cfmm-adapter/package.yaml && stack build --dry-run` | ❌ Wave 0 |
| DIST-03 (a) | Direct push to canonical `main` is refused | manual/one-shot | `git push upstream develop:main` → expect rejection; paste output | ❌ Wave 0 (needs branch protection) |
| DIST-03 (b) | A PR fork→canonical exists and CI runs on it | manual/observed | `gh pr create --repo d2p-finance/evm-spec-bridge …`; `gh pr checks` | ❌ Wave 0 |
| DIST-04 (a) | Gate triggers on **both** push and pull_request | observed | `gh run list --json event` shows both `push` and `pull_request` | ❌ Wave 0 |
| DIST-04 (b) | Every component compiles; a broken one goes red | build | `stack build --test --no-run-tests --pedantic` | ❌ Wave 0 |
| DIST-04 (c) | hpack drift is caught | diff gate | `stack build --dry-run && git diff --exit-code -- '**/*.cabal'` | ❌ Wave 0 |
| DIST-04 (d) | Snapshot matches the spec's | assertion | `diff <(yq .snapshot.url stack.yaml) <(yq .snapshot.url $SPEC/stack.yaml)` — or simply grep for `lts/24/55.yaml` | ❌ Wave 0 |
| DIST-04 (e) | Cold and warm build times are recorded | observed artifact | `$GITHUB_STEP_SUMMARY` table present in the run | ❌ Wave 0 |
| DIST-04 (f) | Image builds and is pushed to GHCR | build + push | `docker/build-push-action` step green on a `push` run | ❌ Wave 0 |
| DIST-04 (g) | The published binary actually starts (runtime libs correct) | smoke | `docker run --rm ghcr.io/jmsbpp/evm-spec-bridge:sha-$SHA --version` | ❌ Wave 0 |
| DIST-04 (h) | The image is anonymously pullable | manual + smoke | `docker logout ghcr.io && docker pull ghcr.io/jmsbpp/evm-spec-bridge:develop` | ❌ Wave 0 (needs the manual visibility flip) |
| Criterion 5 | `tasty` scaffold runs in the gate | unit | `stack test` — must report ≥ 1 test, exit 0 | ❌ Wave 0 |
| **Meta** | The seam guard itself can go red (testing the test) | manual, once | temporarily add the extra-dep to `stack-core.yaml`, re-run `seam-negative-test.sh`, expect FAIL | ❌ Wave 0 |

### Sampling rate

- **Per task commit:** `stack --stack-yaml stack-core.yaml build --dry-run` (0.34 s) + `stack build
  --dry-run && git diff --exit-code -- '**/*.cabal'`. Both are sub-second once warm — cheap enough to
  run on literally every edit.
- **Per wave merge:** `./scripts/seam-negative-test.sh && stack build --test --no-run-tests --pedantic && stack test`
- **Phase gate:** full workflow green on a real `push` to the fork's `develop`, *plus* a real PR
  fork→canonical showing checks running, *plus* the anonymous `docker pull` succeeding, before
  `/gsd:verify-work`.

### Wave 0 gaps

Everything is a gap — this is a greenfield repo containing only `README.md` and `.planning/`.

- [ ] `stack.yaml`, `stack.yaml.lock`, `stack-core.yaml` — CFMM-01
- [ ] `components/{protocol,abi-codec,jsonrpc,registry,transport,codegen,cfmm-adapter}/package.yaml`
      + committed `.cabal` — CFMM-01, DIST-04(b,c)
- [ ] `components/protocol/test/Main.hs` — tasty scaffold, criterion 5
- [ ] `scripts/seam-guard.sh`, `scripts/seam-negative-test.sh` — CFMM-01(b,c)
- [ ] `docker/Dockerfile` — DIST-04(f,g)
- [ ] `.github/workflows/ci.yml` — DIST-04(a–f)
- [ ] `.gitignore` (must **not** ignore `*.cabal` — the drift gate depends on them being tracked)
- [ ] Framework install: none — `tasty` comes from LTS 24.55 via `stack`; no separate install
- [ ] **Manual, not automatable:** GHCR package visibility → Public (one-time, irreversible)
- [ ] **Manual, needs org admin:** branch protection on `d2p-finance/evm-spec-bridge:main`

---

## Sources

### Primary — HIGH confidence (executed locally or official)

- **Local execution, 2026-08-27** — `stack 3.11.1` (`hpack-0.39.6`), GHC 9.10.3, against live
  LTS 24.55. Experiments M1–M9 in `/tmp/seamtest`, `/tmp/intlibtest`, `/tmp/gitdep`, `/tmp/cabalonly`.
  Every command and its output is reproduced verbatim in "Verified Mechanisms".
- `https://raw.githubusercontent.com/commercialhaskell/stackage-snapshots/master/lts/24/55.yaml` —
  `resolver.compiler: ghc-9.10.3`; all package versions in "Standard Stack"; sha256
  `1c2140555bdf61c30a893b3ec1033987d01eda75ce82a1dda033e8fb6f8b322c`, 732456 bytes.
- `https://github.com/haskell/docker-haskell` `9.10/bookworm/Dockerfile` — Stack 3.3.1,
  cabal-install 3.14.1.1, GHC 9.10.3, Debian bookworm, apt list, `system-ghc`/`install-ghc` presets.
- Docker Hub registry API — image sizes and tag existence for `library/haskell`,
  `library/debian`, `fpco/stack-build`, `fpco/stack-build-small`, queried 2026-08-27.
- `gh api` against `JMSBPP/evm-spec-bridge` and `d2p-finance/evm-spec-bridge` — fork status,
  default branches, Actions permissions, workflow count.
- GitHub Docs — *Workflow syntax → `permissions`*: fork PRs "typically you can't grant `write`
  access".
  <https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions>
- GitHub Docs — *Configuring a package's access control and visibility*: personal-account-scoped
  packages default to **private**; making them public is irreversible.
  <https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility>
- GitHub Docs — *Dependency caching*: 10 GB per repository, LRU eviction, 7-day unused expiry.
  <https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching>
- GitHub Docs — *Publishing and installing a package with GitHub Actions*: `permissions` block for
  GHCR, package↔repository linkage.
  <https://docs.github.com/en/packages/managing-github-packages-using-github-actions-workflows/publishing-and-installing-a-package-with-github-actions>
- `haskell-works/tasty-discover` README (via `gh api`) — driver-file convention and prefix rules
  (used to argue *against* it, Pitfall 6).
- Local repo files: `/home/jmsbpp/cfmms-playground/cfmm-wt/vol-markets/spec/{stack.yaml,stack.yaml.lock,package.yaml,cfmm-scratchpad.cabal,.github/workflows/ci.yml}`.

### Secondary — MEDIUM confidence

- BuildKit `--mount=type=cache` not being persisted by `type=gha` — widely reported community
  finding, not verified here. Flagged as Open Question 3.
- Nested-`stack`-inside-`stack test` lock contention — reasoned, not tested. Flagged in Pitfall 3.
- The exact `gh api` payload for branch protection — spelling should be verified by reading it back.

### Tertiary — LOW confidence / flagged

- The exact hpack version bundled in Stack 3.3.1 (Open Question 4). Only the *fact of difference*
  from 0.39.6 is relied upon, and the recommended Dockerfile makes even that irrelevant.

---

## Metadata

**Confidence breakdown:**

| Area | Level | Reason |
|---|---|---|
| Seam mechanism (CFMM-01) | **HIGH** | Executed both directions locally; exact error text, exit codes and timing captured |
| Seven-packages-vs-internal-libraries | **HIGH** | Both failure modes reproduced (`S-4804`, `S-8506`) |
| Toolchain versions | **HIGH** | Read from the pinned snapshot file, not from memory or Hackage "latest" |
| hpack drift gate | **HIGH** | Regeneration and silent-overwrite behaviour executed |
| `stack.yaml.lock` records the git commit | **HIGH** | Executed against the real spec repo |
| Runtime shared libraries | **HIGH** | `ldd` on a real GHC 9.10.3 `-threaded` binary |
| Docker base images | **HIGH** | Registry API + the official Dockerfile source |
| Fork-PR / GHCR permissions | **HIGH** | Official GitHub docs, cross-checked; topology confirmed via `gh` |
| Repo/Actions state | **HIGH** | Queried live |
| CI wall-clock build times | **LOW by construction** | Unmeasured. Measuring them is a Phase 1 deliverable, not a research output |
| BuildKit cache-mount persistence in GHA | **MEDIUM** | Community consensus, unverified here |
| Branch-protection API payload | **MEDIUM** | Intent certain, exact flags should be read back |

**Research date:** 2026-08-27
**Valid until:** ~2026-09-26 for the toolchain and image facts (LTS 24.x moves weekly — 24.56 already
exists — but our snapshot is pinned by URL, so *our* facts do not move). The GitHub Actions
permission model and GHCR visibility defaults are stable; re-verify in ~90 days.
