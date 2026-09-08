{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | A minimal scripted HEVM stand-in for relayd integration tests: dials the
-- daemon's data-plane Unix socket and replies to @echo@ requests by
-- reflecting their params back as the result.
module FakeHevm
  ( runEchoHevm
  , connectAndHangUp
  , connectAndHangUpAfter
  , runSilentHevm
  , runErrorHevm
  , runOverflowHevm
  ) where

import Bridge.Relay.Wire
  ( RpcRequest (..)
  , RpcResponse (..)
  , decodeRequest
  , decodeResponse
  , encodeRequest
  , encodeResponse
  )
import Control.Concurrent.MVar (MVar, tryPutMVar)
import Control.Exception (IOException, catch, try)
import Data.Aeson (Value (Array, Number, String))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Vector as V
import Control.Concurrent (threadDelay)
import Network.Socket
  ( Family (AF_UNIX)
  , SockAddr (SockAddrUnix)
  , Socket
  , SocketType (Stream)
  , connect
  , defaultProtocol
  , socket
  , socketToHandle
  )
import System.IO (BufferMode (LineBuffering), IOMode (ReadWriteMode), hClose, hFlush, hSetBuffering)

-- | Connect to the relayd data-plane socket at 'sockPath' (retrying briefly
-- until the daemon is listening), then serve @echo@ requests until the
-- connection closes.
runEchoHevm :: FilePath -> IO ()
runEchoHevm sockPath = do
  sock <- connectRetrying sockPath (50 :: Int)
  h <- socketToHandle sock ReadWriteMode
  hSetBuffering h LineBuffering
  loop h
  where
    loop h = do
      result <- try (BSC.hGetLine h) :: IO (Either IOException BS.ByteString)
      case result of
        Left _ -> pure ()
        Right lineBs -> do
          case decodeRequest lineBs of
            Right (RpcRequest rid method params)
              | method == "echo" ->
                  (BS.hPut h (encodeResponse (RpcResult rid params)) >> hFlush h)
                    `catch` \(_ :: IOException) -> pure ()
            _ -> pure ()
          loop h

-- | Connect to the relayd data-plane socket then immediately hang up without
-- serving anything, simulating a HEVM process that dies mid-session. Used to
-- exercise the daemon's disconnect / stale-handle handling.
connectAndHangUp :: FilePath -> IO ()
connectAndHangUp sockPath = do
  sock <- connectRetrying sockPath (50 :: Int)
  h <- socketToHandle sock ReadWriteMode
  hClose h

-- | Like 'connectAndHangUp', but stays connected (without ever reading or
-- replying) for 'delayMicros' before hanging up. Used to simulate HEVM
-- dying *while* the daemon is already blocked awaiting a reply to an
-- in-flight outbound 'send', as opposed to being gone before the send is
-- even attempted.
connectAndHangUpAfter :: FilePath -> Int -> IO ()
connectAndHangUpAfter sockPath delayMicros = do
  sock <- connectRetrying sockPath (50 :: Int)
  h <- socketToHandle sock ReadWriteMode
  threadDelay delayMicros
  hClose h

-- | Connect to the relayd data-plane socket and stay connected, silently
-- discarding every inbound line without ever replying. Used to exercise the
-- daemon's outbound-send timeout: HEVM is present but never answers.
runSilentHevm :: FilePath -> IO ()
runSilentHevm sockPath = do
  sock <- connectRetrying sockPath (50 :: Int)
  h <- socketToHandle sock ReadWriteMode
  hSetBuffering h LineBuffering
  loop h
  where
    loop h = do
      result <- try (BSC.hGetLine h) :: IO (Either IOException BS.ByteString)
      case result of
        Left _ -> pure ()
        Right _ -> loop h

-- | Connect to the relayd data-plane socket and reply to every request with
-- a JSON-RPC error, regardless of method. Used to exercise the
-- HEVM-returns-an-error path (as opposed to a successful result).
runErrorHevm :: FilePath -> IO ()
runErrorHevm sockPath = do
  sock <- connectRetrying sockPath (50 :: Int)
  h <- socketToHandle sock ReadWriteMode
  hSetBuffering h LineBuffering
  loop h
  where
    loop h = do
      result <- try (BSC.hGetLine h) :: IO (Either IOException BS.ByteString)
      case result of
        Left _ -> pure ()
        Right lineBs -> do
          case decodeRequest lineBs of
            Right (RpcRequest rid _ _) ->
              (BS.hPut h (encodeResponse (RpcError rid (String "boom"))) >> hFlush h)
                `catch` \(_ :: IOException) -> pure ()
            Left _ -> pure ()
          loop h

-- | Connect to the relayd data-plane socket and immediately fire two
-- inbound requests back-to-back, with no poll in between, to exercise the
-- bound-1 queue-overflow rejection path from the HEVM side of the wire:
-- the second request should overflow the queue and come back over this
-- same handle as a JSON-RPC error rather than being silently dropped. Any
-- such error response is reported via 'rejectedVar'. Afterward, the
-- connection keeps serving @echo@ requests so the caller can additionally
-- verify the session still functions for outbound sends once the overflow
-- has been handled.
runOverflowHevm :: FilePath -> MVar RpcResponse -> IO ()
runOverflowHevm sockPath rejectedVar = do
  sock <- connectRetrying sockPath (50 :: Int)
  h <- socketToHandle sock ReadWriteMode
  hSetBuffering h LineBuffering
  BS.hPut h (encodeRequest (RpcRequest (Number 1) "cheat1" (Array V.empty)))
  hFlush h
  BS.hPut h (encodeRequest (RpcRequest (Number 2) "cheat2" (Array V.empty)))
  hFlush h
  loop h
  where
    loop h = do
      result <- try (BSC.hGetLine h) :: IO (Either IOException BS.ByteString)
      case result of
        Left _ -> pure ()
        Right lineBs -> do
          case decodeResponse lineBs of
            Right resp@(RpcError _ _) -> do
              _ <- tryPutMVar rejectedVar resp
              loop h
            _ -> do
              case decodeRequest lineBs of
                Right (RpcRequest rid method params)
                  | method == "echo" ->
                      (BS.hPut h (encodeResponse (RpcResult rid params)) >> hFlush h)
                        `catch` \(_ :: IOException) -> pure ()
                _ -> pure ()
              loop h

connectRetrying :: FilePath -> Int -> IO Socket
connectRetrying path n = do
  sock <- socket AF_UNIX Stream defaultProtocol
  (connect sock (SockAddrUnix path) >> pure sock) `catch` \(e :: IOException) ->
    if n <= 0
      then ioError e
      else threadDelay 20000 >> connectRetrying path (n - 1)
