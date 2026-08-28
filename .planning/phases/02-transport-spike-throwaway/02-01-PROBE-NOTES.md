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

## Script sanity check during 02-01-T3 — NOT the T4 negative test

**This does NOT satisfy 02-01-T4.** T4 is a blocking human-verify checkpoint that must be run on
the REPO tree with the user, with restoration proved by `git diff --exit-code`. What follows was
run in a throwaway `/tmp` copy of `scripts/` + `.github/foundry-version` during T3, purely to
avoid committing an assertion that cannot fail. The repo tree was never mutated.

All four failure modes fire, and each fires DIFFERENTLY:

| Perturbation (scratch copy) | Exit | Message class |
|---|---|---|
| last char of `FOUNDRY_COMMIT` changed to `…a3` | 1 | "the forge on this box is NOT the pinned toolchain", quotes EXPECTED commit and full ACTUAL `forge --version` |
| `FOUNDRY_VERSION=` line deleted | 1 | `FOUNDRY_VERSION: ERROR: FOUNDRY_VERSION is unset or empty in .github/foundry-version` — a missing-variable error, not a mismatch |
| `forge` removed from `PATH` | 1 | "could not run \`forge --version\` (exit status 127) … This is NOT a version mismatch" |
| `FOUNDRY_COMMIT` shortened to `b0a9dd9` (`--check-format`) | 1 | "not a full 40-character lowercase hex SHA" |

The third row is the one the two-variable capture buys: a `forge` that cannot start reports as
absent, not as the wrong version.

---

## Wiring (02-01-T5)

`justfile` recipe `foundry-pin` -> `./scripts/foundry-pin.sh` (full local assertion, no flag).
`.github/workflows/ci.yml` seam job -> `./scripts/foundry-pin.sh --check-format`, placed as the
FIRST runnable step (line 42, immediately after `actions/checkout@v5` at line 29), well before the
cache restore at line 57. One script, two callers, identical path.

`grep -ci 'foundryup\|foundry-toolchain' .github/workflows/ci.yml` -> `0`. No Foundry install step
was added to CI, by design.

### UNVERIFIED on this box: `just foundry-pin`

`just` is **not installed** on this machine — `command -v just` is empty and it is absent from
`/usr/bin`, `~/.cargo/bin`, `~/.local/bin` and the nix profile; `pacman -Q just` reports the
package is not installed. So the T5 acceptance criterion "`just foundry-pin` exits 0" is
**unverified here**, not verified-and-passing. What IS verified is that the recipe body invokes
the identical string CI would, and that `./scripts/foundry-pin.sh` itself exits 0 (see T3). This
gap applies equally to the Phase 1 recipes (`just seam`, `just drift`, …) — CI never invokes
`just`, it calls the scripts directly, so nothing in the gate depends on it.

---

## 02-01-T4 — the pin assertion was made to FIRE, on the repo tree

Run inline with the user. This supersedes the `/tmp` scratch sanity check recorded earlier, which
explicitly did NOT satisfy T4.

| Stage | Tree state | exit | Message class |
|---|---|---|---|
| CONTROL | clean | **0** | `PASS: forge matches the pin -- v1.5.1 at commit b0a9dd9…` |
| NEGATIVE | last char of `FOUNDRY_COMMIT` changed to `…a3` | **1** | version mismatch |
| CONTRAST | `FOUNDRY_VERSION` line deleted | **1** | **missing variable — a different failure** |
| CONTRAST (`--check-format`) | same | **1** | same missing-variable error, so CI catches it too |
| RESTORE | `git checkout` | — | `git diff --exit-code = 0` (byte-identical) |
| post-restore | clean | **0** | PASS |

### Why CONTRAST is the stage that matters

NEGATIVE alone cannot distinguish "the guard fired for the reason we think" from "the guard exits 1
at anything". The two failure messages are unmistakably different — a commit mismatch that prints
EXPECTED vs ACTUAL, versus a `: "${VAR:?}"` unset-variable error naming the variable. Same shape as
01-04's seam negative test, where CONTRAST separated "the guard fired" from "the package name was
bad".

### The NEGATIVE message, verbatim

```
ERROR: the forge on this box is NOT the pinned toolchain.
       EXPECTED commit: b0a9dd9ceda36f63e2326ce530c10e6916f4b8a3
       ACTUAL `forge --version`:
         forge Version: 1.5.1-stable
         Commit SHA: b0a9dd9ceda36f63e2326ce530c10e6916f4b8a2
       Fix by installing the pin, not by editing it:
         foundryup --install 1.5.1
       Editing the pin changes what every measurement in this repo is scoped to, and
       must match cfmm-vol-markets' own pin (their CI-05).
```

The remediation advice matters: the tempting fix for a red pin is to edit the pin. That silently
re-scopes every measurement in the repo. The message says so at the moment someone is about to.

---

## Finding: `just` is NOT installed on this box — and Phase 1 never noticed

Discovered while verifying 02-01-T5.

```
$ command -v just
(absent)  — not in /usr/bin, ~/.cargo/bin, ~/.local/bin, or the nix profile; `pacman -Q just` reports not installed
```

**Consequences, stated honestly:**

1. **T5's criterion "`just foundry-pin` exits 0" is UNVERIFIED**, not satisfied. What IS verified:
   the recipe body is the identical string CI runs modulo the flag, and `./scripts/foundry-pin.sh`
   exits 0 directly.
2. **CI does not depend on `just`.** Its only two occurrences in `ci.yml` are prose in comments;
   every gate calls `scripts/*.sh` directly. Verified by reading both matches.
3. **Phase 1 carried `just`-based acceptance criteria that could never run.** `01-06-PLAN.md:480`
   has `<automated>… && just --list | grep -q 'image-run'</automated>` and `:485` requires
   "`just --list` lists `image` and `image-run`". The current `justfile` contains
   `default, seam, seam-negative, build, test, drift, foundry-pin` — **there is no `image` or
   `image-run` recipe.** That criterion was neither met nor flagged.
4. No FALSE claim was recorded: `01-SUMMARY.md` and `01-01-PROBE-NOTES.md` make no assertion that
   any `just` recipe was run. The gap is an unverified criterion, not a fabricated result.

**This is instrument failure #10, and it is ours.** The pattern is the familiar one: a check that
could not execute at all, in a spot nobody executed it. Distinct from the earlier nine only in that
the instrument was *absent* rather than *mis-scoped*.

**Not fixed here.** Adding the missing `image`/`image-run` recipes and installing `just` is Phase 1
gap-closure, deliberately not smuggled into Phase 2. Recorded in STATE.md blockers.

---

## 02-01-T6 — CI green, and the pin costs nothing

Run `33171542201` on `JMSBPP/evm-spec-bridge@develop`, commit `aed92a1`. **All three jobs success.**

| Job | Conclusion | Duration | Phase 1 baseline |
|---|---|---|---|
| seam | success | **145 s** | 125 s |
| build | success | **427 s** | 440 s |
| image | success | **56 s** | — |

### Step-level, seam job — the +20 s is NOT the pin

| # | Step | Duration |
|---|---|---|
| 2 | `actions/checkout@v5` | 2 s |
| **3** | **Foundry pin well-formedness (DIST-06)** | **0 s** |
| 4 | `haskell-actions/setup@v2` | **117 s** |
| 6 | Restore Stack cache BEFORE the guard | 11 s |
| 7 | Seam guard (CFMM-01) | 1 s |
| 8 | Prove the guard fires | 2 s |

The pin step is **0 s**, as predicted — it reads one small file and does no I/O beyond that. The
seam job's rise from the 125 s Phase 1 baseline is `haskell-actions/setup` taking 117 s this run
against 106 s previously: **runner variance in a step both jobs already paid for**, not a cost the
pin introduced. Recorded this way rather than as "seam got slower", because the job-level number
alone would have supported that wrong conclusion.

The pin step runs 3rd, immediately after checkout — so a malformed pin fails before the 117 s
toolchain setup is spent.

---

## Instrument failure #11 — `gh run list` returned `[]` for the wrong repo

While verifying T6, `gh run list --branch develop` returned an empty array. That reads as
"CI did not run".

It was not. `gh repo view` resolves this checkout to **`d2p-finance/evm-spec-bridge`** — the
CANONICAL repo — while the push went to `origin`, the **fork** `JMSBPP/evm-spec-bridge`. Canonical
has no Actions runs because, by DIST-03's design, nothing is ever pushed to it directly.

```
$ gh repo view --json nameWithOwner -q .nameWithOwner
d2p-finance/evm-spec-bridge          <- NOT where we pushed

$ git remote -v
origin    https://github.com/JMSBPP/evm-spec-bridge.git      (push)
upstream  https://github.com/d2p-finance/evm-spec-bridge.git (push)
```

`gh run list --repo JMSBPP/evm-spec-bridge` immediately showed the run.

**This is the same shape as Phase 1's `gh api` 404**, which meant a missing OAuth scope and read as
a missing package. Both are cases where a tool answered a DIFFERENT question than the one asked and
returned something indistinguishable from a substantive negative. There an authorization artefact
wore the costume of an existence claim; here a repo-resolution artefact wore the costume of
"no CI ran".

**Rule, carried forward:** in this repo every `gh` invocation must pass `--repo
JMSBPP/evm-spec-bridge` explicitly. The fork/canonical split that DIST-03 exists to enforce is
exactly what makes bare `gh` commands ambiguous here.

---

## 02-01 — plan complete

DIST-06's mechanism exists and has been observed to fail. Surviving artifacts:
`.github/foundry-version`, `scripts/foundry-pin.sh`, one `justfile` recipe, one CI step.
Everything else in Phase 2 is throwaway.

---

## 02-02-T2 — the spike is a self-contained Stack project

`spike/` has its own `stack.yaml` and is NOT listed in the root `stack.yaml`. Consequence: CI's
`build` job never compiles warp/wai or their transitive closure, and deletion in 02-05 is
`rm -rf spike/` plus one `justfile` recipe rather than a five-step cleanup (remove packages entry,
regenerate .cabal, re-run the drift gate, re-run the seam guard). Code that is annoying to delete
does not get deleted -- it gets adopted.

The snapshot block is byte-identical to the root's, confirmed mechanically:

```
$ diff <(sed -n '/^snapshot:/,/^  size:/p' stack.yaml) \
       <(sed -n '/^snapshot:/,/^  size:/p' spike/stack.yaml)
$ echo $?
0
```

`extra-deps: []` -- warp-3.4.9, wai-3.2.5, http-types-0.12.6, aeson, bytestring and text are all
present in LTS 24.55, so the spike pins nothing of its own.

`spike/` is deliberately NOT in `.gitignore`; the files are committed so the 02-05 deletion shows up
as a visible diff:

```
$ git check-ignore spike/README.md; echo "exit=$?"
exit=1                                   <- not ignored

$ git diff --exit-code stack.yaml stack-core.yaml .github/workflows/ci.yml; echo "exit=$?"
exit=0                                   <- root project untouched
```

---

## 02-02-T3 — the stub: hardcoded payload, echoed id, loopback bind, required port

`spike/stub-server/app/Main.hs`, 56 lines. Four properties, each with a reason:

**1. The payload is EVEN-nibble.** It was generated mechanically rather than typed, precisely
because a hand-typed run of zeros is where an odd nibble count comes from:

```
$ printf '%064x' 42
000000000000000000000000000000000000000000000000000000000000002a
$ echo -n "$(printf '%064x' 42)" | wc -c
64
```

64 hex characters after `0x` -- even, all `[0-9a-f]`, integer value 42, one 32-byte EVM word. An
odd count is not valid hex and falls into a different `json_value_to_token` coercion branch
(PITFALLS.md:82), which would invalidate the whole spike without necessarily turning the test red
in an obvious way. NOTE: the payload literal written out in the 02-02 plan's `<action>` block is
60 zeros + `2a` = 62 characters, NOT 64. The plan's own instruction to "count it, do not assume"
caught its own example. The committed value is the 64-character one.

**2. Bound to 127.0.0.1 and nothing else.**

```
$ grep -c '0\.0\.0\.0' spike/stub-server/app/Main.hs
0
$ ss -ltn | grep 8547
LISTEN 0      4096       127.0.0.1:8547       0.0.0.0:*
```

The `0.0.0.0:*` on the right is the PEER-address column (any remote may connect); the local bind
address is `127.0.0.1:8547`, which is what alloy's `guess_local_url` requires in order to apply
`no_proxy`. This is the check curl cannot make: a wrong bind still answers curl on localhost
perfectly while also being reachable from the network.

**3. Port is required; there is no default.**

```
$ stack --stack-yaml spike/stack.yaml run stub-server
usage: stub-server PORT   (PORT is required; there is no default)
exit=1
```

**4. The id is echoed.** alloy correlates a response to its request by id.

```
$ curl -sS -i -X POST http://127.0.0.1:8547 -H 'content-type: application/json' \
    -d '{"jsonrpc":"2.0","id":7,"method":"spec_health","params":[]}'
HTTP/1.1 200 OK
Transfer-Encoding: chunked
Date: Fri, 28 Aug 2026 13:28:04 GMT
Server: Warp/3.4.9
Content-Type: application/json

{"jsonrpc":"2.0","id":7,"result":"0x000000000000000000000000000000000000000000000000000000000000002a"}
```

`"id":7`, not 1 -- so the echo is real and not the fallback accidentally agreeing. The fallback was
exercised separately: a body with no `"id"`, and a body that is not JSON at all, both return
`"id":1`.

Request log on the stub's stdout (this is what makes a red `forge test` in 02-03 diagnosable):

```
[stub] listening on 127.0.0.1:8547
[stub] path="/" body-bytes=59 echoed-id=7
```

After the process was stopped, `ss -ltn | grep 8547` returned nothing (exit 1) -- port released.

**Build:** `stack --stack-yaml spike/stack.yaml build` exits 0. `-Wall` produced NO warnings for
`Main` -- the compile went `[1 of 2] Compiling Main` straight to `[2 of 2] Compiling
Paths_spike_stub_server` with nothing between. The warnings visible in the build output are all
`-Wdeprecations` from inside the `warp-3.4.9` dependency's own modules, not from our source.

### Finding: the spike is NOT entirely invisible to the root gates

`scripts/hpack-drift.sh` ends with `git status --porcelain -- '*.cabal'`, and that glob is
REPO-WIDE. The freshly generated `spike/stub-server/spike-stub-server.cabal` therefore turned
`just drift` red as an untracked generated artifact:

```
$ ./scripts/hpack-drift.sh
ERROR: untracked or unstaged .cabal files -- generated artifacts must be committed
?? spike/stub-server/spike-stub-server.cabal
drift exit=1
```

Resolved by committing it, which is the repo's stated policy for generated .cabal files anyway. It
lives inside `spike/`, so 02-05's deletion is still `rm -rf spike/` -- but the claim "the spike is
invisible to the root project" is now precisely: invisible to `stack build`, `stack-core.yaml` and
`ci.yml`, NOT invisible to the repo-wide `*.cabal` glob in the drift gate.

---

## 02-02-T5 — the `spike-server` recipe, and one criterion that stays UNVERIFIED

Added to `justfile`:

```
spike-server PORT="8547":
    stack --stack-yaml spike/stack.yaml run stub-server -- {{PORT}}
```

with a comment above it naming 02-05 as where both the directory and the recipe are removed, and
stating why server-start and test-run stay separate recipes.

**`just --list | grep spike-server` is UNVERIFIED.** `just` is not installed on this box:

```
$ which just
which: no just in (...)
```

This is the SAME honest gap already recorded for 02-01-T5 -- the justfile is written and read as
the CI-mirroring source of truth, but no `just` binary has ever executed it here. What WAS verified
is the recipe's payload: line 41 was extracted from the file, `{{PORT}}` substituted with the
default, and the resulting command run directly.

```
$ sed -n '41p' justfile | sed 's/^ *//; s/{{PORT}}/8547/'
stack --stack-yaml spike/stack.yaml run stub-server -- 8547

$ curl ... -o /dev/null -w 'http=%{http_code}\n' ...
http=200
$ ss -ltn | grep 8547
LISTEN 0      4096       127.0.0.1:8547       0.0.0.0:*
```

So: the COMMAND the recipe runs is verified to start a listener on `127.0.0.1:8547`. That `just`
parses the recipe, exposes it in `--list`, and expands `{{PORT}}` as expected is asserted from the
justfile's syntax alone and remains untested. The recipe body uses 4-space indentation, matching
every existing recipe in the file.

After the process was stopped the port was released (`ss -ltn | grep 8547` exit 1), and the drift
gate is green again now that the spike's .cabal is committed:

```
$ ./scripts/hpack-drift.sh
PASS: committed .cabal files match package.yaml
```

---

## 02-02-T4 — the stub answers, AND it listens nowhere else

Run inline with the user, independently of the agent's own verification.

### Two claims, two instruments, because one has a blind spot

| Instrument | Question it answers | Result |
|---|---|---|
| `curl` on localhost | does it answer? | HTTP 200, `id:7` echoed, `0x…2a` result |
| `ss -ltn` | **where** is it bound? | `LISTEN 0 4096 127.0.0.1:8547 0.0.0.0:*` |
| `curl` to the host's LAN IP | is it reachable off-loopback? | **refused, exit 7** |

`curl` on localhost cannot distinguish a correct `127.0.0.1` bind from a wrong `0.0.0.0` bind — a
server bound to all interfaces answers that exact request identically. Hence `ss`, and hence the
third row.

The `0.0.0.0:*` in the `ss` output is the **peer** column (any remote may connect *to the socket*);
the local bind is `127.0.0.1:8547`. Read the columns, not the substring.

**Negative check, the decisive one:**
```
host global IP: 192.168.1.37
curl: (7) Failed to connect to 192.168.1.37 port 8547 — Could not connect to server
```
Refused from the LAN interface while answering on loopback. This is the evidence `curl` alone
could not produce.

### Payload arithmetic, computed not eyeballed

```
echoed id      : 7   (sent 7)
hex chars      : 64
even nibbles   : True
decodes to     : 42
== 32 bytes    : True
```

Even nibble count matters: an odd-length hex string falls into a DIFFERENT Foundry coercion branch
(`PITFALLS.md:82`), which would silently invalidate the whole spike.

### Teardown
Port released after stop; `git status --porcelain` clean.

---

## Two findings from 02-02 worth carrying

### 1. The payload literal in 02-02-PLAN.md was WRONG — 62 characters, not 64

The plan's `<action>` block printed `0000…002a` with 60 zeros. Correct is `printf '%064x' 42` =
62 zeros + `2a`. Measured:

```
plan literal length: 62
correct length:      64
```

**The plan's own instruction caught the plan's own error** — the `<action>` said "verify the nibble
count is EVEN and the total is 64 hex characters before committing — count it, do not assume." The
executing agent counted, found 62, and used the correct value. Had the instruction said only "use
this literal", an odd-nibble payload would have shipped and the spike would have measured the wrong
coercion branch.

This is an argument for writing the *invariant* alongside the value, not the value alone.

### 2. The spike is NOT fully isolated — `hpack-drift.sh` globs `*.cabal` repo-wide

02-02-T1 claimed the isolated-project layout makes the spike invisible to the root project.
**Partly false.** `scripts/hpack-drift.sh:11` runs:

```
git status --porcelain -- '*.cabal'
```

That glob is repo-wide, so the freshly generated `spike/stub-server/spike-stub-server.cabal` turned
the drift gate RED until it was committed. Verified after the fix: `PASS: committed .cabal files
match package.yaml`, exit 0.

**Accurate statement of the isolation:** the spike is invisible to `stack build`, to
`stack-core.yaml`'s seam guard, and to `ci.yml` — but **visible to the drift gate**. Deletion is
still `rm -rf spike/`, and the .cabal goes with it, so 02-05 is unaffected in substance. But
02-05-T2 must confirm the drift gate is green AFTER deletion, not merely that the tree is clean.

Recorded rather than quietly corrected: an isolation claim that was 3/4 true is exactly the kind of
thing that gets remembered as 4/4.

---

## `just` installed — three phases of unverifiable criteria resolved

`just 1.52.0` installed via `pacman -S just` with user permission, 2026-08-28. Every criterion
previously recorded as UNVERIFIED was then actually run:

| Criterion | Source | Result |
|---|---|---|
| `just foundry-pin` exits 0 | 02-01-T5 | **PASS**, exit 0 |
| `just seam` exits 0 | 01-05 | **PASS**, exit 0 |
| `just drift` exits 0 | 01-05 | **PASS**, exit 0 |
| `just --list` shows `spike-server` | 02-02-T5 | **PASS** |
| `just --list \| grep -q 'image-run'` | **01-06-PLAN.md:480** | **WAS FAILING** — recipes absent |

### The Phase 1 gap was real, and is now closed

`01-06-PLAN.md:480` carries an `<automated>` check ending `just --list | grep -q 'image-run'`, and
`:485` requires "`just --list` lists `image` and `image-run`". Neither recipe existed. The criterion
had never been met and had never been flagged, because the instrument to check it was not installed.

Added to `justfile`:
```
image:      docker build -f docker/Dockerfile -t evm-spec-bridge:local .
image-run:  docker run --rm evm-spec-bridge:local --version
```

The local tag is fixed rather than computed: CI derives a lowercase, slash-free ref from
`github.repository`, which is not reproducible off a runner. Same Dockerfile, same context, same
smoke command.

Verified by EXECUTION, not by listing:
```
$ just image-run
docker run --rm evm-spec-bridge:local --version
evm-spec-bridge-transport 0.1.0.0
exit=0
```

### What this episode actually demonstrates

The check that would have caught this was written down correctly in 01-06 and could not run.
Nine of Phase 1's instrument failures were checks pointed at the wrong thing; this one is a check
pointed at the right thing by a tool that was absent — and absence produced silence rather than an
error. `just: command not found` never appeared in any gate, because no gate invokes `just`.

**Rule:** a criterion phrased against a tool must be accompanied by evidence the tool exists. An
uninstallable check is indistinguishable from a passing one when nobody runs it.

---

## Push gates — MEASURED

| Where | Gate | Blocking? |
|---|---|---|
| `JMSBPP/evm-spec-bridge@develop` (fork) | `on: [push, pull_request]` — CI runs on every push AND every PR | **NO.** `gh api …/branches/develop/protection` → **404 Branch not protected**. CI is advisory here; a red run does not undo a push that already happened |
| `d2p-finance/evm-spec-bridge@main` (canonical) | required checks `['seam','build','image']`, `strict: true`, PR reviews required, `enforce_admins: true`, force-push disabled | **YES.** This is DIST-03's mechanism, and 01-09 observed a direct push being refused |

So: work flows freely on the fork with CI as feedback, and canonical is genuinely gated. Worth
stating plainly because "we have a CI gate" is ambiguous between the two, and only one of them
can stop a bad change.

---

# 02-03 — `vm.rpc` REACHES A HASKELL SERVER (the thing nobody had done)

Run inline with the user. Pin asserted first: `PASS: forge matches the pin -- v1.5.1 at commit
b0a9dd9ceda36f63e2326ce530c10e6916f4b8a2`, exit 0.

**Conditions:** forge 1.5.1-stable / `b0a9dd9`, solc 0.8.34, warp 3.4.9 on `127.0.0.1:8547`,
single host (this box), loopback only, low-level `address(vm).call` form, no forge-std.

## 02-03-T4 — the measurement

`forge test` exit **0**, `2 passed; 0 failed; 0 skipped`.

### Raw returndata, verbatim — 96 bytes

```
0x0000000000000000000000000000000000000000000000000000000000000020   <- head offset = 32
  0000000000000000000000000000000000000000000000000000000000000020   <- length      = 32
  000000000000000000000000000000000000000000000000000000000000002a   <- payload     = 42
```

That is the layout of `abi.encode(bytes)`.

- `abi.decode(ret, (bytes))` **SUCCEEDED**
- decoded length **32**, value `0x…2a`
- `keccak256(decoded) == keccak256(expected)` **held**

### Return-path shape — stated carefully, because it is easy to over-read

PITFALLS.md:103 measured that on 1.5.1 the raw returndata is `abi.encode(<coerced value>)`, **not**
`abi.encode(<bytes>)`. Our result IS wrapped as `abi.encode(bytes)`.

**This is NOT a disagreement.** Our stub returns a 64-hex-char (even-nibble) `0x` string, which
Foundry coerces to `DynSolValue::Bytes`. For this payload the coerced value **is** `bytes`, so
`abi.encode(<coerced value>)` and `abi.encode(<bytes>)` are the same 96 bytes. This reproduces
PITFALLS' own passing row and nothing more.

**What this measurement does NOT establish, and Phase 3 must not infer:**
- nothing about the `uint256` / `int256` / tuple coercion rows
- nothing about whether wrapping is universal across payload shapes
- nothing about the `master` vs `1.5.1` wrapping difference — **still unverified**

It confirms that the hex-envelope discipline (`PITFALLS.md:82`) delivers a decodable, byte-exact
round trip against warp. That is the load-bearing claim, and it holds.

## 02-03-T5 — the green is NOT vacuous

Server stopped, port confirmed free, identical test re-run:

```
forge test exit = 1                                   <- RED
[FAIL: vm.rpc reverted -- see -vvv for CheatcodeError body] test_vmRpcReachesWarp()
  └─ [Revert] vm.rpc: "spec_health": error sending request for url (http://127.0.0.1:8547/)
selector present in errdata: 0xeeaa9e6f                <- CheatcodeError(string)
Suite result: FAILED. 1 passed; 1 failed; 0 skipped
```

Test counts non-zero in both runs (2 total). `forge test` reporting "0 tests passed" exits 0, so
the COUNT is checked, not only the exit status.

This simultaneously re-confirms the measured `try`/`catch` finding on our own stack: a dead endpoint
produces a cheatcode revert carrying `0xeeaa9e6f` with a non-empty string body.

### A live specimen of the false-green shape, found by accident

`test_rawShapeIsRecorded()` **PASSES with the server down.** It is an observation-only probe that
asserts nothing, so it is green whether or not the oracle is alive. That is intentional here — its
job is to keep the wire shape visible even when the assertion test fails.

But it is exactly the shape of the failure this project exists to prevent: **a test that passes
regardless of whether the oracle answered.** Worth keeping as a concrete example. The suite goes
red only because `test_vmRpcReachesWarp` asserts something.

## Instrument notes from 02-03

1. **`-vvv` does not print traces for PASSING tests on 1.5.1** — only for failing ones. The raw
   bytes are visible only at `-vvvv`. A `-vvv` run of a green suite shows no returndata at all, so
   a measurement taken at `-vvv` would silently record nothing. `just spike-test` stays at `-vvv`
   (per plan); use `-vvvv` when capturing bytes.
2. **Hand-rolled `console.log` never appears in a "Logs:" section at any verbosity** on 1.5.1
   (tried both `staticcall` and `call`). Events are the record; console was removed.
3. **`vm.rpc` redacts its URL in traces** as `"<rpc url>"`. The real endpoint is confirmed only via
   the stub's own request log and the connection-refused message.
4. **Two acceptance criteria are now satisfied partly by WORDING, not only by substance.**
   `grep -c 'via_ir\|optimizer' spike/forge/foundry.toml` and the "no typed `= vm.rpc(`" grep were
   both initially tripped by *comments explaining what we deliberately do not do*. Rewording the
   comments cleared them. The substance is correct — those options are genuinely unset and the call
   is genuinely low-level — but the checks are weaker than they look: they measure text, not
   configuration. A better criterion would read effective config (`forge config --json`) rather
   than grep source. Recorded rather than fixed; noted for Phase 3's criteria design.

---

# 02-04-T2 / T5 implementation notes

**Scope of this section: what was BUILT, and the self-checks that prove the instrument
works.** It is NOT the T3 Content-Type matrix and NOT the T4 envelope result — those are
recorded separately, inline with the user, under their own headings.

## 02-04-T2 — the stub learned three Content-Type modes

`spike/stub-server/app/Main.hs` now takes an OPTIONAL second positional argument:

```
usage: stub-server PORT [MODE]
  PORT is required; there is no default.
  MODE is the response Content-Type mode; it defaults to `json`.
  valid MODEs: json, text, none
    json  -> Content-Type: application/json
    text  -> Content-Type: text/plain
    none  -> no Content-Type header at all
```

Design points, each of them load-bearing for the matrix rather than decorative:

1. **One body function, no mode parameter.** `responseBody :: BL.ByteString -> BL.ByteString`
   cannot see the mode. Byte-identity across rows is therefore a property of the code, not a
   promise in a comment. The mode reaches only `modeHeaders`.
2. **`CtNone` is an EMPTY header list**, not a deletion — `responseLBS` emits the list it is
   given. Whether warp then adds one of its own is a question for `curl -i`; see below.
3. **No fallback on a bad mode.** `stub-server 8547 bogus` exits 1 and prints the usage. A
   typo that silently ran the `json` row while the notes said `text` would invalidate a row
   with no trace, so this is a hard failure by design.
4. **The mode is logged at startup AND on every request**, so a transcript can be checked
   against what actually ran:
   `[stub] listening on 127.0.0.1:8547 ct-mode=none`
   `[stub] ct-mode=none path="/" body-bytes=59 echoed-id=7 resp-bytes=102`

`grep -c '0\.0\.0\.0' spike/stub-server/app/Main.hs` → `0`. The loopback-only bind is intact.

### Wire check — `curl -sS -i`, verbatim, one stub run per mode

Request in every case:
`POST http://127.0.0.1:8547` with `content-type: application/json` and body
`{"jsonrpc":"2.0","id":7,"method":"spec_health","params":[]}`.

```
--- mode json ---
HTTP/1.1 200 OK
Transfer-Encoding: chunked
Date: Fri, 28 Aug 2026 13:57:57 GMT
Server: Warp/3.4.9
Content-Type: application/json

{"jsonrpc":"2.0","id":7,"result":"0x000000000000000000000000000000000000000000000000000000000000002a"}
```

```
--- mode text ---
HTTP/1.1 200 OK
Transfer-Encoding: chunked
Date: Fri, 28 Aug 2026 13:57:57 GMT
Server: Warp/3.4.9
Content-Type: text/plain

{"jsonrpc":"2.0","id":7,"result":"0x000000000000000000000000000000000000000000000000000000000000002a"}
```

```
--- mode none ---
HTTP/1.1 200 OK
Transfer-Encoding: chunked
Date: Fri, 28 Aug 2026 13:57:57 GMT
Server: Warp/3.4.9

{"jsonrpc":"2.0","id":7,"result":"0x000000000000000000000000000000000000000000000000000000000000002a"}
```

**Warp 3.4.9 does NOT insert a default `Content-Type`.** The `none` row is genuinely
header-absent on the wire — four response headers instead of five, and the only one missing
is the one under test. This was read off raw `curl -i` output, not inferred from the Haskell.
No workaround was needed.

### Body byte-identity — by `cmp`, not by eye

```
cmp body_json body_text  -> exit 0
cmp body_json body_none  -> exit 0
cmp body_text body_none  -> exit 0

102 body_json   sha256 8f80ef6a6e50f450fee0f1a6e462e88211030a8f40e2749d820a00bd40166af2
102 body_text   sha256 8f80ef6a6e50f450fee0f1a6e462e88211030a8f40e2749d820a00bd40166af2
102 body_none   sha256 8f80ef6a6e50f450fee0f1a6e462e88211030a8f40e2749d820a00bd40166af2
```

Same length, same hash, `cmp` silent. One variable in the experiment: the header.

## 02-04-T5 — `just spike-matrix`

Added to the root `justfile`. Order and failure policy:

- `./scripts/foundry-pin.sh` runs FIRST and its failure ABORTS with a message saying no row
  was measured. Same for a failed `stack build` or a stub that never binds the port — those
  are broken instruments, not measurements.
- Then, per mode `json`/`text`/`none`: start the stub, wait for the port to accept, print the
  response headers from `curl -i`, run `cd spike/forge && forge test -vvv`, print
  `-- MODE <m>: forge test EXIT STATUS = <n>` explicitly, stop the stub, continue.
- **A non-zero `forge test` does not abort the loop.** The probe has no expected outcome, and
  aborting on the first red row would discard the two rows that answer the other two
  questions. The recipe ends with a summary naming which modes passed and which failed.
- The recipe's own exit status is 0 whenever all three rows RAN. That is deliberate and is
  stated in its output: a red row is DATA, so the per-row EXIT STATUS lines are the result,
  not the recipe's exit code.

Implementation detail worth keeping: the recipe runs the built binary DIRECTLY, resolved via
`stack path --local-install-root`, rather than through `stack run`. Under `stack run`, `$!` is
stack's wrapper PID and `kill` can leave the listener holding the port, which would silently
make the NEXT row measure the PREVIOUS row's server.

`just --list` now shows `spike-matrix PORT="8547"`.

---

# 02-04 — Content-Type matrix and the hex envelope

**Conditions for everything below:** forge 1.5.1-stable / `b0a9dd9`, solc 0.8.34, warp 3.4.9 on
`127.0.0.1:8547`, Linux, single host, loopback, `vm.rpc` path (NOT `vm.parseJson` — see the
`convert_to_bytes` note). Pin asserted before each measurement.

## 02-04-T3 — Content-Type matrix — MEASURED

Body byte-identical across all three rows: 102 bytes, sha256
`8f80ef6a6e50f450fee0f1a6e462e88211030a8f40e2749d820a00bd40166af2`, verified with `cmp` in all
three pairings. Same bytes, three headers, one difference.

| mode | header observed on the wire (`curl -i`) | `forge test` exit | verdict |
|---|---|---|---|
| `json` | `Content-Type: application/json` | **0** | pass |
| `text` | `Content-Type: text/plain` | **0** | pass |
| `none` | *(header absent — 4 headers, not 5)* | **0** | pass |

For `none`, warp 3.4.9 did **not** insert a default; absence was read off raw `curl -i` output, not
inferred from the Haskell.

### Verdict: `ARCHITECTURE.md:612` is RETIRED

> "Does alloy's HTTP transport enforce a `Content-Type` on the response? Not verified. Send
> `application/json` regardless. **LOW confidence** that it is optional."

**It is optional.** alloy accepts `application/json`, `text/plain`, and no Content-Type header at
all, on this version and this path. The last LOW-confidence transport item is closed.

We will still send `application/json`, because being correct costs nothing and this result is
scoped to one version. But a missing or wrong Content-Type is **not** a failure mode we need to
design around, and it is not a candidate explanation when something else breaks.

**What this does NOT establish:** one host, one OS, one observation per row; nothing about proxies,
HTTP/2, or the consumer's runner.

## 02-04-T4 — the hex envelope, byte-exact — MEASURED, including the Address branch

Scope extended mid-plan (user-approved) after `gams-evm-transport` measured that on the
**`vm.parseJson`** path a 32-byte hex string coerces to `bytes32` and `abi.decode(ret,(bytes))`
REVERTS, and a 20-byte one coerces to `address`. Our rule rested on `convert_to_bytes` collapsing
all three branches — `[SOURCE]` plus exactly ONE measured case. The Address branch was unmeasured.

### Case A — 32-byte payload (control)

```
raw returndata, 96 bytes:
  0000…0020   offset = 32
  0000…0020   length = 32
  0000…002a   payload = 42
abi.decode(ret,(bytes)) -> 32 bytes, keccak matched.  2 passed.
```

### Case B — 20-byte payload, the Address branch — NEW

Payload `1111111111111111111111111111111111111111` (40 nibbles = 20 bytes):

```
raw returndata, 96 bytes:
  0000000000000000000000000000000000000000000000000000000000000020   offset = 32
  0000000000000000000000000000000000000000000000000000000000000014   length = 0x14 = 20
  1111111111111111111111111111111111111111 000000000000000000000000   20 bytes + 12 pad
```

**`convert_to_bytes` DOES collapse `Address` → `Bytes`, and preserves the true length of 20.** It
is not widened to 32 and not reinterpreted as an address on the Solidity side.
`abi.decode(ret,(bytes))` succeeded and yielded 20 bytes; `test_vmRpcReachesWarp` then failed
correctly on the equality assertion, because the payload is not the 32-byte encoding of 42 — a
*content* failure, not a *shape* failure, which is exactly the discrimination we wanted.

### Consequence

The hex-envelope rule (`PITFALLS.md:82`) holds on the `vm.rpc` path for BOTH the 20-byte/Address
and 32-byte/FixedBytes branches. `gams-evm-transport`'s "pin your payload length or avoid 20 and 32
bytes" hazard is **real on `vm.parseJson` and does not transfer to `vm.rpc`** — because
`convert_to_bytes` (`FEATURES.md:27`, `evm/fork.rs:535-546`) runs on the rpc path only.

**A measurement is scoped to its CODE PATH as much as to its version.** `vm.rpc` and `vm.parseJson`
give different answers for identical JSON. Every coercion row in our research is `vm.rpc`-scoped
unless it says otherwise, and this must be labelled wherever those rows are reused.

### Odd-nibble and non-hex payloads are REJECTED by the stub, not padded

```
$ stub-server 8547 json abc     -> exit 1, "ODD nibble count (3) ... lands in the STRING branch"
$ stub-server 8547 json zzzz    -> exit 1, "must be bare hex, no 0x prefix"
```

Silently padding an odd-length payload would convert a length bug into a *coercion* bug — the odd
string leaves the bytes branch entirely and lands in the value-dependent string branch (measured by
`gams-evm-transport` on parseJson; consistent with `PITFALLS.md:63` here).

## Resolved: the `echoed-id=0` / two-requests observation

Flagged as unexplained by the executing agent. Both parts are benign and one is a validated design
choice:

- **Two requests per run** = two test functions, each making one `vm.rpc` call. Expected.
- **alloy sends `"id":0`**, not 1. Measured: `2 echoed-id=0`.

02-02's plan text said "the id will almost certainly be 1 — but 'almost certainly' is an
assumption, and echoing costs four lines." **The assumption was wrong and the echo absorbed it.**
Had the stub hard-coded `id:1`, we would be relying on alloy not checking correlation. Cheap
defensive choice, vindicated by measurement.
