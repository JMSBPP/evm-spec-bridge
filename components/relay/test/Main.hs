{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Bridge.Relay.Control
import Bridge.Relay.Queue
import Bridge.Relay.Session
import Bridge.Relay.Types
import Bridge.Relay.Wire
import Data.Aeson (Value (..))
import qualified Data.Vector as V
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit ((@?=), testCase)

main :: IO ()
main =
  defaultMain $
    testGroup
      "relay"
      [ testGroup
          "queue"
          [ testCase "fifo order" $ do
              let Right q1 = push (1 :: Int) (emptyQueue 4)
                  Right q2 = push 2 q1
                  (a, q3) = pop q2
                  (b, _) = pop q3
              a @?= Just 1
              b @?= Just 2
          , testCase "empty pop" $ do
              let (a, q') = pop (emptyQueue 4 :: Queue Int)
              a @?= Nothing
              let (b, _) = pop q'
              b @?= Nothing
          , testCase "overflow at bound" $ do
              let Right q1 = push (1 :: Int) (emptyQueue 1)
              push 2 q1 @?= Left Overflow
          ]
      , testGroup
          "control"
          [ testCase "roundtrip send req" $ do
              let req = SendReq "foo" (Array (V.fromList [Number 1]))
                  bs = encodeControlReq req
              decodeControlReq bs @?= Right req
          , testCase "poll empty resp" $ do
              decodeControlResp "{\"ok\":true,\"empty\":true}\n" @?= Right PollEmpty
          , testCase "error resp" $ do
              decodeControlResp "{\"ok\":false,\"error\":\"timeout\"}\n" @?= Right (ControlErr "timeout")
          ]
      , testGroup
          "wire"
          [ testCase "request/response line roundtrip" $ do
              let req = RpcRequest (Number 1) "eth_call" (Array (V.fromList [Number 1]))
              decodeRequest (encodeRequest req) @?= Right req
              let resp = RpcResult (Number 1) (String "0xdead")
              decodeResponse (encodeResponse resp) @?= Right resp
          ]
      , testGroup
          "session"
          [ testCase "inbound then poll returns same" $ do
              let sess0 = newSession 4
                  req = RpcRequest (Number 1) "eth_call" (Array (V.fromList []))
                  (sess1, effIn) = step (EvInbound req) sess0
                  (_, effPoll) = step EvPoll sess1
              effIn @?= EffNop
              effPoll @?= EffPollResult (Just (PendingInbound (Number 1) "eth_call" (Array (V.fromList []))))
          , testCase "overflow rejects inbound" $ do
              let sess0 = newSession 1
                  req1 = RpcRequest (Number 1) "eth_call" (Array (V.fromList []))
                  req2 = RpcRequest (Number 2) "eth_call" (Array (V.fromList []))
                  (sess1, eff1) = step (EvInbound req1) sess0
                  (_, eff2) = step (EvInbound req2) sess1
              eff1 @?= EffNop
              eff2 @?= EffRejectInbound (Number 2) "queue overflow"
          , testCase "reply unknown id fails" $ do
              let sess0 = newSession 4
                  (_, eff) = step (EvReply (Number 99) (String "ok")) sess0
              eff @?= EffFail "unknown id"
          , testCase "reply known id succeeds after poll" $ do
              let sess0 = newSession 4
                  req = RpcRequest (Number 1) "eth_call" (Array (V.fromList []))
                  (sess1, _) = step (EvInbound req) sess0
                  (sess2, _) = step EvPoll sess1
                  (_, eff) = step (EvReply (Number 1) (String "0xdead")) sess2
              eff @?= EffWriteResponse (RpcResult (Number 1) (String "0xdead"))
          , testCase "disconnect clears queue" $ do
              let sess0 = newSession 4
                  req = RpcRequest (Number 1) "eth_call" (Array (V.fromList []))
                  (sess1, _) = step (EvInbound req) sess0
                  (sess2, _) = step EvDisconnect sess1
                  (_, effPoll) = step EvPoll sess2
              effPoll @?= EffPollResult Nothing
          ]
      ]
