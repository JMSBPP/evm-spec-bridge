{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Main (main) where

import Bridge.Relay.Control
import Bridge.Relay.Daemon (Config (..), runRelayd, safeWrite)
import Bridge.Relay.Queue
import Bridge.Relay.Session
import Bridge.Relay.Types
import Bridge.Relay.Wire
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (async, cancel, wait, withAsync)
import Control.Concurrent.MVar (newEmptyMVar, takeMVar)
import Control.Exception (IOException, bracket, catch)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.Aeson (Value (..))
import Data.List (isInfixOf)
import qualified Data.Vector as V
import FakeHevm
  ( connectAndHangUp
  , connectAndHangUpAfter
  , runEchoHevm
  , runErrorHevm
  , runInboundRequestHevm
  , runOverflowHevm
  , runSilentHevm
  )
import Network.Socket
  ( Family (AF_UNIX)
  , SockAddr (SockAddrUnix)
  , SocketType (Stream)
  , close
  , connect
  , defaultProtocol
  , socket
  , socketToHandle
  )
import System.Directory (getTemporaryDirectory, removeFile)
import System.Environment (getEnvironment, getExecutablePath)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.Process (proc, readCreateProcessWithExitCode, CreateProcess (env))
import System.IO
  ( BufferMode (LineBuffering)
  , IOMode (ReadMode, ReadWriteMode)
  , hClose
  , hFlush
  , hSetBuffering
  , openFile
  , openTempFile
  )
import System.Timeout (timeout)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, (@?=), testCase)

main :: IO ()
main =
  defaultMain $
    testGroup
      "relay"
      [ testGroup
          "queue"
          [ testCase "fifo order" $ do
              let q1 = mustPush (1 :: Int) (emptyQueue 4)
                  q2 = mustPush 2 q1
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
              let q1 = mustPush (1 :: Int) (emptyQueue 1)
              push 2 q1 @?= Left Overflow
          ]
      , testGroup
          "control"
          [ testCase "roundtrip send req" $ do
              let req = SendReq "foo" (Array (V.fromList [Number 1]))
                  bs = encodeControlReq req
              decodeControlReq bs @?= Right req
          , testCase "poll empty resp" $ do
              decodeControlResp "{\"ok\":true,\"kind\":\"pollEmpty\"}\n" @?= Right PollEmpty
          , testCase "error resp" $ do
              decodeControlResp "{\"ok\":false,\"kind\":\"error\",\"error\":\"timeout\"}\n" @?= Right (ControlErr "timeout")
          , testCase "sendOk with a null result round-trips (not misread as ReplyOk)" $ do
              let resp = SendOk Null
              decodeControlResp (encodeControlResp resp) @?= Right resp
          , testCase "pollOk with null id and null params round-trips" $ do
              let resp = PollOk Null "m" Null
              decodeControlResp (encodeControlResp resp) @?= Right resp
          , testCase "pollOk is discriminated from pollEmpty/replyOk purely by kind, not key presence" $ do
              -- Regression for the pre-fix key-probing decoder: a PollOk
              -- with every payload field null used to decode as ReplyOk
              -- because `.:?` treated null id/method/params as absent.
              decodeControlResp
                "{\"ok\":true,\"kind\":\"poll\",\"id\":null,\"method\":\"m\",\"params\":null}\n"
                @?= Right (PollOk Null "m" Null)
          ]
      , testGroup
          "wire"
          [ testCase "request/response line roundtrip" $ do
              let req = RpcRequest (Number 1) "eth_call" (Array (V.fromList [Number 1]))
              decodeRequest (encodeRequest req) @?= Right req
              let resp = RpcResult (Number 1) (String "0xdead")
              decodeResponse (encodeResponse resp) @?= Right resp
          , testCase "response with an explicit null result decodes as success, not error" $ do
              decodeResponse "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":null}\n"
                @?= Right (RpcResult (Number 1) Null)
          , testCase "request with params omitted defaults params to null" $ do
              decodeRequest "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"foo\"}\n"
                @?= Right (RpcRequest (Number 1) "foo" Null)
          , testCase "request with an explicit null params round-trips" $ do
              let req = RpcRequest (Number 1) "foo" Null
              decodeRequest (encodeRequest req) @?= Right req
          ]
      , testGroup
          "session"
          [ testCase "inbound then poll returns same" $ do
              let sess0 = newSession 4
                  req = RpcRequest (Number 1) "eth_call" (Array (V.fromList []))
                  (sess1, effIn) = step (EvInbound req) sess0
                  (_, effPoll) = step EvPoll sess1
              effIn @?= EffNop
              effPoll @?= EffPollResult (Just (PendingInbound (Number 1) "eth_call" (Array (V.fromList []))))
          , testCase "overflow rejects inbound" $ do
              let sess0 = newSession 1
                  req1 = RpcRequest (Number 1) "eth_call" (Array (V.fromList []))
                  req2 = RpcRequest (Number 2) "eth_call" (Array (V.fromList []))
                  (sess1, eff1) = step (EvInbound req1) sess0
                  (_, eff2) = step (EvInbound req2) sess1
              eff1 @?= EffNop
              eff2 @?= EffRejectInbound (Number 2) "queue overflow"
          , testCase "reply unknown id fails" $ do
              let sess0 = newSession 4
                  (_, eff) = step (EvReply (Number 99) (String "ok")) sess0
              eff @?= EffFail "unknown id"
          , testCase "reply known id succeeds after poll" $ do
              let sess0 = newSession 4
                  req = RpcRequest (Number 1) "eth_call" (Array (V.fromList []))
                  (sess1, _) = step (EvInbound req) sess0
                  (sess2, _) = step EvPoll sess1
                  (_, eff) = step (EvReply (Number 1) (String "0xdead")) sess2
              eff @?= EffWriteResponse (RpcResult (Number 1) (String "0xdead"))
          , testCase "disconnect clears queue" $ do
              let sess0 = newSession 4
                  req = RpcRequest (Number 1) "eth_call" (Array (V.fromList []))
                  (sess1, _) = step (EvInbound req) sess0
                  (sess2, _) = step EvDisconnect sess1
                  (_, effPoll) = step EvPoll sess2
              effPoll @?= EffPollResult Nothing
          ]
      , testGroup
          "daemon"
          [ testCase "send echo via relayd" $ do
              sockPath <- freshSockPath
              let ctlPath = sockPath <> ".ctl"
                  cfg = Config sockPath ctlPath 2 64
              bracket (async (runRelayd cfg)) cancel $ \_ -> do
                waitUntilListening ctlPath
                withAsync (runEchoHevm sockPath) $ \_ -> do
                  resp <-
                    sendControlReqRetrying
                      ctlPath
                      (SendReq "echo" (Array (V.fromList [Number 42])))
                      (100 :: Int)
                  resp @?= SendOk (Array (V.fromList [Number 42]))
          , testCase "safeWrite reports a write failure instead of swallowing it" $ do
              -- A handle opened ReadMode is guaranteed to fail synchronously
              -- on hPut with an IOException; this exercises the exact
              -- contract 'sendAndAwait' / the reply path rely on to fail
              -- promptly instead of idling out a full timeout.
              tmp <- getTemporaryDirectory
              (path, h0) <- openTempFile tmp "safewrite-test"
              hClose h0
              h <- openFile path ReadMode
              result <- safeWrite h "hello\n"
              case result of
                Left _ -> pure ()
                Right () -> assertFailure "expected safeWrite to report a write failure"
              hClose h
              removeFile path
          , testCase "send after hevm hangs up fails promptly, not after the full timeout" $ do
              sockPath <- freshSockPath
              let ctlPath = sockPath <> ".ctl"
                  -- A generously large timeout: if the old bug (write
                  -- failures silently swallowed, then waiting the full
                  -- timeout) regressed, this test would take >= 20s instead
                  -- of completing within the 'timeout' bound below.
                  cfg = Config sockPath ctlPath 20 64
              bracket (async (runRelayd cfg)) cancel $ \_ -> do
                waitUntilListening ctlPath
                connectAndHangUp sockPath
                -- Give the daemon a moment to observe the disconnect so the
                -- assertion below isn't itself racing HEVM's hangup.
                threadDelay 100000
                mresp <-
                  timeout
                    3000000
                    (sendControlReq ctlPath (SendReq "echo" (Array (V.fromList [Number 1]))))
                case mresp of
                  Nothing -> assertFailure "send did not return within 3s (waited out the timeout instead of failing promptly)"
                  Just resp -> assertBool ("expected a ControlErr, got " ++ show resp) (isControlErr resp)
          , testCase "send with hevm connected but silent times out around cfgTimeoutSec" $ do
              sockPath <- freshSockPath
              let ctlPath = sockPath <> ".ctl"
                  cfg = Config sockPath ctlPath 2 64
              bracket (async (runRelayd cfg)) cancel $ \_ -> do
                waitUntilListening ctlPath
                withAsync (runSilentHevm sockPath) $ \_ -> do
                  respAsync <-
                    async
                      ( sendControlReqRetrying
                          ctlPath
                          (SendReq "echo" (Array (V.fromList [Number 1])))
                          (100 :: Int)
                      )
                  -- Assert it hasn't resolved well before the 2s timeout
                  -- elapses (i.e. it isn't failing instantly for some other
                  -- reason), then that it does resolve to a timeout error
                  -- shortly after the 2s mark.
                  early <- timeout 1500000 (wait respAsync)
                  early @?= Nothing
                  mresp <- timeout 2500000 (wait respAsync)
                  case mresp of
                    Nothing -> assertFailure "send did not time out within ~2s of hevm staying silent"
                    Just resp -> resp @?= ControlErr "timeout"
          , testCase "hevm disconnect mid-wait fails the pending send promptly" $ do
              sockPath <- freshSockPath
              let ctlPath = sockPath <> ".ctl"
                  -- Generously large timeout: if the disconnect-mid-wait
                  -- fix regressed, this would take >= 20s (waiting out the
                  -- full timeout) instead of failing shortly after HEVM
                  -- hangs up.
                  cfg = Config sockPath ctlPath 20 64
              bracket (async (runRelayd cfg)) cancel $ \_ -> do
                waitUntilListening ctlPath
                withAsync (connectAndHangUpAfter sockPath 300000) $ \_ -> do
                  mresp <-
                    timeout
                      3000000
                      ( sendControlReqRetrying
                          ctlPath
                          (SendReq "echo" (Array (V.fromList [Number 1])))
                          (100 :: Int)
                      )
                  case mresp of
                    Nothing -> assertFailure "send did not return within 3s of hevm disconnecting mid-wait"
                    -- Exact text, not just "some ControlErr": the disconnect
                    -- sentinel must be the plain, unquoted "hevm disconnected"
                    -- token (I5) so it's distinguishable from a genuine HEVM
                    -- error string reaching the same code path.
                    Just resp -> resp @?= ControlErr "hevm disconnected"
          , testCase "hevm JSON-RPC string error is unwrapped, not aeson-quoted" $ do
              sockPath <- freshSockPath
              let ctlPath = sockPath <> ".ctl"
                  cfg = Config sockPath ctlPath 5 64
              bracket (async (runRelayd cfg)) cancel $ \_ -> do
                waitUntilListening ctlPath
                withAsync (runErrorHevm sockPath) $ \_ -> do
                  resp <-
                    sendControlReqRetrying
                      ctlPath
                      (SendReq "fail" (Array V.empty))
                      (100 :: Int)
                  -- runErrorHevm always replies with RpcError _ (String
                  -- "boom"); pre-fix this decoded to ControlErr "\"boom\""
                  -- (aeson-quoted) instead of the unwrapped token below.
                  resp @?= ControlErr "boom"
          , testCase "reply with an unknown id reports unknown id" $ do
              sockPath <- freshSockPath
              let ctlPath = sockPath <> ".ctl"
                  cfg = Config sockPath ctlPath 5 64
              bracket (async (runRelayd cfg)) cancel $ \_ -> do
                waitUntilListening ctlPath
                resp <- sendControlReq ctlPath (ReplyReq (Number 999) (String "ok"))
                resp @?= ControlErr "unknown id"
          , testCase "queue overflow at bound rejects the second inbound over the wire, session still serves send" $ do
              sockPath <- freshSockPath
              let ctlPath = sockPath <> ".ctl"
                  cfg = Config sockPath ctlPath 5 1
              bracket (async (runRelayd cfg)) cancel $ \_ -> do
                waitUntilListening ctlPath
                rejectedVar <- newEmptyMVar
                withAsync (runOverflowHevm sockPath rejectedVar) $ \_ -> do
                  mrej <- timeout 3000000 (takeMVar rejectedVar)
                  case mrej of
                    Nothing -> assertFailure "hevm did not observe an overflow rejection response within 3s"
                    Just resp -> assertBool ("expected an RpcError, got " ++ show resp) (isRpcError resp)
                  resp <-
                    sendControlReqRetrying
                      ctlPath
                      (SendReq "echo" (Array (V.fromList [Number 7])))
                      (100 :: Int)
                  resp @?= SendOk (Array (V.fromList [Number 7]))
          , testCase "hevm inbound request: poll returns it, reply delivers a response hevm observes" $ do
              -- End-to-end proof of spec success criterion 2 (and the fix
              -- for C3): FakeHevm plays the HEVM role and injects one
              -- inbound (HEVM -> Foundry) request; the test plays the
              -- Foundry role, polling for it and replying, and asserts
              -- FakeHevm actually receives the matching response.
              sockPath <- freshSockPath
              let ctlPath = sockPath <> ".ctl"
                  cfg = Config sockPath ctlPath 5 64
              bracket (async (runRelayd cfg)) cancel $ \_ -> do
                waitUntilListening ctlPath
                replyVar <- newEmptyMVar
                let inboundId = Number 99
                    inboundMethod = "eth_blockNumber"
                    inboundParams = Null
                    inboundReq = RpcRequest inboundId inboundMethod inboundParams
                withAsync (runInboundRequestHevm sockPath inboundReq replyVar) $ \_ -> do
                  pollResp <- pollRetrying ctlPath (100 :: Int)
                  case pollResp of
                    PollOk rid method params -> do
                      rid @?= inboundId
                      method @?= inboundMethod
                      params @?= inboundParams
                      replyResp <- sendControlReq ctlPath (ReplyReq rid (String "0x2a"))
                      replyResp @?= ReplyOk
                      mObserved <- timeout 3000000 (takeMVar replyVar)
                      case mObserved of
                        Nothing -> assertFailure "hevm did not observe a reply within 3s"
                        Just observed -> observed @?= RpcResult rid (String "0x2a")
                    other -> assertFailure ("expected PollOk, got " ++ show other)
          ]
      , testGroup
          "cli"
          [ testCase "relay send echo via CLI against a running relayd" $ do
              binPath <- relayBinPath
              sockPath <- freshSockPath
              let ctlPath = sockPath <> ".ctl"
                  cfg = Config sockPath ctlPath 5 64
              bracket (async (runRelayd cfg)) cancel $ \_ -> do
                waitUntilListening ctlPath
                withAsync (runEchoHevm sockPath) $ \_ -> do
                  (code, out, err) <-
                    runRelayCliRetrying binPath sockPath ["send", "echo", "[1]"] (100 :: Int)
                  code @?= ExitSuccess
                  assertBool ("expected stdout to contain 1, got: " ++ show out) ("1" `isInfixOf` out)
                  err @?= ""
          , testCase "relay send with no relayd listening reports relayd unavailable" $ do
              binPath <- relayBinPath
              sockPath <- freshSockPath
              (code, out, err) <- runRelayCli binPath sockPath ["send", "echo", "[1]"]
              code @?= ExitFailure 1
              out @?= ""
              assertBool
                ("expected stderr to mention relayd unavailable, got: " ++ show err)
                ("relayd unavailable" `isInfixOf` err)
          , testCase "relay send with a hevm JSON-RPC error reply exits non-zero with empty stdout" $ do
              binPath <- relayBinPath
              sockPath <- freshSockPath
              let ctlPath = sockPath <> ".ctl"
                  cfg = Config sockPath ctlPath 5 64
              bracket (async (runRelayd cfg)) cancel $ \_ -> do
                waitUntilListening ctlPath
                withAsync (runErrorHevm sockPath) $ \_ -> do
                  (code, out, err) <-
                    runRelayCliRetrying binPath sockPath ["send", "fail", "[]"] (100 :: Int)
                  assertBool ("expected a non-zero exit code, got " ++ show code) (code /= ExitSuccess)
                  out @?= ""
                  assertBool ("expected non-empty stderr, got: " ++ show err) (not (null err))
          , testCase "relay poll returns a hevm inbound request as three-line stdout via CLI" $ do
              binPath <- relayBinPath
              sockPath <- freshSockPath
              let ctlPath = sockPath <> ".ctl"
                  cfg = Config sockPath ctlPath 5 64
              bracket (async (runRelayd cfg)) cancel $ \_ -> do
                waitUntilListening ctlPath
                replyVar <- newEmptyMVar
                let inboundReq = RpcRequest (Number 7) "eth_chainId" Null
                withAsync (runInboundRequestHevm sockPath inboundReq replyVar) $ \_ -> do
                  (code, out, err) <- runRelayCliPollRetrying binPath sockPath (100 :: Int)
                  code @?= ExitSuccess
                  err @?= ""
                  lines out @?= ["7", "eth_chainId", "null"]
          ]
      ]

-- | The 'relay' executable is a sibling build product of this test suite
-- under Stack's per-component build tree
-- (@.../build/relay-test/relay-test@ vs. @.../build/relay/relay@), so we can
-- locate it relative to our own executable path without shelling out to
-- @stack path@ (which would re-enter Stack's project lock).
relayBinPath :: IO FilePath
relayBinPath = do
  selfPath <- getExecutablePath
  let buildDir = takeDirectory (takeDirectory selfPath)
  pure (buildDir </> "relay" </> "relay")

-- | Invoke the built @relay@ binary with @RELAY_SOCK@ pointing at
-- 'sockPath', capturing exit code / stdout / stderr.
runRelayCli :: FilePath -> FilePath -> [String] -> IO (ExitCode, String, String)
runRelayCli binPath sockPath args = do
  baseEnv <- getEnvironment
  let cp = (proc binPath args) {env = Just (("RELAY_SOCK", sockPath) : baseEnv)}
  readCreateProcessWithExitCode cp ""

-- | Like 'runRelayCli' invoking @poll@, but retries while the response is
-- an empty success (exit 0, empty stdout): the FakeHevm inbound request
-- may not have been enqueued by the daemon yet.
runRelayCliPollRetrying :: FilePath -> FilePath -> Int -> IO (ExitCode, String, String)
runRelayCliPollRetrying binPath sockPath n = do
  result@(code, out, _) <- runRelayCli binPath sockPath ["poll"]
  case code of
    ExitSuccess
      | null out && n > 0 -> do
          threadDelay 20000
          runRelayCliPollRetrying binPath sockPath (n - 1)
    _ -> pure result

-- | Like 'runRelayCli', but retries while the daemon reports
-- @"hevm not connected"@, matching 'sendControlReqRetrying' below: the
-- FakeHevm data-plane connection may not have finished dialing in yet.
runRelayCliRetrying :: FilePath -> FilePath -> [String] -> Int -> IO (ExitCode, String, String)
runRelayCliRetrying binPath sockPath args n = do
  result@(code, _, err) <- runRelayCli binPath sockPath args
  case code of
    ExitSuccess -> pure result
    _
      | "hevm not connected" `isInfixOf` err && n > 0 -> do
          threadDelay 20000
          runRelayCliRetrying binPath sockPath args (n - 1)
      | otherwise -> pure result

-- | Unwrap a successful 'push' in test setup where overflow is not the
-- point of the test. A total 'case' (both constructors handled), so this
-- doesn't itself trip @-Wincomplete-uni-patterns@ the way the pattern-bound
-- @let Right q1 = ...@ it replaces did.
mustPush :: a -> Queue a -> Queue a
mustPush x q = case push x q of
  Right q' -> q'
  Left Overflow -> error "mustPush: unexpected overflow in test setup"

isControlErr :: ControlResp -> Bool
isControlErr (ControlErr _) = True
isControlErr _ = False

isRpcError :: RpcResponse -> Bool
isRpcError (RpcError _ _) = True
isRpcError _ = False

-- | Create a fresh, not-yet-existing path suitable for a Unix socket:
-- allocate a uniquely-named temp file (guaranteeing no collision with other
-- concurrent test runs) then remove it so 'bind' can create the socket.
freshSockPath :: IO FilePath
freshSockPath = do
  tmp <- getTemporaryDirectory
  (path, h) <- openTempFile tmp "relayd-test.sock"
  hFlush h
  removeFile path
  pure path

-- | Poll a Unix socket path with short retries until a connection succeeds,
-- then close it. Used to wait for 'runRelayd' to finish binding + listening
-- before dialing in as a client.
waitUntilListening :: FilePath -> IO ()
waitUntilListening path = go (100 :: Int)
  where
    go n = do
      r <- tryConnect `catch` \(_ :: IOException) -> pure False
      if r
        then pure ()
        else
          if n <= 0
            then ioError (userError ("timed out waiting for socket: " ++ path))
            else threadDelay 20000 >> go (n - 1)
    tryConnect = do
      sock <- socket AF_UNIX Stream defaultProtocol
      connect sock (SockAddrUnix path)
      close sock
      pure True

-- | Like 'sendControlReq', but retries while the daemon reports
-- @"hevm not connected"@, i.e. before the data-plane (FakeHevm) side has
-- finished dialing in. Each retry is a fresh short-lived control connection,
-- matching the daemon's one-request-per-connection contract.
sendControlReqRetrying :: FilePath -> ControlReq -> Int -> IO ControlResp
sendControlReqRetrying path req n = do
  resp <- sendControlReq path req
  case resp of
    ControlErr "hevm not connected" | n > 0 -> do
      threadDelay 20000
      sendControlReqRetrying path req (n - 1)
    _ -> pure resp

-- | Poll the control socket, retrying while the queue is still empty: the
-- FakeHevm inbound request may not have reached the daemon's session queue
-- yet. Each retry is a fresh control connection, matching the
-- one-request-per-connection contract.
pollRetrying :: FilePath -> Int -> IO ControlResp
pollRetrying path n = do
  resp <- sendControlReq path PollReq
  case resp of
    PollEmpty | n > 0 -> do
      threadDelay 20000
      pollRetrying path (n - 1)
    _ -> pure resp

-- | Dial the control socket, write one NDJSON request line, read one
-- response line, close.
sendControlReq :: FilePath -> ControlReq -> IO ControlResp
sendControlReq path req = do
  sock <- socket AF_UNIX Stream defaultProtocol
  connect sock (SockAddrUnix path)
  h <- socketToHandle sock ReadWriteMode
  hSetBuffering h LineBuffering
  BS.hPut h (encodeControlReq req)
  hFlush h
  lineBs <- BSC.hGetLine h
  hClose h
  case decodeControlResp lineBs of
    Right resp -> pure resp
    Left err -> ioError (userError ("bad control response: " ++ err))
