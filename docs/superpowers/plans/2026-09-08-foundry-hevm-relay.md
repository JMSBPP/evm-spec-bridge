# Foundry–HEVM Relay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a dumb duplex Unix-socket relay (`relayd` + `relay` ffi CLI) so Foundry can send arbitrary JSON-RPC to HEVM and poll/reply to HEVM-initiated requests, with no domain/ABI logic.

**Architecture:** New Stack package `components/relay`. Long-lived `relayd` binds a data AF_UNIX sock (HEVM dials, NDJSON JSON-RPC) and a control sock (`RELAY_SOCK` + `.ctl`). Short-lived `relay` CLI speaks one NDJSON control request/response per invocation for `send` / `poll` / `reply`. Pure session/queue logic is unit-tested; integration uses a fake HEVM peer. Existing `oracle-stub` / `registry` / HTTP transport are untouched.

**Tech Stack:** Haskell (GHC via Stack LTS 24.55 / ghc-9.10.3), `aeson`, `bytestring`, `text`, `network` (Unix sockets), `async`, `stm`, `optparse-applicative`, `tasty` + `tasty-hunit`. No Warp/WAI. No dependency on `evm-spec-bridge-registry` or `evm-spec-bridge-transport`.

**Spec:** `docs/superpowers/specs/2026-09-08-foundry-hevm-relay-design.md`

## Global Constraints

- Work only in a git worktree under `.worktrees/` on a dedicated branch; land via PR (never deliver from the primary dirty `develop` checkout).
- No HTTP, no `spec_*` registry, no ABI codec, no three-outcome envelope inside relay.
- Opaque JSON only for `params` / `result`.
- Single HEVM connection; inbound FIFO bound **64**; `send` default timeout **45s**.
- Control plane and data-plane JSON-RPC `id` spaces are separate.
- Control + data framing: **NDJSON** (one JSON value per line, `\n`-terminated).
- Errors: non-zero process exit + short stderr; never print HEVM `error` objects as success stdout.
- Add `.worktrees/` to `.gitignore` if missing.

---

## File structure (locked)

```
components/relay/
  package.yaml
  src/Bridge/Relay/
    Types.hs       -- Config, ControlReq, ControlResp, PendingInbound, WireId
    Queue.hs       -- pure bounded FIFO
    Session.hs     -- pure correlation + inbound queue transitions
    Control.hs     -- encode/decode control NDJSON lines
    Wire.hs        -- encode/decode data-plane JSON-RPC request/response lines
  app/relayd/Main.hs
  app/relay/Main.hs
  test/Main.hs
  test/FakeHevm.hs -- test helper: dials data sock, scripted replies/inbound
stack.yaml         -- add components/relay
.gitignore         -- .worktrees/
```

Responsibilities:

| File | One job |
|------|---------|
| `Types.hs` | Shared ADTs + defaults (`defaultTimeoutSec = 45`, `defaultQueueBound = 64`) |
| `Queue.hs` | `push` / `pop` with overflow |
| `Session.hs` | Pure state machine for waiters + inbound + disconnect flush |
| `Control.hs` | CLI↔daemon line codec |
| `Wire.hs` | HEVM↔daemon JSON-RPC line codec (opaque params/result) |
| `relayd` | IO: bind, accept, mux STM session, timeouts |
| `relay` | IO: parse argv, one control round-trip, map to exit code/stdout |
| tests | Pure unit + in-process integration with FakeHevm |

---

### Task 0: Worktree + branch

**Files:**
- Create: `.worktrees/foundry-hevm-relay/` (via git worktree)
- Modify: `.gitignore` (ensure `.worktrees/`)

**Interfaces:**
- Consumes: none
- Produces: clean branch (e.g. `feat/foundry-hevm-relay`) checked out under `.worktrees/foundry-hevm-relay`

- [ ] **Step 1: Ensure `.worktrees/` is ignored**

Add to `.gitignore` if absent:

```
.worktrees/
```

- [ ] **Step 2: Create worktree + branch**

Use `superpowers:using-git-worktrees` (or equivalent):

```bash
mkdir -p .worktrees
git fetch origin
git worktree add -b feat/foundry-hevm-relay .worktrees/foundry-hevm-relay develop
cd .worktrees/foundry-hevm-relay
```

- [ ] **Step 3: Confirm clean baseline**

```bash
pwd   # .../evm_spec_rpc/.worktrees/foundry-hevm-relay
git status -sb
```

Expected: on `feat/foundry-hevm-relay`, clean relative to develop tip (plus ignored paths).

- [ ] **Step 4: Commit gitignore if changed**

```bash
git add .gitignore
git commit -m "chore: ignore .worktrees/ for local worktree checkouts"
```

All later tasks execute **inside** `.worktrees/foundry-hevm-relay`.

---

### Task 1: Package scaffold + pure queue

**Files:**
- Create: `components/relay/package.yaml`
- Create: `components/relay/src/Bridge/Relay/Types.hs`
- Create: `components/relay/src/Bridge/Relay/Queue.hs`
- Create: `components/relay/test/Main.hs`
- Modify: `stack.yaml` (add `- components/relay`)

**Interfaces:**
- Consumes: none
- Produces:
  - `defaultTimeoutSec :: Int` (= 45)
  - `defaultQueueBound :: Int` (= 64)
  - `data Queue a`
  - `emptyQueue :: Int -> Queue a`
  - `push :: a -> Queue a -> Either Overflow (Queue a)`
  - `pop :: Queue a -> (Maybe a, Queue a)`
  - `data Overflow = Overflow`

- [ ] **Step 1: Write failing queue tests**

In `components/relay/test/Main.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Bridge.Relay.Queue
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit ((@?=), testCase)

main :: IO ()
main =
  defaultMain $
    testGroup
      "relay"
      [ testGroup
          "queue"
          [ testCase "fifo order" $ do
              let Right q1 = push (1 :: Int) (emptyQueue 4)
                  Right q2 = push 2 q1
                  (a, q3) = pop q2
                  (b, _) = pop q3
              a @?= Just 1
              b @?= Just 2
          , testCase "empty pop" $ do
              let (a, q') = pop (emptyQueue 4 :: Queue Int)
              a @?= Nothing
              let (b, _) = pop q'
              b @?= Nothing
          , testCase "overflow at bound" $ do
              let Right q1 = push (1 :: Int) (emptyQueue 1)
              push 2 q1 @?= Left Overflow
          ]
      ]
```

- [ ] **Step 2: Add package.yaml + stack entry (library stub so tests compile against missing modules will fail)**

`components/relay/package.yaml`:

```yaml
name:        evm-spec-bridge-relay
version:     0.1.0.0
synopsis:    Minimal Foundry–HEVM Unix-socket JSON-RPC relay
license:     BSD-3-Clause
author:      JMSBPP
maintainer:  juan.serranotmf@gmail.com
copyright:   2026 JMSBPP

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
- aeson
- async
- bytestring
- network
- optparse-applicative
- stm
- text

library:
  source-dirs: src

executables:
  relayd:
    main: Main.hs
    source-dirs: app/relayd
    dependencies:
    - evm-spec-bridge-relay
  relay:
    main: Main.hs
    source-dirs: app/relay
    dependencies:
    - evm-spec-bridge-relay

tests:
  relay-test:
    main: Main.hs
    source-dirs: test
    ghc-options:
    - -threaded
    - -rtsopts
    - -with-rtsopts=-N
    dependencies:
    - evm-spec-bridge-relay
    - tasty
    - tasty-hunit
    - aeson
    - bytestring
    - network
    - stm
    - async
    - text
```

Add to `stack.yaml` `packages:`:

```yaml
- components/relay
```

Stub `Types.hs` / `Queue.hs` empty exports so the first compile finds the test module names — or skip stubs and let Step 3 implement.

- [ ] **Step 3: Run tests — expect FAIL (module missing)**

```bash
stack test evm-spec-bridge-relay --fast
```

Expected: compile error `Could not find module Bridge.Relay.Queue` (or missing symbols).

- [ ] **Step 4: Implement Types + Queue**

`Types.hs`:

```haskell
module Bridge.Relay.Types
  ( defaultTimeoutSec
  , defaultQueueBound
  ) where

defaultTimeoutSec :: Int
defaultTimeoutSec = 45

defaultQueueBound :: Int
defaultQueueBound = 64
```

`Queue.hs`:

```haskell
module Bridge.Relay.Queue
  ( Queue
  , Overflow (..)
  , emptyQueue
  , push
  , pop
  ) where

data Overflow = Overflow
  deriving (Eq, Show)

data Queue a = Queue
  { qBound :: Int
  , qItems :: [a] -- front is head
  }
  deriving (Eq, Show)

emptyQueue :: Int -> Queue a
emptyQueue n = Queue {qBound = n, qItems = []}

push :: a -> Queue a -> Either Overflow (Queue a)
push x q
  | length (qItems q) >= qBound q = Left Overflow
  | otherwise = Right q {qItems = qItems q ++ [x]}

pop :: Queue a -> (Maybe a, Queue a)
pop q =
  case qItems q of
    [] -> (Nothing, q)
    (x : xs) -> (Just x, q {qItems = xs})
```

- [ ] **Step 5: Run tests — expect PASS for queue group**

```bash
stack test evm-spec-bridge-relay --fast
```

- [ ] **Step 6: Commit**

```bash
git add stack.yaml components/relay .gitignore
git commit -m "feat(relay): scaffold package and bounded FIFO queue"
```

---

### Task 2: Control NDJSON codec

**Files:**
- Create: `components/relay/src/Bridge/Relay/Control.hs`
- Modify: `components/relay/src/Bridge/Relay/Types.hs`
- Modify: `components/relay/test/Main.hs`

**Interfaces:**
- Consumes: `Types` defaults
- Produces:
  - `data ControlReq = SendReq Text Value | PollReq | ReplyReq Value Value`  
    (`ReplyReq id result` — `id` is JSON value mirroring JSON-RPC id)
  - `data ControlResp = …` (see below)
  - `encodeControlReq :: ControlReq -> ByteString`
  - `decodeControlReq :: ByteString -> Either String ControlReq`
  - `encodeControlResp :: ControlResp -> ByteString`
  - `decodeControlResp :: ByteString -> Either String ControlResp`

`ControlResp` constructors:

```haskell
data ControlResp
  = SendOk Value          -- JSON-RPC result
  | PollEmpty
  | PollOk Value Text Value  -- id, method, params
  | ReplyOk
  | ControlErr Text       -- error token: "timeout" | "relayd unavailable" | ...
```

Wire shapes (one line, no pretty print):

```json
{"op":"send","method":"foo","params":[1]}
{"op":"poll"}
{"op":"reply","id":1,"result":"0xab"}

{"ok":true,"result":"0xab"}
{"ok":true,"empty":true}
{"ok":true,"id":1,"method":"bar","params":[]}
{"ok":true}
{"ok":false,"error":"timeout"}
```

- [ ] **Step 1: Write failing codec tests**

```haskell
testCase "roundtrip send req" $ do
  let req = SendReq "foo" (Array (V.fromList [Number 1]))
      bs = encodeControlReq req
  decodeControlReq bs @?= Right req

testCase "poll empty resp" $ do
  decodeControlResp "{\"ok\":true,\"empty\":true}\n" @?= Right PollEmpty

testCase "error resp" $ do
  decodeControlResp "{\"ok\":false,\"error\":\"timeout\"}\n" @?= Right (ControlErr "timeout")
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
stack test evm-spec-bridge-relay --fast
```

Expected: missing `Bridge.Relay.Control` or missing constructors.

- [ ] **Step 3: Implement Types ADTs + Control codec**

Use `aeson` `object` / `withObject`. Strip a single trailing `\n` on decode; always append `\n` on encode.

- [ ] **Step 4: Run tests — expect PASS**

```bash
stack test evm-spec-bridge-relay --fast
```

- [ ] **Step 5: Commit**

```bash
git add components/relay
git commit -m "feat(relay): NDJSON control request/response codec"
```

---

### Task 3: Data-plane wire codec + pure Session

**Files:**
- Create: `components/relay/src/Bridge/Relay/Wire.hs`
- Create: `components/relay/src/Bridge/Relay/Session.hs`
- Modify: `components/relay/test/Main.hs`

**Interfaces:**
- Consumes: `Queue`, `Types`
- Produces:

```haskell
-- Wire.hs
data RpcRequest = RpcRequest { rpcId :: Value, rpcMethod :: Text, rpcParams :: Value }
data RpcResponse
  = RpcResult { respId :: Value, respResult :: Value }
  | RpcError  { respId :: Value, respError :: Value }

encodeRequest :: RpcRequest -> ByteString
decodeRequest :: ByteString -> Either String RpcRequest
encodeResponse :: RpcResponse -> ByteString
decodeResponse :: ByteString -> Either String RpcResponse

-- Session.hs (pure)
data Session = Session
  { sessInbound :: Queue PendingInbound
  , sessWaiters :: Map Text ()  -- keys = canonical id text; IO layer holds TMVars
  , sessNextId  :: Integer      -- allocate monotonic Int ids for Foundry→HEVM
  , sessAlive   :: Bool
  }

data PendingInbound = PendingInbound
  { pinId :: Value
  , pinMethod :: Text
  , pinParams :: Value
  }

data SessionEvent
  = EvSendAlloc           -- allocate id for outbound send
  | EvOutboundResult Value Value  -- id, result
  | EvOutboundError Value Value   -- id, error
  | EvInbound RpcRequest
  | EvPoll
  | EvReply Value Value   -- id, result
  | EvDisconnect

data SessionEffect
  = EffNop
  | EffAllocatedId Value
  | EffWriteRequest RpcRequest
  | EffWriteResponse RpcResponse
  | EffPollResult (Maybe PendingInbound)
  | EffRejectInbound Value Text  -- id + error message (queue overflow)
  | EffFail Text                 -- e.g. unknown id, no session

step :: SessionEvent -> Session -> (Session, SessionEffect)
```

Rules in `step`:

- `EvSendAlloc` when `not sessAlive` → `EffFail "hevm not connected"`; else bump `sessNextId`, `EffAllocatedId (Number …)`.
- `EvInbound` → `push` queue; on `Overflow` → `EffRejectInbound id "queue overflow"` (session unchanged aside from no push).
- `EvPoll` → `pop`; `EffPollResult`.
- `EvReply` → if matching pending was already popped, IO tracks outstanding reply ids; pure session only validates alive — **keep outstanding reply set in Session**:

```haskell
, sessOutstanding :: Set Text  -- ids handed out by poll, awaiting reply
```

  On poll Just: insert id into outstanding. On reply: if id in outstanding, delete and `EffWriteResponse (RpcResult …)`; else `EffFail "unknown id"`.
- `EvDisconnect` → empty queue, clear outstanding, `sessAlive=False`, `EffFail` only if callers need — effect `EffNop` is fine; IO fails waiters.

- [ ] **Step 1: Write failing tests for wire roundtrip + session fifo/overflow/unknown reply/disconnect**

Cover at least:

1. request/response line roundtrip  
2. inbound then poll returns same  
3. overflow → reject effect  
4. reply unknown id → fail  
5. disconnect clears queue (`poll` empty after)

- [ ] **Step 2: Run — expect FAIL**

```bash
stack test evm-spec-bridge-relay --fast
```

- [ ] **Step 3: Implement Wire + Session**

- [ ] **Step 4: Run — expect PASS**

```bash
stack test evm-spec-bridge-relay --fast
```

- [ ] **Step 5: Commit**

```bash
git add components/relay
git commit -m "feat(relay): JSON-RPC wire codec and pure session state"
```

---

### Task 4: `relayd` daemon (IO)

**Files:**
- Create: `components/relay/app/relayd/Main.hs`
- Create: `components/relay/src/Bridge/Relay/Daemon.hs` (optional but preferred: keep `Main` thin)
- Modify: `components/relay/test/Main.hs` + Create: `components/relay/test/FakeHevm.hs`

**Interfaces:**
- Consumes: `Session.step`, `Control.*`, `Wire.*`, `Types` defaults
- Produces:
  - `runRelayd :: Config -> IO ()`
  - `data Config = Config { cfgDataSock :: FilePath, cfgCtlSock :: FilePath, cfgTimeoutSec :: Int, cfgQueueBound :: Int }`
  - CLI: `relayd --sock PATH [--timeout SEC]` with `cfgCtlSock = cfgDataSock <> ".ctl"`

Behavior:

1. `removePathForcibly` both sock paths; `listen` Unix; accept loop.
2. **Data thread:** accept exactly one HEVM connection (or replace on reconnect: flush via `EvDisconnect` then new alive session). Read NDJSON lines; `decodeRequest` → `EvInbound` or `decodeResponse` → match outbound waiter.
3. **Control thread:** accept many short connections; one req line → one resp line → close.
4. Outbound `send`: allocate id via session; write `RpcRequest` to HEVM; wait on `TMVar` with `threadDelay`/timeout `cfgTimeoutSec`; on timeout respond `ControlErr "timeout"`.
5. HEVM JSON-RPC error → `ControlErr` with compact error text (e.g. aeson-encoded error value), not `SendOk`.
6. Queue overflow → write `RpcError` to HEVM with message `queue overflow`.

- [ ] **Step 1: Write FakeHevm + integration test (failing until daemon exists)**

`FakeHevm.hs`: connect to data sock; for scripted mode:

- On request with method `"echo"`: reply `RpcResult` with params as result.  
- Optionally push one inbound `RpcRequest` id=99 method=`ping` params=`[]`.

Test outline:

```haskell
testCase "send echo via relayd" $ do
  sock <- emptyTempSockPath
  let ctl = sock <> ".ctl"
  bracket (async (runRelayd (Config sock ctl 2 64))) cancel $ \_ -> do
    waitUntilListening ctl
    _ <- async (runEchoHevm sock)  -- dials and serves
    -- dial control: write send req, read SendOk
```

Until daemon exists, test fails to import/`runRelayd`.

- [ ] **Step 2: Run — expect FAIL**

```bash
stack test evm-spec-bridge-relay --fast
```

- [ ] **Step 3: Implement Daemon + relayd Main**

Keep `Main` as parse opts + `runRelayd`.

- [ ] **Step 4: Run — expect PASS including integration**

```bash
stack test evm-spec-bridge-relay --fast
```

- [ ] **Step 5: Manual smoke**

```bash
stack exec -- relayd --sock /tmp/fh-relay-test.sock &
# in another shell, run a tiny Haskell or printf NDJSON against .ctl after starting FakeHevm via test helper / stack ghci
```

Prefer relying on automated integration; manual optional.

- [ ] **Step 6: Commit**

```bash
git add components/relay
git commit -m "feat(relay): relayd Unix daemon with control and HEVM data plane"
```

---

### Task 5: `relay` ffi CLI

**Files:**
- Create: `components/relay/app/relay/Main.hs`
- Modify: `components/relay/test/Main.hs` (process-level tests via `createProcess`)

**Interfaces:**
- Consumes: control codec; env `RELAY_SOCK` or `--sock`
- Produces: executable `relay` with:

```text
relay send   <method> <params-json>
relay poll
relay reply  <id-json> <result-json>
```

Exit / IO mapping:

| ControlResp | exit | stdout | stderr |
|-------------|------|--------|--------|
| `SendOk v` | 0 | `encode v` (compact JSON, no extra newline required beyond one) | empty |
| `PollEmpty` | 0 | empty | empty |
| `PollOk id m p` | 0 | `idEnc <> "\n" <> method <> "\n" <> paramsEnc` | empty |
| `ReplyOk` | 0 | empty | empty |
| `ControlErr e` | 1 | empty | `e` |
| connect fail | 1 | empty | `relayd unavailable` |
| bad argv / JSON | 1 | empty | short reason |

- [ ] **Step 1: Write failing CLI tests**

Start `relayd` + FakeHevm in test; `stack exec relay -- send echo "[1]"` via `readProcessWithExitCode` against built exe path (`$(stack path --local-install-root)/bin/relay`) or `cabal`-style; assert exit 0 and stdout contains `1`.

Also: no daemon → stderr contains `relayd unavailable`, exit ≠ 0.

- [ ] **Step 2: Run — expect FAIL** (binary missing or stub)

```bash
stack build evm-spec-bridge-relay:exe:relay --fast
stack test evm-spec-bridge-relay --fast
```

- [ ] **Step 3: Implement `app/relay/Main.hs`**

Connect Unix `cfgCtlSock`, write `encodeControlReq`, read one line, map to exit.

- [ ] **Step 4: Run — expect PASS**

```bash
stack test evm-spec-bridge-relay --fast
```

- [ ] **Step 5: Commit**

```bash
git add components/relay
git commit -m "feat(relay): ffi CLI send/poll/reply over control socket"
```

---

### Task 6: Failure-path coverage + timeout

**Files:**
- Modify: `components/relay/test/Main.hs`
- Modify: `components/relay/src/Bridge/Relay/Daemon.hs` if gaps appear

**Interfaces:**
- Consumes: `runRelayd`, FakeHevm, `relay` CLI
- Produces: tests proving spec error table

Cases (each assert non-zero or exact stderr token):

1. `send` with HEVM connected but silent → `timeout` within ~2s when `--timeout 2`
2. HEVM returns JSON-RPC `error` → CLI exit ≠ 0; stdout empty
3. `reply` unknown id → `unknown id`
4. queue overflow (bound 1): second inbound without poll → HEVM receives error response; session still serves `send`
5. HEVM disconnect mid-wait → `send` fails (stderr non-empty)

- [ ] **Step 1: Write failing tests for any not already green**

- [ ] **Step 2: Run — expect FAIL on missing behaviors**

```bash
stack test evm-spec-bridge-relay --fast
```

- [ ] **Step 3: Fix daemon/CLI to satisfy**

- [ ] **Step 4: Run — expect PASS**

```bash
stack test evm-spec-bridge-relay --fast
```

- [ ] **Step 5: Commit**

```bash
git add components/relay
git commit -m "test(relay): cover timeout, RPC errors, overflow, disconnect"
```

---

### Task 7: Optional Foundry smoke (ffi)

**Files:**
- Create: `solidity/test/RelaySmoke.t.sol` (or `solidity/test/relay/RelaySmoke.t.sol`)
- Create: `scripts/run-relay-smoke.sh`
- Modify: `justfile` — recipe `relay-smoke` (optional)

**Interfaces:**
- Consumes: built `relay` + `relayd` on `PATH` / absolute path via `vm.env`
- Produces: forge test that:
  1. Assumes `relayd` + echo FakeHevm already running (script starts them)
  2. `vm.ffi` → `["relay","send","echo","[1]"]` (ffi enabled in `foundry.toml` for this smoke only if not already)

Skip this task if ffi is disabled in the pin and enabling it is out of scope — document skip in PR. Spec marks Foundry smoke **optional v0**.

- [ ] **Step 1: Script starts relayd + fake hevm, runs forge test, tears down**

- [ ] **Step 2: Commit if implemented**

```bash
git add solidity scripts justfile
git commit -m "test(relay): optional Foundry ffi smoke against echo HEVM"
```

---

### Task 8: PR

**Files:** none new required beyond prior tasks

- [ ] **Step 1: Push branch from worktree**

```bash
cd .worktrees/foundry-hevm-relay
git push -u origin HEAD
```

- [ ] **Step 2: Open PR**

```bash
gh pr create --title "feat: Foundry–HEVM minimal Unix relay" --body "$(cat <<'EOF'
## Summary
- Add `components/relay` with `relayd` (AF_UNIX JSON-RPC peer) and `relay` (`send`/`poll`/`reply` ffi CLI)
- Pure session/queue + integration tests against fake HEVM; leaves Phase 4 HTTP oracle untouched

## Test plan
- [ ] `stack test evm-spec-bridge-relay --fast`
- [ ] Manual: `relayd --sock /tmp/fh-relay.sock` + fake HEVM + `relay send echo '[1]'`
- [ ] (Optional) `just relay-smoke`

EOF
)"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Dumb relay only; no registry/HTTP | 1–5 (package isolation) |
| `send` / `poll` / `reply` surface | 2, 5 |
| `relayd` binds; HEVM dials; control sock `.ctl` | 4 |
| ffi short-lived CLI | 5 |
| 45s timeout; bound 64; FIFO | 1, 3, 6 |
| Error table / non-zero exits | 5, 6 |
| Unit + fake HEVM integration | 1–6 |
| Optional Foundry smoke | 7 |
| Worktree under `.worktrees/` + PR | 0, 8 |

## Placeholder / consistency review

- Control + data framing fixed as NDJSON (spec open point closed).
- Language fixed as Haskell `components/relay` (spec open point closed).
- `ControlReq` / `ControlResp` / `Session.step` names are consistent across tasks.
- No TBD steps remain.
