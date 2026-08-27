# Phase 1: Repo Skeleton, Component Seams, CI Floor - Context

**Gathered:** 2026-08-27
**Status:** Ready for planning

<domain>
## Phase Boundary

The repository exists with its architectural seams already enforced by the compiler, and a CI
gate that goes red on anything that does not build. Retires the carried infrastructure risks
before any design work is sunk.

Requirements: **CFMM-01, DIST-03, DIST-04**.

In scope: component skeleton, seam enforcement, CI gate, container image, build-time
measurement. Out of scope: protocol semantics, server behaviour, codegen, domain logic — those
are Phases 3–11. Nothing here implements the bridge; it makes the bridge buildable and its
boundaries unviolatable.

</domain>

<decisions>
## Implementation Decisions

### Execution model — GOVERNING, applies to this phase and beyond

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

### Component structure

- **Seven components exist from day one**: `protocol`, `abi-codec`, `jsonrpc`, `registry`,
  `transport`, `codegen` (core) plus `cfmm-adapter`.
- Rationale: every later phase drops into a component that already exists, and the dependency
  graph is declared before anyone can accidentally violate it. Accepts seven near-empty stanzas
  as the cost.
- `cfmm-adapter` is the ONLY component permitted to depend on the spec package
  (`cfmm-scratchpad`).

### Build system

- **Stack + hpack**, snapshot matching the spec's exactly (LTS 24.55).
- Spec arrives as a Stack `extra-deps` git entry pinned to a commit — not a submodule.
- **The generated `.cabal` IS committed**, matching the spec repo's convention, so consumers can
  build without hpack installed. CI runs hpack and fails on a diff — the same
  `git diff --exit-code` treatment the generated Solidity gets later, so both generated-artifact
  gates are one habit rather than two.

### Seam enforcement

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

### CI gate

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

### Distribution — Docker

- **The container image is the artifact.** The bridge is built and published as an image by our
  gate (GHCR, public, anonymous pull). The consumer runs it rather than building it.
- This **replaces the self-hosted-runner probe**: criterion 4 changes from "can their runner
  build GHC and resolve cairo/pango" to "can their runner run our image" — a far easier question,
  answerable without owning the machine.
- Three risks collapse into one: toolchain provisioning on an uninspectable runner; the
  zombie/port-collision class on a *persistent* runner (a container lifecycle is bounded where a
  leaked bare process is not); and their build time, since `Chart-cairo` arrives through the spec
  *library*, not just its executable.
- **Phase 1 builds and publishes a minimal multi-stage image** carrying a trivial binary — proving
  GHC-in-a-container, cairo resolution and the GHCR publish while there is almost no code, so a
  failure is cheap to diagnose.
- Docker does not remove our own need for cairo at image-build time — but that is on hosted CI
  where we control the environment, which is the easy case rather than the unverified one.
- `docker-hub` MCP was unavailable this session; GHCR is the registry.

### Repository topology

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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project governance
- `.planning/PROJECT.md` — constraints, carried risks, and the Key Decisions table; note the
  Stack/hpack and snapshot-matching constraints and the measured-findings provenance
- `.planning/REQUIREMENTS.md` — CFMM-01, DIST-03, DIST-04 are this phase's requirements; `[M]`
  and `[S]` markers denote measured/source-derived requirements that must not be relaxed
- `.planning/ROADMAP.md` — Phase 1 success criteria and the "Governing Decisions Applied" section

### Research
- `.planning/research/SUMMARY.md` — synthesis, convergent findings, and the recorded
  disagreements (D1: the STACK dimension's `vm.rpcJson` recommendation is superseded; D5:
  ARCHITECTURE's guard-evaluation assumption is overridden by PROJECT.md)
- `.planning/research/STACK.md` — library and toolchain findings. **Its cabal-over-stack
  recommendation and its `hspec` recommendation are both superseded by this document.**
- `.planning/research/ARCHITECTURE.md` — component seams and build order
- `.planning/research/PITFALLS.md` — includes the containerisation suggestion this phase adopts,
  and the Stack-cache-keyed-on-freeze-file trap relevant to a git source dependency

### External (upstream, read-only)
- `/home/jmsbpp/cfmms-playground/cfmm-wt/vol-markets/spec/stack.yaml` — the snapshot to match
  (LTS 24.55, pinned by URL)
- `/home/jmsbpp/cfmms-playground/cfmm-wt/vol-markets/spec/package.yaml` — the spec's package name
  (`cfmm-scratchpad`) and its package-level `Chart`/`Chart-cairo` dependencies, which the library
  inherits
- `/home/jmsbpp/.claude/CLAUDE.md` — the fork → PR rule and the mandatory two-step reviewer
  process for pre-commit artifacts

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None. The repository contains `README.md` and `.planning/` only — this phase is greenfield and
  every structural decision here is a first decision.

### Established Patterns
- The spec repo (`cfmm-vol-markets-spec`) is the pattern to follow for Haskell conventions:
  Stack + hpack, committed generated `.cabal`, snapshot pinned by URL.
- The consumer repo's planning conventions (worktree per unit of work, CI as the arbiter) are
  adopted here, with one deliberate divergence: our gate runs on push as well as PR.

### Integration Points
- `cfmm-adapter` → `cfmm-scratchpad` is the single permitted edge to the outside world, and the
  one the seam guard exists to protect.
- The published image is the integration surface for `cfmm-vol-markets`, replacing a native build
  on their runner.

</code_context>

<specifics>
## Specific Ideas

- The seam guard must fail for a reason a reader can *see*, not infer. That is why the spec-less
  config was chosen over a target list, and why the negative test exists.
- "A guard nobody has seen fire is a guard you are trusting, not one you have verified" — this is
  the same principle behind the coercion-conformance fixture and the compile-time spec SHA stamp
  elsewhere in the project.
- Phase 1 should be cheap to diagnose when it fails. Everything it proves is proved while there is
  almost no code, deliberately.

</specifics>

<deferred>
## Deferred Ideas

- **Propagating the Docker decision into ROADMAP.md phases 6 and 10** and the affected
  requirements (SRV-01's ephemeral port becomes a port mapping; SRV-08's lifecycle becomes
  container lifecycle; DIST-05's leaked-server lane is softened because a container bounds the
  failure mode it tests; DIST-01's packaging becomes an image pull). The user chose to write
  context first. This should happen before Phase 6 is planned, or those phases will be planned
  against a stale model.
- Splitting the core into finer components than the six chosen, or merging them — revisit when
  real modules exist and boundaries are known from code rather than predicted.
- `hlint` / formatter checks in the gate — considered and deferred; another thing that can go red
  for reasons unrelated to correctness, on a gate that runs on every push.

</deferred>

---

*Phase: 01-repo-skeleton-component-seams-ci-floor*
*Context gathered: 2026-08-27*
