-- THROWAWAY. Deleted in plan 02-05. Nothing outside spike/ may depend on this.
-- The envelope is hand-written on purpose: json-rpc's Data layer arrives in Phase 3/4.
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import           Data.Aeson                 (Value (Number, Object), decode, encode)
import qualified Data.Aeson.KeyMap          as KM
import qualified Data.ByteString.Lazy       as BL
import qualified Data.ByteString.Lazy.Char8 as BLC
import           Network.HTTP.Types         (ResponseHeaders, status200)
import           Network.Wai                (Application, rawPathInfo, responseLBS,
                                             strictRequestBody)
import           Network.Wai.Handler.Warp   (defaultSettings, runSettings, setHost, setPort)
import           System.Environment         (getArgs)
import           System.Exit                (exitFailure)
import           System.IO                  (BufferMode (LineBuffering), hPutStrLn,
                                             hSetBuffering, stderr, stdout)
import           Text.Read                  (readMaybe)

-- 32-byte big-endian ABI encoding of decimal 42: 64 hex chars, an EVEN nibble count.
-- Odd would not be valid hex and would fall into a different Foundry coercion branch.
payload :: BL.ByteString
payload = "000000000000000000000000000000000000000000000000000000000000002a"

-- The Content-Type probe (02-04). THREE modes, ONE body.
--
-- The body bytes below are built by `responseBody` and are IDENTICAL in every mode --
-- the header list is the only thing that varies. If the body varied too, a difference
-- in Foundry's behaviour could not be attributed to the header, and the experiment
-- would have two variables in it.
--
-- This probe has NO expected outcome. Both "alloy enforces a response Content-Type"
-- and "it does not" are valid results; neither is a defect in the stub.
data CtMode
  = CtJson  -- Content-Type: application/json
  | CtText  -- Content-Type: text/plain      -- asks: is a WRONG type rejected?
  | CtNone  -- no Content-Type header at all -- asks: is a MISSING header rejected?
  deriving (Eq, Show)

-- An unrecognised mode is a HARD failure, never a silent fallback to `json`: a typo
-- that quietly ran the json row while the notes recorded `text` would invalidate the
-- matrix without leaving a trace.
parseMode :: String -> Maybe CtMode
parseMode "json" = Just CtJson
parseMode "text" = Just CtText
parseMode "none" = Just CtNone
parseMode _      = Nothing

modeName :: CtMode -> String
modeName CtJson = "json"
modeName CtText = "text"
modeName CtNone = "none"

-- `responseLBS` emits exactly the header list it is given and adds no Content-Type of
-- its own, so CtNone is an EMPTY list rather than a deletion. Whether warp nonetheless
-- puts one on the wire is a question for `curl -i`, not for this comment.
modeHeaders :: CtMode -> ResponseHeaders
modeHeaders CtJson = [("Content-Type", "application/json")]
modeHeaders CtText = [("Content-Type", "text/plain")]
modeHeaders CtNone = []

-- alloy correlates a response to its request by id, so echo it. Number 1 is the
-- fallback when the body is not an object or carries no "id".
echoedId :: BL.ByteString -> Value
echoedId body = case decode body of
  Just (Object o) -> maybe (Number 1) id (KM.lookup "id" o)
  _               -> Number 1

-- The single source of the response bytes. Takes no CtMode, by construction: that is
-- what makes "byte-identical across modes" a property of the code and not a promise.
responseBody :: BL.ByteString -> BL.ByteString
responseBody body =
  BL.concat ["{\"jsonrpc\":\"2.0\",\"id\":", encode (echoedId body), ",\"result\":\"0x", payload, "\"}"]

app :: CtMode -> Application
app mode req respond = do
  body <- strictRequestBody req
  let out = responseBody body
  putStrLn $ "[stub] ct-mode=" ++ modeName mode
          ++ " path=" ++ show (rawPathInfo req)
          ++ " body-bytes=" ++ show (BL.length body)
          ++ " echoed-id=" ++ BLC.unpack (encode (echoedId body))
          ++ " resp-bytes=" ++ show (BL.length out)
  respond (responseLBS status200 (modeHeaders mode) out)

usage :: IO a
usage = do
  hPutStrLn stderr "usage: stub-server PORT [MODE]"
  hPutStrLn stderr "  PORT is required; there is no default."
  hPutStrLn stderr "  MODE is the response Content-Type mode; it defaults to `json`."
  hPutStrLn stderr "  valid MODEs: json, text, none"
  hPutStrLn stderr "    json  -> Content-Type: application/json"
  hPutStrLn stderr "    text  -> Content-Type: text/plain"
  hPutStrLn stderr "    none  -> no Content-Type header at all"
  exitFailure

-- Bound to 127.0.0.1 and nothing else: alloy's guess_local_url treats only
-- localhost / 127.0.0.1 / ::1 as local, and only those get no_proxy.
run :: Int -> CtMode -> IO ()
run port mode = do
  putStrLn $ "[stub] listening on 127.0.0.1:" ++ show port ++ " ct-mode=" ++ modeName mode
  runSettings (setHost "127.0.0.1" (setPort port defaultSettings)) (app mode)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  args <- getArgs
  case args of
    [p] | Just port <- readMaybe p -> run port CtJson
    [p, m] | Just port <- readMaybe p ->
      case parseMode m of
        Just mode -> run port mode
        Nothing   -> do
          hPutStrLn stderr ("ERROR: unrecognised Content-Type mode: " ++ show m)
          hPutStrLn stderr "       There is NO fallback -- a typo must not silently run the `json` row."
          usage
    _ -> usage
