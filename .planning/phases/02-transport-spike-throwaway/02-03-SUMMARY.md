---
phase: 02-transport-spike-throwaway
plan: 02-03
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

# 02-03 Summary — `vm.rpc` reaches a Haskell warp server

**`forge test` exit 0, 2 passed, against warp on `127.0.0.1:8547`; raw returndata 96 bytes,
decoded byte-exact. This is the thing nobody had done — every prior transport finding was taken
against a non-Haskell stub oracle.**

## Performance

- **Duration:** not-instrumented (executed inline; no timing was captured)
- **Started / Completed:** not recorded
- **Commits:** 4 (`c694ade`, `1607a1b`, `cacc56f`, `547bfff`)

## Task commits

1. **Minimal solc-pinned forge project, no forge-std** — `c694ade` (feat)
2. **`Spike.t.sol` — low-level vm.rpc call, raw returndata recorded before decode** — `1607a1b` (feat)
3. **`just spike-test` — asserts the foundry pin before running forge test** — `cacc56f` (feat)
4. **vm.rpc reaches warp — 96-byte abi.encode(bytes), red without a server** — `547bfff` (feat)

**Conditions:** forge 1.5.1-stable / `b0a9dd9`, solc 0.8.34, warp 3.4.9 on `127.0.0.1:8547`, single
host, loopback only, low-level `address(vm).call` form, no forge-std. The pin was asserted first.

## The measurement — raw returndata, 96 bytes

```
0x0000…0020   <- head offset = 32
  0000…0020   <- length      = 32
  0000…002a   <- payload     = 42
```

`abi.decode(ret, (bytes))` **succeeded**; decoded length 32; `keccak256(decoded) == keccak256(expected)`
held. That is the layout of `abi.encode(bytes)`.

### Stated carefully, because it is easy to over-read

`PITFALLS.md:103` measured the 1.5.1 returndata as `abi.encode(<coerced value>)`, **not**
`abi.encode(<bytes>)`. **This is not a disagreement.** The stub returns an even-nibble 64-hex-char
string, which Foundry coerces to `DynSolValue::Bytes`, so for this payload the two expressions
denote the same 96 bytes. This reproduces that passing row and nothing more.

**What it does NOT establish:** nothing about the `uint256` / `int256` / tuple coercion rows,
nothing about whether wrapping is universal across payload shapes, and the `master`-vs-`1.5.1`
wrapping difference remains **unverified**.

## The green is not vacuous

Server stopped, port confirmed free, identical test re-run:

```
forge test exit = 1
[FAIL: vm.rpc reverted] test_vmRpcReachesWarp()
  └─ [Revert] vm.rpc: "spec_health": error sending request for url (http://127.0.0.1:8547/)
selector in errdata: 0xeeaa9e6f
```

Test counts are non-zero in both runs, and the count is checked rather than only the exit status —
`forge test` reporting "0 tests passed" exits 0. This also incidentally re-confirmed the measured
`try`/`catch` finding on our own stack.

## A live specimen of the false-green shape, found by accident

`test_rawShapeIsRecorded()` **passes with the server down.** It is observation-only and asserts
nothing, which is intentional — its job is to keep the wire shape visible when the assertion test
fails. But it is exactly the shape of failure this project exists to prevent: *a test that passes
regardless of whether the oracle answered.* Kept as a concrete example.

## Instrument notes

1. **`-vvv` does not print traces for passing tests on 1.5.1** — only for failing ones. Raw bytes
   are visible only at `-vvvv`, so a measurement taken at `-vvv` on a green suite would silently
   record nothing.
2. Hand-rolled `console.log` never appears in a Logs section at any verbosity on 1.5.1.
3. **`vm.rpc` redacts its URL in traces** as `"<rpc url>"`; the real endpoint is confirmed only via
   the stub's request log and the connection-refused message.
4. **Two acceptance criteria were satisfied partly by wording.** Greps for `via_ir|optimizer` and
   for a typed `= vm.rpc(` were tripped by *comments explaining what we deliberately do not do*.
   The substance is correct, but the checks measure text, not configuration. A better criterion
   reads `forge config --json`. Recorded, not fixed; noted for Phase 3's criteria design.

## Requirements

- **none** — this plan's `requirements` frontmatter is `[]`. Its output is the measurement, which
  survives in the notebook and the phase summary; the code was deleted in 02-05.
