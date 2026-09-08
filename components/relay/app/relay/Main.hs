{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Short-lived FFI CLI for talking to a running @relayd@ control socket.
--
-- Usage:
--
-- > relay send   <method> <params-json>
-- > relay poll
-- > relay reply  <id-json> <result-json>
--
-- The control socket path is resolved from @--sock PATH@ (if present
-- anywhere in argv) or the @RELAY_SOCK@ environment variable; the control
-- socket itself is @sock <> ".ctl"@, matching @relayd@'s own convention.
module Main (main) where

import Bridge.Relay.Control (decodeControlResp, encodeControlReq)
import Bridge.Relay.Types (ControlReq (..), ControlResp (..))
import Control.Exception (IOException, try)
import Data.Aeson (Value, eitherDecode, encode)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.Socket
  ( Family (AF_UNIX)
  , SockAddr (SockAddrUnix)
  , SocketType (Stream)
  , connect
  , defaultProtocol
  , socket
  , socketToHandle
  )
import System.Environment (getArgs, lookupEnv)
import System.Exit (exitFailure, exitSuccess)
import System.IO
  ( BufferMode (LineBuffering)
  , IOMode (ReadWriteMode)
  , hClose
  , hFlush
  , hPutStrLn
  , hSetBuffering
  , stderr
  , stdout
  )
import System.IO.Error (userError)

-- | A parsed CLI command, independent of where the control socket lives.
data Command
  = CmdSend T.Text Value
  | CmdPoll
  | CmdReply Value Value

main :: IO ()
main = do
  args <- getArgs
  let (sockOverride, rest) = extractSock args
  case parseCommand rest of
    Left err -> die1 err
    Right cmd -> do
      msock <- resolveSock sockOverride
      case msock of
        Nothing -> die1 "missing --sock or RELAY_SOCK"
        Just sockPath -> run (sockPath <> ".ctl") cmd

-- | Pull an optional @--sock PATH@ pair out of argv, wherever it appears,
-- returning the remaining positional arguments untouched.
extractSock :: [String] -> (Maybe String, [String])
extractSock = go
  where
    go [] = (Nothing, [])
    go ("--sock" : v : more) =
      let (_, rest) = go more in (Just v, rest)
    go (a : more) =
      let (s, rest) = go more in (s, a : rest)

resolveSock :: Maybe String -> IO (Maybe String)
resolveSock (Just s) = pure (Just s)
resolveSock Nothing = lookupEnv "RELAY_SOCK"

-- | Parse the subcommand and its positional arguments. Any JSON payload
-- argument is decoded eagerly so bad JSON is reported as a CLI-usage error
-- before we ever touch the socket.
parseCommand :: [String] -> Either String Command
parseCommand ["send", method, paramsStr] =
  CmdSend (T.pack method) <$> parseJSONArg paramsStr
parseCommand ["poll"] = Right CmdPoll
parseCommand ["reply", idStr, resultStr] =
  CmdReply <$> parseJSONArg idStr <*> parseJSONArg resultStr
parseCommand _ =
  Left "usage: relay send <method> <params-json> | relay poll | relay reply <id-json> <result-json>"

parseJSONArg :: String -> Either String Value
parseJSONArg s =
  case eitherDecode (BL.fromStrict (TE.encodeUtf8 (T.pack s))) of
    Left err -> Left ("bad JSON: " ++ err)
    Right v -> Right v

-- | Connect to the control socket, send the request, read and dispatch the
-- single-line response. Any 'IOException' along the way (including a
-- failed connect, i.e. no @relayd@ listening) is reported uniformly as
-- \"relayd unavailable\".
run :: FilePath -> Command -> IO ()
run ctlPath cmd = do
  result <- performRequest ctlPath (toControlReq cmd)
  case result of
    Left (_ :: IOException) -> do
      hPutStrLn stderr "relayd unavailable"
      exitFailure
    Right resp -> emit resp

toControlReq :: Command -> ControlReq
toControlReq (CmdSend method params) = SendReq method params
toControlReq CmdPoll = PollReq
toControlReq (CmdReply rid result) = ReplyReq rid result

performRequest :: FilePath -> ControlReq -> IO (Either IOException ControlResp)
performRequest ctlPath req = try $ do
  sock <- socket AF_UNIX Stream defaultProtocol
  connect sock (SockAddrUnix ctlPath)
  h <- socketToHandle sock ReadWriteMode
  hSetBuffering h LineBuffering
  BS.hPut h (encodeControlReq req)
  hFlush h
  lineBs <- BSC.hGetLine h
  hClose h
  case decodeControlResp lineBs of
    Right resp -> pure resp
    Left err -> ioError (userError ("bad control response: " ++ err))

-- | Map a 'ControlResp' to the exit-code / stdout / stderr contract from
-- the task brief.
emit :: ControlResp -> IO ()
emit (SendOk v) = do
  BSC.hPutStrLn stdout (BL.toStrict (encode v))
  exitSuccess
emit PollEmpty = exitSuccess
emit (PollOk rid method params) = do
  let idEnc = BL.toStrict (encode rid)
      methodBS = TE.encodeUtf8 method
      paramsEnc = BL.toStrict (encode params)
  BS.hPut stdout (idEnc <> "\n" <> methodBS <> "\n" <> paramsEnc <> "\n")
  exitSuccess
emit ReplyOk = exitSuccess
emit (ControlErr e) = do
  hPutStrLn stderr (T.unpack e)
  exitFailure

die1 :: String -> IO ()
die1 msg = hPutStrLn stderr msg >> exitFailure
