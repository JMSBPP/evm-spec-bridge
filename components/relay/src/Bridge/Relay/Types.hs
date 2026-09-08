module Bridge.Relay.Types
  ( defaultTimeoutSec
  , defaultQueueBound
  , ControlReq (..)
  , ControlResp (..)
  ) where

import Data.Aeson (Value)
import Data.Text (Text)

defaultTimeoutSec :: Int
defaultTimeoutSec = 45

defaultQueueBound :: Int
defaultQueueBound = 64

data ControlReq
  = SendReq Text Value
  | PollReq
  | ReplyReq Value Value
  deriving (Eq, Show)

data ControlResp
  = SendOk Value
  | PollEmpty
  | PollOk Value Text Value
  | ReplyOk
  | ControlErr Text
  deriving (Eq, Show)
