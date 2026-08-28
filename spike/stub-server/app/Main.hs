-- THROWAWAY. Deleted in plan 02-05. Nothing outside spike/ may depend on this.
-- The envelope is hand-written on purpose: json-rpc's Data layer arrives in Phase 3/4.
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import           Data.Aeson                 (Value (Number, Object), decode, encode)
import qualified Data.Aeson.KeyMap          as KM
import qualified Data.ByteString.Lazy       as BL
import qualified Data.ByteString.Lazy.Char8 as BLC
import           Network.HTTP.Types         (status200)
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

-- alloy correlates a response to its request by id, so echo it. Number 1 is the
-- fallback when the body is not an object or carries no "id".
echoedId :: BL.ByteString -> Value
echoedId body = case decode body of
  Just (Object o) -> maybe (Number 1) id (KM.lookup "id" o)
  _               -> Number 1

app :: Application
app req respond = do
  body <- strictRequestBody req
  let rid  = echoedId body
      out  = BL.concat
        ["{\"jsonrpc\":\"2.0\",\"id\":", encode rid, ",\"result\":\"0x", payload, "\"}"]
  putStrLn $ "[stub] path=" ++ show (rawPathInfo req)
          ++ " body-bytes=" ++ show (BL.length body)
          ++ " echoed-id=" ++ BLC.unpack (encode rid)
  respond (responseLBS status200 [("Content-Type", "application/json")] out)

-- Bound to 127.0.0.1 and nothing else: alloy's guess_local_url treats only
-- localhost / 127.0.0.1 / ::1 as local, and only those get no_proxy.
main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  args <- getArgs
  case args of
    [p] | Just port <- readMaybe p -> do
            putStrLn $ "[stub] listening on 127.0.0.1:" ++ show (port :: Int)
            runSettings (setHost "127.0.0.1" (setPort port defaultSettings)) app
    _ -> do
      hPutStrLn stderr "usage: stub-server PORT   (PORT is required; there is no default)"
      exitFailure
