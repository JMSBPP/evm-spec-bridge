{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
module Bridge.Relay.Control
  ( encodeControlReq
  , decodeControlReq
  , encodeControlResp
  , decodeControlResp
  ) where

import Bridge.Relay.Types (ControlReq (..), ControlResp (..))
import Data.Aeson (Value (..), eitherDecode, encode, object, withObject, (.:), (.=))
import Data.Aeson.Types (Parser, parseEither)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import Prelude hiding (id)

encodeControlReq :: ControlReq -> BS.ByteString
encodeControlReq req =
  BL.toStrict (encode (controlReqToJSON req)) `BS.append` BSC.singleton '\n'

decodeControlReq :: BS.ByteString -> Either String ControlReq
decodeControlReq bs =
  case eitherDecode (BL.fromStrict (stripTrailingNewline bs)) of
    Left err -> Left err
    Right v -> parseEither controlReqFromJSON v

encodeControlResp :: ControlResp -> BS.ByteString
encodeControlResp resp =
  BL.toStrict (encode (controlRespToJSON resp)) `BS.append` BSC.singleton '\n'

decodeControlResp :: BS.ByteString -> Either String ControlResp
decodeControlResp bs =
  case eitherDecode (BL.fromStrict (stripTrailingNewline bs)) of
    Left err -> Left err
    Right v -> parseEither controlRespFromJSON v

stripTrailingNewline :: BS.ByteString -> BS.ByteString
stripTrailingNewline bs =
  case BS.unsnoc bs of
    Just (rest, 10) -> rest
    _ -> bs

controlReqToJSON :: ControlReq -> Value
controlReqToJSON = \case
  SendReq method params ->
    object
      [ "op" .= String "send"
      , "method" .= String method
      , "params" .= params
      ]
  PollReq ->
    object ["op" .= String "poll"]
  ReplyReq rid result ->
    object
      [ "op" .= String "reply"
      , "id" .= rid
      , "result" .= result
      ]

controlReqFromJSON :: Value -> Parser ControlReq
controlReqFromJSON =
  withObject "ControlReq" $ \o -> do
    op <- o .: "op"
    case op of
      "send" -> SendReq <$> o .: "method" <*> o .: "params"
      "poll" -> pure PollReq
      "reply" -> ReplyReq <$> o .: "id" <*> o .: "result"
      other -> fail ("unknown op: " ++ show (other :: Text))

-- | Every control response carries an explicit @"kind"@ discriminator
-- (distinct from the human-readable @"ok"@ flag, kept for convenience) so
-- the decoder never has to infer the constructor from *which* optional
-- keys happen to be present. That inference (the previous encoding) is
-- ambiguous whenever a field that's legitimately present in one variant
-- is null or otherwise absent-looking, e.g. @PollOk@ with @params: null@
-- or @id: null@ was indistinguishable from @ReplyOk@ / @SendOk@ by key
-- probing alone. With a tag, decoding is total and unambiguous regardless
-- of which fields are null.
controlRespToJSON :: ControlResp -> Value
controlRespToJSON = \case
  SendOk result ->
    object
      [ "ok" .= Bool True
      , "kind" .= String "send"
      , "result" .= result
      ]
  PollEmpty ->
    object
      [ "ok" .= Bool True
      , "kind" .= String "pollEmpty"
      ]
  PollOk rid method params ->
    object
      [ "ok" .= Bool True
      , "kind" .= String "poll"
      , "id" .= rid
      , "method" .= String method
      , "params" .= params
      ]
  ReplyOk ->
    object
      [ "ok" .= Bool True
      , "kind" .= String "reply"
      ]
  ControlErr err ->
    object
      [ "ok" .= Bool False
      , "kind" .= String "error"
      , "error" .= String err
      ]

controlRespFromJSON :: Value -> Parser ControlResp
controlRespFromJSON =
  withObject "ControlResp" $ \o -> do
    kind <- o .: "kind"
    case (kind :: Text) of
      "send" -> SendOk <$> o .: "result"
      "pollEmpty" -> pure PollEmpty
      "poll" -> PollOk <$> o .: "id" <*> o .: "method" <*> o .: "params"
      "reply" -> pure ReplyOk
      "error" -> ControlErr <$> o .: "error"
      other -> fail ("unknown control response kind: " ++ show other)
