---
phase: 02-transport-spike-throwaway
plan: 02-04
status: complete
completed: 2026-08-28
requirements-completed: []
duration: not-instrumented
---

> **BACK-FILLED 2026-08-28**, reconstructed from git history and PROBE-NOTES. This is NOT a contemporaneous record — the plan was executed inline with the user and no summary was written at the time. Measurements quoted here are sourced from the phase notebook; nothing is reconstructed from memory.

**Note on paths.** Everything under the spike directory was deleted in 02-05, so paths named below
no longer exist on disk. The durable record is
`.planning/phases/02-transport-spike-throwaway/02-01-PROBE-NOTES.md`; the phase's one surviving
artifact is `scripts/foundry-pin.sh`.

# 02-04 Summary — Content-Type is not enforced, and the hex envelope holds on both branches

**Three headers over one byte-identical body, all green; and a byte-exact round trip measured on
the 32-byte branch and the previously unmeasured 20-byte/Address branch.**

## Performance

- **Duration:** not-instrumented (executed inline; no timing was captured)
- **Started / Completed:** not recorded
- **Commits:** 4 (`b4cbf6d`, `727a334`, `9daaa07`, `ee1b6b6`)

## Task commits

1. **Teach the spike stub three Content-Type modes over one body** — `b4cbf6d` (feat)
2. **Add a re-runnable spike-matrix recipe over the three modes** — `727a334` (feat)
3. **Record implementation notes and wire-level Content-Type evidence** — `9daaa07` (feat)
4. **Content-Type not enforced (612 RETIRED); Address branch collapses to 20-byte bytes** — `ee1b6b6` (feat)

**Conditions:** forge 1.5.1-stable / `b0a9dd9`, solc 0.8.34, warp 3.4.9 on `127.0.0.1:8547`, Linux,
single host, loopback, **`vm.rpc` path** — not `vm.parseJson`. Pin asserted before each measurement.

## Content-Type matrix — MEASURED

Body byte-identical across all three rows: 102 bytes, sha256
`8f80ef6a6e50f450fee0f1a6e462e88211030a8f40e2749d820a00bd40166af2`, verified with `cmp` in all
three pairings. Same bytes, three headers, one difference.

| mode | header observed on the wire (`curl -i`) | `forge test` exit |
|---|---|---|
| `json` | `Content-Type: application/json` | **0** |
| `text` | `Content-Type: text/plain` | **0** |
| `none` | *absent — 4 headers, not 5* | **0** |

warp 3.4.9 inserted no default for `none`; absence was read off raw `curl -i`, not inferred from
the Haskell.

**`ARCHITECTURE.md:612` is RETIRED** — the last LOW-confidence transport item. alloy does not
enforce a response Content-Type. We still send `application/json`, because being correct costs
nothing and this result is scoped to one version, but it is no longer a failure mode to design
around nor a candidate explanation when something else breaks.

**What this does NOT establish:** one host, one OS, one observation per row; nothing about proxies,
HTTP/2, or the consumer's runner.

## The hex envelope, byte-exact — including the branch we had not measured

Scope extended mid-plan (user-approved) after `gams-evm-transport` measured that on the
**`vm.parseJson`** path a 32-byte hex coerces to `bytes32` (and decoding as `bytes` reverts) and a
20-byte hex coerces to `address`. Our rule had rested on `convert_to_bytes` collapsing all three
branches — source-derived plus exactly one measured case.

| payload | raw returndata | decoded |
|---|---|---|
| 32 bytes (control) | 96 B — offset 32, **length 32** | 32 B, keccak matched |
| **20 bytes (`0x1111…`)** | 96 B — offset 32, **length 0x14 = 20**, + 12 pad | 20 B, true length preserved |

**`convert_to_bytes` collapses `Address` → `Bytes` and preserves the true length of 20** — not
widened to 32, not reinterpreted as an address on the Solidity side. The equality assertion then
failed correctly, because the payload is not the 32-byte encoding of 42 — a *content* failure, not
a *shape* failure, which is exactly the discrimination wanted.

**A measurement is scoped to its CODE PATH as much as to its version.** `vm.rpc` and `vm.parseJson`
give different answers for identical JSON, because `convert_to_bytes` runs on the rpc path only.
Every coercion row in our research is `vm.rpc`-scoped unless stated, and must be labelled wherever
reused. `gams-evm-transport`'s "avoid 20- and 32-byte payloads" hazard is real on `parseJson` and
**does not transfer** to `vm.rpc`.

## Two smaller findings

- **Odd-nibble and non-hex payloads are rejected by the stub, not padded.** Silently padding an
  odd-length payload would convert a length bug into a *coercion* bug, moving it out of the bytes
  branch entirely.
- **alloy sends `"id":0`, not 1** — measured twice. 02-02's plan text said "almost certainly 1, but
  that is an assumption, and echoing costs four lines". The assumption was wrong and the echo
  absorbed it. Cheap defensive choice, vindicated by measurement. The "two requests per run"
  observation is simply two test functions.

## Instrument design worth keeping

The matrix recipe asserts the pin **first** and aborts if the pin, the build, or the port bind
fails — those are broken instruments, not measurements. A red row does **not** abort the loop: the
probe has no expected outcome, and aborting on the first red would discard the two rows answering
the other questions. Per-row exit statuses are the result; the recipe's own exit status only says
that all three rows ran. It also runs the built binary directly rather than through a wrapper,
because killing the wrapper can leave the listener holding the port and silently make the next row
measure the previous row's server.

## Requirements

- **none** — this plan's `requirements` frontmatter is `[]`.
