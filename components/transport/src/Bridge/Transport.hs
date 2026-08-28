-- | Loopback HTTP server carrying the oracle.
--
-- Reads JSON-RPC POST bodies, delegates to 'Bridge.Registry.dispatch', returns
-- encoded responses. Wedge mode preserves Phase 3 never-answer behaviour.
{-# LANGUAGE OverloadedStrings #-}
module Bridge.Transport
  ( parseRequest
  , serve
  , componentName
  ) where

import Bridge.JsonRpc (ProtocolFault (..), protocolFault)
import Bridge.Registry (LegacyMode (..), RpcRequest (..), dispatch)

import qualified Control.Concurrent as Concurrent
import Control.Monad (forever)
import Data.Aeson (Value (..))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as LBS
import Data.Scientific (toRealFloat)
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Types (hContentType, status200)
import Network.HTTP.Types.Header (hContentLength)
import Network.JSONRPC (Id (..))
import qualified Network.JSONRPC as RPC
import Network.Wai (Application, Response, responseLBS, strictRequestBody)
import Network.Wai.Handler.Warp (run)
import System.IO (hPutStrLn, stderr)

-- | Strict JSON-RPC request decode. Unknown fields and bad shapes are faults.
parseRequest :: LBS.ByteString -> Either (Id, ProtocolFault) RpcRequest
parseRequest body =
  case Aeson.eitherDecode body of
    Left _ -> Left (IdInt 0, ParseFailure)
    Right v -> parseValue v

parseValue :: Value -> Either (Id, ProtocolFault) RpcRequest
parseValue (Array _) = Left (IdInt 0, BadParams "batch not supported")
parseValue (Object o) =
  let faultId = lookupFaultId o
   in do
        let keys = KM.keys o
            allowed =
              Set.fromList
                [ Key.fromText "jsonrpc"
                , Key.fromText "method"
                , Key.fromText "params"
                , Key.fromText "id"
                ]
        case findUnknown keys allowed of
          Just k -> Left (faultId, BadParams ("unknown field: " <> Key.toText k))
          Nothing -> parseObject faultId o
parseValue _ = Left (IdInt 0, BadParams "expected JSON object")

parseObject :: Id -> KM.KeyMap Value -> Either (Id, ProtocolFault) RpcRequest
parseObject faultId o = do
  jsonrpc <- requireText faultId o "jsonrpc"
  if jsonrpc /= "2.0"
    then Left (faultId, BadParams "jsonrpc must be 2.0")
    else pure ()
  method <- requireText faultId o "method"
  params <-
    case KM.lookup (Key.fromText "params") o of
      Nothing -> pure (Array mempty)
      Just p -> pure p
  idVal <- requirePresent faultId o "id"
  parsedId <- parseIdValue faultId idVal
  pure RpcRequest {rpcMethod = method, reqId = parsedId, rpcParams = params}

lookupFaultId :: KM.KeyMap Value -> Id
lookupFaultId o =
  case KM.lookup (Key.fromText "id") o of
    Nothing -> IdInt 0
    Just v ->
      case parseIdValue (IdInt 0) v of
        Right id' -> id'
        Left (id', _) -> id'

findUnknown :: [Key.Key] -> Set.Set Key.Key -> Maybe Key.Key
findUnknown ks allowed =
  case filter (`Set.notMember` allowed) ks of
    [] -> Nothing
    (k : _) -> Just k

requireText :: Id -> KM.KeyMap Value -> T.Text -> Either (Id, ProtocolFault) T.Text
requireText faultId o k =
  case KM.lookup (Key.fromText k) o of
    Nothing -> Left (faultId, BadParams ("missing field: " <> k))
    Just (String t) -> Right t
    Just _ -> Left (faultId, BadParams ("field not a string: " <> k))

requirePresent :: Id -> KM.KeyMap Value -> T.Text -> Either (Id, ProtocolFault) Value
requirePresent faultId o k =
  case KM.lookup (Key.fromText k) o of
    Nothing -> Left (faultId, BadParams ("missing field: " <> k))
    Just Null -> Left (faultId, BadParams "notifications not supported")
    Just v -> Right v

parseIdValue :: Id -> Value -> Either (Id, ProtocolFault) Id
parseIdValue _ (Number n) = Right (IdInt (truncate (toRealFloat n :: Double)))
parseIdValue _ (String t) = Right (IdTxt t)
parseIdValue faultId Null = Left (faultId, BadParams "notifications not supported")
parseIdValue faultId _ = Left (faultId, BadParams "invalid id")

-- | Start the loopback server on @port@ with the given legacy dev @mode@.
serve :: LegacyMode -> Int -> IO ()
serve mode port = run port (application mode)

application :: LegacyMode -> Application
application mode request respond =
  case mode of
    Wedge -> wedgeHandler request respond
    _ -> normalHandler mode request respond

normalHandler :: LegacyMode -> Application
normalHandler mode request respond = do
  body <- strictRequestBody request
  let resp =
        case parseRequest body of
          Left (faultId, fault) -> protocolFault faultId fault
          Right rpc -> dispatch mode rpc
  respond (jsonResp resp)

wedgeHandler :: Application
wedgeHandler request respond = do
  body <- strictRequestBody request
  case parseRequest body of
    Left (faultId, fault) -> respond (jsonResp (protocolFault faultId fault))
    Right rpc -> do
      hPutStrLn stderr ("wedge: reached handler method=" ++ T.unpack (rpcMethod rpc))
      forever (Concurrent.threadDelay maxBound)

jsonResp :: RPC.Response -> Response
jsonResp resp =
  let bs = Aeson.encode resp
   in responseLBS
        status200
        [ (hContentType, "application/json")
        , (hContentLength, TE.encodeUtf8 (T.pack (show (LBS.length bs))))
        ]
        bs

componentName :: String
componentName = "evm-spec-bridge-transport"
