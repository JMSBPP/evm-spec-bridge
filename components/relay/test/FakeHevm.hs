{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | A minimal scripted HEVM stand-in for relayd integration tests: dials the
-- daemon's data-plane Unix socket and replies to @echo@ requests by
-- reflecting their params back as the result.
module FakeHevm (runEchoHevm, connectAndHangUp) where

import Bridge.Relay.Wire
  ( RpcRequest (..)
  , RpcResponse (..)
  , decodeRequest
  , encodeResponse
  )
import Control.Exception (IOException, catch, try)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
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

connectRetrying :: FilePath -> Int -> IO Socket
connectRetrying path n = do
  sock <- socket AF_UNIX Stream defaultProtocol
  (connect sock (SockAddrUnix path) >> pure sock) `catch` \(e :: IOException) ->
    if n <= 0
      then ioError e
      else threadDelay 20000 >> connectRetrying path (n - 1)
