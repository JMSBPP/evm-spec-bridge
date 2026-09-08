{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
module Bridge.Relay.Control
  ( encodeControlReq
  , decodeControlReq
  , encodeControlResp
  , decodeControlResp
  ) where

import Bridge.Relay.Types (ControlReq (..), ControlResp (..))
import Data.Aeson (Value (..), eitherDecode, encode, object, withObject, (.:), (.:?), (.=))
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

controlRespToJSON :: ControlResp -> Value
controlRespToJSON = \case
  SendOk result ->
    object
      [ "ok" .= Bool True
      , "result" .= result
      ]
  PollEmpty ->
    object
      [ "ok" .= Bool True
      , "empty" .= Bool True
      ]
  PollOk rid method params ->
    object
      [ "ok" .= Bool True
      , "id" .= rid
      , "method" .= String method
      , "params" .= params
      ]
  ReplyOk ->
    object ["ok" .= Bool True]
  ControlErr err ->
    object
      [ "ok" .= Bool False
      , "error" .= String err
      ]

controlRespFromJSON :: Value -> Parser ControlResp
controlRespFromJSON =
  withObject "ControlResp" $ \o -> do
    ok <- o .: "ok"
    if ok
      then do
        memptyFlag <- o .:? "empty"
        case memptyFlag of
          Just True -> pure PollEmpty
          _ -> do
            mid <- o .:? "id"
            mmethod <- o .:? "method"
            mparams <- o .:? "params"
            case (mid, mmethod, mparams) of
              (Just rid, Just method, Just params) -> pure (PollOk rid method params)
              _ -> do
                mresult <- o .:? "result"
                case mresult of
                  Just result -> pure (SendOk result)
                  Nothing -> pure ReplyOk
      else ControlErr <$> o .: "error"
