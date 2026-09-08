{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Stand-alone echo HEVM peer for forge ffi smoke: dials RELAY_SOCK / --sock
-- and reflects @echo@ params as the JSON-RPC result.
module Main (main) where

import Bridge.Relay.Wire
  ( RpcRequest (..)
  , RpcResponse (RpcResult)
  , decodeRequest
  , encodeResponse
  )
import Control.Concurrent (threadDelay)
import Control.Exception (IOException, catch, try)
import Control.Monad (when)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
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
import System.Environment (getArgs, lookupEnv)
import System.Exit (die)
import System.IO
  ( BufferMode (LineBuffering)
  , IOMode (ReadWriteMode)
  , hFlush
  , hSetBuffering
  )

main :: IO ()
main = do
  args <- getArgs
  sock <- resolveSock args
  case sock of
    Nothing -> die "fake-hevm-echo: missing --sock PATH or RELAY_SOCK"
    Just path -> runEcho path

resolveSock :: [String] -> IO (Maybe FilePath)
resolveSock ("--sock" : p : _) = pure (Just p)
resolveSock (_ : rest) = resolveSock rest
resolveSock [] = lookupEnv "RELAY_SOCK"

runEcho :: FilePath -> IO ()
runEcho sockPath = do
  sock <- connectRetrying sockPath 50
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

connectRetrying :: FilePath -> Int -> IO Socket
connectRetrying path attempts = do
  when (attempts <= 0) $ die $ "fake-hevm-echo: could not connect to " <> path
  result <-
    try
      ( do
          s <- socket AF_UNIX Stream defaultProtocol
          connect s (SockAddrUnix path)
          pure s
      ) ::
      IO (Either IOException Socket)
  case result of
    Right s -> pure s
    Left _ -> threadDelay 100000 >> connectRetrying path (attempts - 1)
