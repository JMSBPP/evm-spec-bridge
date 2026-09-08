{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Bridge.Relay.Control
import Bridge.Relay.Queue
import Bridge.Relay.Types
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
      ]
