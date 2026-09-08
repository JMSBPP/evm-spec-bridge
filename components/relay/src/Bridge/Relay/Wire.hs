{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | NDJSON JSON-RPC request/response wire codec.
--
-- Params and result payloads are treated as opaque 'Value's: this module
-- only handles the JSON-RPC envelope (id, method, params / result / error)
-- and the newline-delimited framing used on the wire.
module Bridge.Relay.Wire
  ( RpcRequest (..)
  , RpcResponse (..)
  , encodeRequest
  , decodeRequest
  , encodeResponse
  , decodeResponse
  ) where

import Data.Aeson (Value (..), eitherDecode, encode, object, withObject, (.:), (.:?), (.=))
import Data.Aeson.Types (Parser, parseEither)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)

data RpcRequest = RpcRequest
  { rpcId :: Value
  , rpcMethod :: Text
  , rpcParams :: Value
  }
  deriving (Eq, Show)

data RpcResponse
  = RpcResult {respId :: Value, respResult :: Value}
  | RpcError {respId :: Value, respError :: Value}
  deriving (Eq, Show)

encodeRequest :: RpcRequest -> BS.ByteString
encodeRequest req =
  BL.toStrict (encode (requestToJSON req)) `BS.append` BSC.singleton '\n'

decodeRequest :: BS.ByteString -> Either String RpcRequest
decodeRequest bs =
  case eitherDecode (BL.fromStrict (stripTrailingNewline bs)) of
    Left err -> Left err
    Right v -> parseEither requestFromJSON v

encodeResponse :: RpcResponse -> BS.ByteString
encodeResponse resp =
  BL.toStrict (encode (responseToJSON resp)) `BS.append` BSC.singleton '\n'

decodeResponse :: BS.ByteString -> Either String RpcResponse
decodeResponse bs =
  case eitherDecode (BL.fromStrict (stripTrailingNewline bs)) of
    Left err -> Left err
    Right v -> parseEither responseFromJSON v

stripTrailingNewline :: BS.ByteString -> BS.ByteString
stripTrailingNewline bs =
  case BS.unsnoc bs of
    Just (rest, 10) -> rest
    _ -> bs

requestToJSON :: RpcRequest -> Value
requestToJSON (RpcRequest rid method params) =
  object
    [ "jsonrpc" .= String "2.0"
    , "id" .= rid
    , "method" .= String method
    , "params" .= params
    ]

requestFromJSON :: Value -> Parser RpcRequest
requestFromJSON =
  withObject "RpcRequest" $ \o ->
    RpcRequest <$> o .: "id" <*> o .: "method" <*> o .: "params"

responseToJSON :: RpcResponse -> Value
responseToJSON = \case
  RpcResult rid result ->
    object
      [ "jsonrpc" .= String "2.0"
      , "id" .= rid
      , "result" .= result
      ]
  RpcError rid err ->
    object
      [ "jsonrpc" .= String "2.0"
      , "id" .= rid
      , "error" .= err
      ]

responseFromJSON :: Value -> Parser RpcResponse
responseFromJSON =
  withObject "RpcResponse" $ \o -> do
    mresult <- o .:? "result"
    case mresult of
      Just result -> RpcResult <$> o .: "id" <*> pure result
      Nothing -> RpcError <$> o .: "id" <*> o .: "error"
