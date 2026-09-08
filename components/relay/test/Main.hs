{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Main (main) where

import Bridge.Relay.Control
import Bridge.Relay.Daemon (Config (..), runRelayd)
import Bridge.Relay.Queue
import Bridge.Relay.Session
import Bridge.Relay.Types
import Bridge.Relay.Wire
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (async, cancel, withAsync)
import Control.Exception (IOException, bracket, catch)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.Aeson (Value (..))
import qualified Data.Vector as V
import FakeHevm (runEchoHevm)
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
import System.IO (BufferMode (LineBuffering), IOMode (ReadWriteMode), hClose, hFlush, hSetBuffering, openTempFile)
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
      , testGroup
          "control"
          [ testCase "roundtrip send req" $ do
              let req = SendReq "foo" (Array (V.fromList [Number 1]))
                  bs = encodeControlReq req
              decodeControlReq bs @?= Right req
          , testCase "poll empty resp" $ do
              decodeControlResp "{\"ok\":true,\"empty\":true}\n" @?= Right PollEmpty
          , testCase "error resp" $ do
              decodeControlResp "{\"ok\":false,\"error\":\"timeout\"}\n" @?= Right (ControlErr "timeout")
          ]
      , testGroup
          "wire"
          [ testCase "request/response line roundtrip" $ do
              let req = RpcRequest (Number 1) "eth_call" (Array (V.fromList [Number 1]))
              decodeRequest (encodeRequest req) @?= Right req
              let resp = RpcResult (Number 1) (String "0xdead")
              decodeResponse (encodeResponse resp) @?= Right resp
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
          ]
      ]

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
