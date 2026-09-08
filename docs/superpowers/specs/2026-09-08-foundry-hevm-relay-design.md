# Foundry ↔ HEVM minimal relay

**Date:** 2026-09-08  
**Status:** Draft for review  
**Classification:** Architectural (new peer + duplex Unix transport; does not extend Phase 4 HTTP `oracle-stub`)

## Goal

Establish the **smallest** bidirectional JSON-RPC bridge between Foundry and HEVM:

- Foundry can send arbitrary method + params to HEVM and get a response.
- HEVM can initiate requests toward Foundry; Foundry answers via poll/reply (no push into the EVM).
- Transport is **AF_UNIX**, not HTTP.
- ABI decode/encode stays with HEVM / Solidity — the bridge is opaque bytes/JSON only.

This design does **not** replace the existing Phase 4 HTTP `oracle-stub` / closed `spec_*` registry. That stack remains for current forge integration. The relay is a separate, minimal path.

## Non-goals (v0)

- HTTP / TCP listeners
- Closed method registry (`spec_*`) or three-outcome hex envelope
- Domain logic, ABI codec, or HEVM embedding in-process
- Multi-HEVM, auth, reconnect storms, batch JSON-RPC
- True push of HEVM events into a running EVM without Solidity poll
- Forking Foundry / custom cheatcodes

## Architecture

**Approach: dumb relay only.**

```
┌──────────────┐     vm.ffi      ┌─────────────┐  control sock   ┌──────────┐
│ forge test   │ ──────────────► │ relay (CLI) │ ───────────────►│          │
│ (Solidity)   │                 └─────────────┘                 │  relayd  │
└──────────────┘                                                 │ (daemon) │
                                                                 │          │
┌──────────────┐              JSON-RPC (AF_UNIX data sock)       │          │
│    HEVM      │ ◄──────────────────────────────────────────────►│          │
└──────────────┘                                                 └──────────┘
```

| Component | Role |
|-----------|------|
| `relayd` | Long-lived: bind sockets, one HEVM connection, request correlation, inbound FIFO queue |
| `relay` | Short-lived `vm.ffi` client: `send` / `poll` / `reply` → control sock → `relayd` |
| HEVM | Real peer: dials data sock; decodes inputs; responds; may initiate requests |
| Existing `oracle-stub` | Unchanged; out of scope for this design |

## Call directions

- **Foundry → HEVM:** Solidity `vm.ffi` → `relay send` → `relayd` → JSON-RPC request on data sock → HEVM → response → stdout to Foundry.
- **HEVM → Foundry:** HEVM JSON-RPC request on data sock → `relayd` queues → Solidity `vm.ffi` → `relay poll` → Solidity handles → `relay reply <id> …` → JSON-RPC response to HEVM.

## `ffi` command surface

Binary: `relay`. Socket path(s) from env/flags (e.g. `RELAY_SOCK`).

| Verb | Argv | Behavior | Stdout |
|------|------|----------|--------|
| `send` | `send <method> <params-json>` | Synchronous Foundry→HEVM RPC; wait for matching `id` | raw JSON-RPC `result` (success path) |
| `poll` | `poll` | Non-blocking; pop one HEVM→Foundry request | empty if none; else `<id>\n<method>\n<params-json>` |
| `reply` | `reply <id> <result-json>` | Complete a previously polled request | empty on success |

Rules:

- `params-json` / `result-json` are opaque JSON.
- No ABI in the relay.
- Errors → non-zero exit + short stderr (Foundry surfaces as ffi failure).

## Socket lifecycle

1. **`relayd` binds** the data sock (and control sock). Remove stale sock files on startup.
2. **HEVM dials** the data sock. Single accepted connection per session.
3. Forge runs; each `vm.ffi` spawns `relay`, which talks to `relayd` over the **control** sock.
4. HEVM disconnect → in-flight `send` fails; inbound queue flushed; next connect is a new session.

**Sockets:**

- Data sock: JSON-RPC with HEVM (`RELAY_SOCK`, e.g. `/tmp/fh-relay.sock`).
- Control sock: ffi CLI ↔ daemon (e.g. `RELAY_SOCK` + `.ctl`).

Foundry never opens either sock directly.

## Errors and timeouts

| Failure | Behavior |
|---------|----------|
| `relayd` / control sock missing | `relay` non-zero; stderr `relayd unavailable` |
| HEVM not connected | `send` fails (short wait cap optional); `poll` empty; `reply` fails if no session |
| Disconnect mid-`send` | non-zero; abandon in-flight `id` |
| JSON-RPC `error` from HEVM on `send` | non-zero + stderr with error text; **not** written as success stdout |
| Bad argv / bad JSON | non-zero before touching HEVM |
| `reply` unknown `id` | non-zero `unknown id` |
| `send` timeout | non-zero `timeout`; drop waiter for that `id` |

Defaults:

- `send` timeout: **45s** (align with Foundry `vm.rpc` ceiling); tests may use a shorter flag.
- `poll`: non-blocking.
- Inbound queue: FIFO, bound **64**; overflow → JSON-RPC error to HEVM (do not block forever).
- No silent retry.

## Testing

**Unit:** control framing; FIFO / empty poll / overflow; `id` correlation; unknown reply id; disconnect mid-wait.

**Integration:** fake HEVM dials data sock — answers `send`, injects one inbound request for `poll`→`reply`; timeout path with short test timeout.

**Foundry smoke (optional v0):** one Solidity test via `ffi send` against fake HEVM; one poll/reply path. Real HEVM after relay is green against the double.

Phase 4 HTTP/`spec_*` tests stay on the existing stub; not part of relay v0 gates.

## Implementation process

- Work in a **git worktree under `.worktrees/`** on a dedicated branch.
- Land via **PR** (do not implement on the primary checkout’s dirty `develop` tree as the delivery path).
- Keep `relay` / `relayd` free of `Bridge.Registry` domain methods unless a later explicit decision merges the stacks.

## Success criteria (v0)

1. With `relayd` up and fake HEVM connected, Foundry (or a CLI stand-in) can `send` an arbitrary method+params and receive the `result`.
2. Fake HEVM can enqueue a request; `poll` returns it; `reply` delivers a JSON-RPC response HEVM accepts.
3. Failure modes in the error table are distinguishable via non-zero exit (no silent success).
4. No HTTP, no `spec_*` table, no ABI logic inside relay/relayd.

## Open points (explicitly deferred, not TBD blockers)

- Exact control-sock message framing (length-prefixed JSON vs line protocol) — choose at plan/implement time; must support the three verbs only.
- Language for `relay`/`relayd` (Haskell in-repo vs tiny separate binary) — choose at plan time; prefer whatever keeps the shuttle small and testable.
- Whether HEVM also uses the same JSON-RPC id space as control operations — data plane ids are HEVM↔relayd only; control plane is separate.
