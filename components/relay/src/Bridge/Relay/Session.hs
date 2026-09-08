{-# LANGUAGE OverloadedStrings #-}

-- | Pure Foundry<->HEVM relay session state machine.
--
-- All IO (socket reads/writes, TMVar waiters for outbound replies) lives in
-- the relayd daemon; this module only tracks the FIFO of inbound requests
-- awaiting a Foundry-side poll, the set of outstanding reply ids, and the
-- monotonic id allocator used for outbound (Foundry -> HEVM) sends.
module Bridge.Relay.Session
  ( Session (..)
  , PendingInbound (..)
  , SessionEvent (..)
  , SessionEffect (..)
  , newSession
  , markAlive
  , canonicalId
  , step
  ) where

import Bridge.Relay.Queue (Overflow (..), Queue, emptyQueue, pop, push)
import Bridge.Relay.Wire (RpcRequest (..), RpcResponse (..))
import Data.Aeson (Value (..), encode)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TLE

-- | An inbound (HEVM -> Foundry) request waiting to be delivered via poll.
data PendingInbound = PendingInbound
  { pinId :: Value
  , pinMethod :: Text
  , pinParams :: Value
  }
  deriving (Eq, Show)

data Session = Session
  { sessInbound :: Queue PendingInbound
  , sessOutstanding :: Set Text
  -- ^ canonical id text of requests handed out by 'EvPoll', awaiting 'EvReply'.
  , sessNextId :: Integer
  -- ^ monotonic allocator for outbound (Foundry -> HEVM) request ids.
  , sessAlive :: Bool
  }
  deriving (Eq, Show)

data SessionEvent
  = EvSendAlloc
  | EvOutboundResult Value Value -- ^ id, result (IO layer matches waiters; pure session no-ops)
  | EvOutboundError Value Value -- ^ id, error (IO layer matches waiters; pure session no-ops)
  | EvInbound RpcRequest
  | EvPoll
  | EvReply Value Value -- ^ id, result
  | EvDisconnect
  deriving (Eq, Show)

data SessionEffect
  = EffNop
  | EffAllocatedId Value
  | EffWriteRequest RpcRequest
  | EffWriteResponse RpcResponse
  | EffPollResult (Maybe PendingInbound)
  | EffRejectInbound Value Text -- ^ id, error message (queue overflow)
  | EffFail Text -- ^ e.g. unknown id, no session
  deriving (Eq, Show)

-- | Construct a fresh session with the given inbound-queue bound.
--
-- Starts with 'sessAlive' = 'True' so pure unit tests can drive 'step'
-- directly without a preceding connect event; the relayd daemon calls
-- 'markAlive' / marks the session dead itself around the actual HEVM
-- connection lifecycle.
newSession :: Int -> Session
newSession bound =
  Session
    { sessInbound = emptyQueue bound
    , sessOutstanding = Set.empty
    , sessNextId = 0
    , sessAlive = True
    }

markAlive :: Session -> Session
markAlive sess = sess {sessAlive = True}

-- | Canonical id text used as the 'Set' key: compact (no-whitespace) aeson
-- encoding of the id 'Value', so that e.g. @Number 1@ and any equivalent
-- representation map to the same key.
canonicalId :: Value -> Text
canonicalId = TL.toStrict . TLE.decodeUtf8 . encode

step :: SessionEvent -> Session -> (Session, SessionEffect)
step ev sess = case ev of
  EvSendAlloc
    | not (sessAlive sess) -> (sess, EffFail "hevm not connected")
    | otherwise ->
        let n = sessNextId sess
            sess' = sess {sessNextId = n + 1}
         in (sess', EffAllocatedId (Number (fromInteger n)))
  EvOutboundResult _ _ -> (sess, EffNop)
  EvOutboundError _ _ -> (sess, EffNop)
  EvInbound (RpcRequest rid method params) ->
    case push (PendingInbound rid method params) (sessInbound sess) of
      Left Overflow -> (sess, EffRejectInbound rid "queue overflow")
      Right q' -> (sess {sessInbound = q'}, EffNop)
  EvPoll ->
    case pop (sessInbound sess) of
      (Nothing, q') -> (sess {sessInbound = q'}, EffPollResult Nothing)
      (Just pin, q') ->
        let idText = canonicalId (pinId pin)
            sess' =
              sess
                { sessInbound = q'
                , sessOutstanding = Set.insert idText (sessOutstanding sess)
                }
         in (sess', EffPollResult (Just pin))
  EvReply rid result ->
    let idText = canonicalId rid
     in if Set.member idText (sessOutstanding sess)
          then
            let sess' = sess {sessOutstanding = Set.delete idText (sessOutstanding sess)}
             in (sess', EffWriteResponse (RpcResult rid result))
          else (sess, EffFail "unknown id")
  EvDisconnect ->
    let sess' =
          sess
            { sessInbound = drainQueue (sessInbound sess)
            , sessOutstanding = Set.empty
            , sessAlive = False
            }
     in (sess', EffNop)

-- | Pop every element off a queue, discarding them, leaving it empty while
-- preserving its bound (the 'Queue' module does not expose a constructor
-- that resets contents in place).
drainQueue :: Queue a -> Queue a
drainQueue q = case pop q of
  (Nothing, q') -> q'
  (Just _, q') -> drainQueue q'
