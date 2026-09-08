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
  , respId
  , encodeRequest
  , decodeRequest
  , encodeResponse
  , decodeResponse
  ) where

import Data.Aeson (Value (..), eitherDecode, encode, object, withObject, (.:), (.:!), (.:?), (.=), (.!=))
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

-- | A decoded JSON-RPC response line: either a success carrying a
-- (possibly 'Null') result, or a failure carrying an error payload.
--
-- Deliberately positional (no per-constructor field labels): 'respResult'
-- and 'respError' would each only be defined for one of the two
-- constructors, which trips @-Wpartial-fields@ under @--pedantic@. 'respId'
-- below is total over both constructors and is provided as a plain
-- function instead.
data RpcResponse
  = RpcResult Value Value -- ^ id, result
  | RpcError Value Value -- ^ id, error
  deriving (Eq, Show)

-- | The @id@ carried by either constructor of 'RpcResponse'.
respId :: RpcResponse -> Value
respId (RpcResult rid _) = rid
respId (RpcError rid _) = rid

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

-- | @params@ is optional in JSON-RPC 2.0 (a no-arg request may omit it
-- entirely); a missing key defaults to 'Null' rather than failing the
-- decode. An explicit @null@ also decodes to 'Null', so both spellings of
-- "no params" are accepted uniformly.
requestFromJSON :: Value -> Parser RpcRequest
requestFromJSON =
  withObject "RpcRequest" $ \o ->
    RpcRequest <$> o .: "id" <*> o .: "method" <*> (o .:? "params" .!= Null)

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

-- | Discriminate success vs. failure by the *presence* of the @result@
-- key, not its value: aeson's @.:?@ treats an explicit @"result": null@
-- the same as an absent key, which would misclassify a legal JSON-RPC
-- success carrying a null result (e.g. @eth_getBlockByNumber@ on a
-- missing block) as a decode failure. @.:!@ parses an explicit null as
-- @Just Null@, only returning @Nothing@ when the key is truly absent.
responseFromJSON :: Value -> Parser RpcResponse
responseFromJSON =
  withObject "RpcResponse" $ \o -> do
    mresult <- o .:! "result"
    case mresult of
      Just result -> RpcResult <$> o .: "id" <*> pure result
      Nothing -> RpcError <$> o .: "id" <*> o .: "error"
