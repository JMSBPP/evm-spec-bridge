---
phase: 02-transport-spike-throwaway
status: complete
completed: 2026-08-28
plans: 5
requirements: [DIST-06]
---

# Phase 2 Summary — Transport Spike (Throwaway)

**`vm.rpc` reaches a Haskell `warp` server. Measured, on the version the consumer pins.**

That is the sentence the whole phase existed to make true, and nobody had made it true before —
every prior transport finding was taken against a non-Haskell stub oracle in `/tmp/orctest`.

## Goal vs outcome

> Confirm that a Haskell `warp` server can be the thing on the other end of `vm.rpc`, and pin the
> Foundry toolchain in a form that can go red.

Both achieved. The phase also **shrank correctly**: three of its four ORIGINAL criteria were already
satisfied before it began, and the fourth named a file that structurally cannot satisfy it. Rather
than perform work already done, the criteria were amended and the originals preserved with their
disposition.

## Success criteria — verdict against the AMENDED criteria

| # | Criterion | Verdict | Evidence |
|---|---|---|---|
| 1 | `forge test` green through `vm.rpc` against a **Haskell warp** stub, on `v1.5.1`/`b0a9dd9` | **MET** | 2 passed; raw returndata 96 B; decode byte-exact |
| 2 | Content-Type answered by observation: json / text-plain / **absent** | **MET** | Three rows, byte-identical body, all exit 0 |
| 3 | Pin in a mechanism that **can fail**, asserted where each side can see | **MET** | Assertion observed failing two distinguishable ways; CI step 0 s |
| 4 | Hex envelope survives coercion **byte-exact** | **MET, and extended** | 32-byte AND 20-byte/Address branches both measured |
| 5 | Spike deleted; only the pin and the measurements survive | **MET** | See 02-05 |

## The measurements

### Content-Type is NOT enforced — `ARCHITECTURE.md:612` RETIRED

Body byte-identical across all three rows (102 bytes, sha256
`8f80ef6a6e50f450fee0f1a6e462e88211030a8f40e2749d820a00bd40166af2`, `cmp` verified in every
pairing). Only the header varied.

| mode | header observed on the wire | `forge test` exit |
|---|---|---|
| `json` | `Content-Type: application/json` | **0** |
| `text` | `Content-Type: text/plain` | **0** |
| `none` | *absent — 4 headers, not 5* | **0** |

warp 3.4.9 inserted no default for `none`; absence was read from raw `curl -i`, not inferred from
source. **alloy does not enforce a response Content-Type.** We still send `application/json` —
being correct costs nothing and this is one version — but it is no longer a failure mode to design
around, nor a candidate explanation when something else breaks.

### Return-path shape — agrees with research, but does NOT discriminate it

32-byte payload, raw returndata **96 bytes**: offset `0x20`, length `0x20`, payload. That is
`abi.encode(bytes)` layout, and `abi.decode(ret,(bytes))` succeeded with `keccak256` matching.

`PITFALLS.md:103` measured the returndata as `abi.encode(<coerced value>)`, **not**
`abi.encode(<bytes>)`. **This is not a contradiction.** Our payload is an even-nibble hex string
that coerces to `DynSolValue::Bytes`, so for this shape the two expressions denote the same 96
bytes. **Phase 3 must not read this as evidence that wrapping is universal** — it says nothing
about the uint256 / int256 / tuple rows, and the `master`-vs-`1.5.1` wrapping difference remains
**unverified**.

### The hex envelope holds on BOTH branches — including the one we had not measured

Scope extended mid-plan (user-approved) after `gams-evm-transport` measured that on the
**`vm.parseJson`** path a 32-byte hex coerces to `bytes32` (and `abi.decode(...,(bytes))` REVERTS)
and a 20-byte hex coerces to `address`. Our rule rested on `convert_to_bytes` collapsing all three
branches — `[SOURCE]` plus exactly one measured case.

| payload | raw returndata | decoded |
|---|---|---|
| 32 bytes (`…002a`) | 96 B — offset 32, **length 32** | 32 B, keccak matched |
| **20 bytes (`0x1111…`)** | 96 B — offset 32, **length 0x14 = 20**, + 12 pad | 20 B, true length preserved |

**`convert_to_bytes` collapses `Address` → `Bytes` and preserves the true length.** The envelope
rule (`PITFALLS.md:82`) now holds on the `vm.rpc` path by measurement on both branches.

**A measurement is scoped to its CODE PATH as much as to its version.** `vm.rpc` and `vm.parseJson`
give different answers for identical JSON, because `convert_to_bytes` (`FEATURES.md:27`,
`evm/fork.rs:535-546`) runs on the rpc path only. Every coercion row in our research is
`vm.rpc`-scoped unless stated, and must be labelled wherever reused.

### The pin (DIST-06)

`.github/foundry-version` mirrors the consumer's byte-for-byte (`v1.5.1` /
`b0a9dd9ceda36f63e2326ce530c10e6916f4b8a2` / installer `a27902e…`), their requirement CI-05.
`scripts/foundry-pin.sh` asserts the binary locally and well-formedness in CI.

**Observed failing, on the real tree, in two distinguishable ways:**

| stage | exit | failure class |
|---|---|---|
| CONTROL | 0 | PASS |
| NEGATIVE — corrupt commit | 1 | version mismatch, prints EXPECTED vs ACTUAL |
| CONTRAST — delete a value | 1 | **unset-variable — a different error** |
| restore | — | `git diff --exit-code` = 0 |

CONTRAST is what separates "the guard fired" from "the guard exits 1 at anything".

`foundry.toml` **cannot** pin a forge version: 111 config keys, the only version-bearing one is
`evm_version` (the EVM hardfork). A config file cannot constrain the binary reading it.

### Timings, with conditions

| Quantity | Value | Conditions |
|---|---|---|
| CI pin step | **0 s** | reads one small file |
| seam job | 145 s | of which `haskell-actions/setup` **117 s** (was 106 s in Phase 1 — runner variance, **not** the pin) |
| build job | 427 s | vs 440 s Phase 1 |
| image job | 56 s | |
| `forge test` | ~1.4–2.4 ms suite, ~350–620 ms wall | 2 tests, loopback, warm |
| local image build | exit 0, 129 MB | full `just image` from scratch |

## Consumed, not re-derived

Three questions the roadmap scheduled here were already `[MEASURED]` on the identical binary:
`try`/`catch` catching a cheatcode revert (`0xeeaa9e6f`); the 1.5.1 return-path shape
(`PITFALLS.md:103`); `vm.rpcJson` absent (`PITFALLS.md:134-137`). Re-running them was declined
deliberately. The `try`/`catch` result was nonetheless re-confirmed incidentally by 02-03-T5's
server-down run.

## Corrections made to this phase's own claims

1. **My plan's payload literal was 62 characters, not 64.** The plan's own instruction — *"count
   it, do not assume"* — caught the plan's own error. Had it printed only the literal, an
   odd-nibble payload would have shipped into a different coercion branch. **Write the invariant
   beside the value, not the value alone.**
2. **02-02-T1's isolation claim was 3/4 true.** `scripts/hpack-drift.sh` globs `*.cabal`
   **repo-wide**, so the spike's generated `.cabal` was visible to the drift gate.
3. **My plan assumed alloy sends `id:1`. It sends `id:0`** — measured twice. The plan hedged
   ("'almost certainly' is an assumption, and echoing costs four lines") and the echo absorbed it.
4. **Two acceptance criteria were satisfied partly by WORDING.** `grep -c 'via_ir\|optimizer'` was
   tripped by a *comment explaining what we deliberately do not do*. The substance is correct, but
   the check measures **text, not configuration**. A better criterion reads `forge config --json`.
5. **I captured an exit code through `head -3`** and read `exit=0` for a command that exits 1.
   Re-ran properly. *Exit code before greps — including when the grep is a pager.*

## Instrument failures #10 and #11

**#10 — `just` was not installed, so a correct check never ran.** `01-06-PLAN.md:480` carried
`just --list | grep -q 'image-run'`; neither recipe existed, for two phases, and **absence produced
silence rather than an error** — no gate invokes `just`. Closed this phase: `just` installed, both
recipes added, `just image` built from scratch (exit 0) and `just image-run` verified by execution.
**Rule: a criterion phrased against a tool needs evidence the tool exists.**

**#11 — `gh run list` returned `[]`, which reads as "CI did not run".** `gh` resolves this checkout
to canonical `d2p-finance`, where nothing is ever pushed by DIST-03's design; we push to the fork.
Same shape as Phase 1's `gh api` 404. **Rule: every `gh` command here passes
`--repo JMSBPP/evm-spec-bridge`.**

## Cross-repo — `gams-evm-transport`

An exchange that produced findings neither session had alone.

- My coercion findings exposed a **live defect in their shipped fixture path**: `dQx`/`dQM` ride as
  raw JSON numbers just under 2^64.
- **I under-reported, twice.** I gave them the raw-number hazard but not the string branch, after
  they had told me their fields were strings; and I gave them a coercion table scoped to `vm.rpc`
  without labelling the path, while knowing they were on `parseJson`.
- Their reproduction produced the `convert_to_bytes` reconciliation and the 20-byte case above.
- **Their array finding is the most valuable single result of the exchange, and it lands on our
  Phase 8/9 codegen:** `int256[]` and `uint256[]` have **identical ABI layouts**, so the wire
  carries no signal. `[2613128317657530400, -1]` decodes as `int256[]` → `-1`, and as `uint256[]` →
  `2^256-1`, **with no revert either way**. For scalars a wrong-branch decode reverts; for arrays
  it structurally cannot. **Signedness must be asserted by the schema, because the wire will never
  contradict it.** A generated `uint256[]` against a model that can emit negatives is a defect no
  positive-fixture round-trip will ever catch.
- Brief written to `/tmp/claude-1000/evm-spec-bridge-notes.md`, every claim tagged
  MEASURED / SOURCE / DESIGN-not-built / UNVERIFIED.

## What this phase did NOT prove

- **One host, one OS, one observation per row.** Nothing about the consumer's runner, proxies, or
  HTTP/2.
- **Nothing about load, concurrency or repetition.** A single green `forge test` proves the
  mechanism works once. Phases 4–5 own the rest; do not infer stability from this green.
- **Nothing about non-hex payload shapes.** uint256 / int256 / tuple coercion rows are untouched.
  Boundary values (zero, >2^64, negative, empty, odd-nibble) remain Phase 3 criterion 2.
- **The `master`-vs-`1.5.1` wrapping difference is unverified.**
- **`guess_local_url` / `HTTP_PROXY` remains `[S]`** — source-derived, never observed. We addressed
  as `127.0.0.1` so the spike is unaffected; Phase 6 owns SRV-01.
- **`forge script` vs `forge test` cheatcode availability, `--via-ir` interactions, ordering,
  reentrancy and state visibility** — all untested.

## Carried forward to Phase 3

- The decode path is `abi.decode(ret, (bytes))` on the `vm.rpc` path — **for hex-string payloads**.
- Boundary values must measure **three encodings of the same value** — hex blob, decimal string,
  raw number — not just the hex path. A decimal string under u64 is Solidity `string`; at or above
  u64 it is `uint256`. Quoting does not escape the boundary.
- **Array signedness must be schema-asserted** (see cross-repo above). Owed back to
  `gams-evm-transport`: arrays and signed values on the `vm.rpc` path.
- Acceptance criteria should read effective config, not grep source text.
