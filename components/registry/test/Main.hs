-- | Registry dispatch tests — assertions on encoded JSON bytes.
{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Bridge.AbiCodec.Envelope (decodeEnvelope, tagSuccess)
import Bridge.AbiCodec.Hex (Hex0x, hexOfText)
import Bridge.Registry (LegacyMode (..), RpcRequest (..), dispatch, healthBody)
import Bridge.Protocol (SpecOutcome (..))

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as LBS
import Network.JSONRPC (Id (..), Response (..))
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "evm-spec-bridge-registry"
    [ testCase "spec_health lands in result" healthInResult
    , testCase "spec_health body is non-empty sentinel" healthBodySentinel
    , testCase "spec_health envelope tag is success" healthTagSuccess
    , testCase "fixture rejection has no error key" fixtureRejectionInResult
    , testCase "same request same bytes health" sameRequestHealth
    , testCase "namespace rejects eth_call" namespaceReject
    ]

healthReq :: RpcRequest
healthReq =
  RpcRequest
    { rpcMethod = "spec_health"
    , reqId = IdInt 0
    , rpcParams = Aeson.Array mempty
    }

encodeResp :: Response -> BS.ByteString
encodeResp r = LBS.toStrict (Aeson.encode r)

healthInResult :: IO ()
healthInResult = do
  let bs = encodeResp (dispatch Success healthReq)
  BS8.pack "result" `BS.isInfixOf` bs @?= True
  BS8.pack "error" `BS.isInfixOf` bs @?= False

healthBodySentinel :: IO ()
healthBodySentinel = do
  BS.length healthBody @?= 32
  BS.all (== 0xcd) healthBody @?= True

healthTagSuccess :: IO ()
healthTagSuccess = do
  let bs = encodeResp (dispatch Success healthReq)
  hex <- extractResultHex bs
  outcome <-
    case decodeEnvelope hex of
      Left e -> assertFailure (show e)
      Right o -> pure o
  case outcome of
    SpecSuccess body -> body @?= healthBody
    _ -> assertFailure "expected SpecSuccess"
  tagSuccess @?= 0x01

fixtureRejectionInResult :: IO ()
fixtureRejectionInResult = do
  let req =
        RpcRequest
          { rpcMethod = "spec_fixtureRejection"
          , reqId = IdInt 0
          , rpcParams = Aeson.Array mempty
          }
      bs = encodeResp (dispatch Success req)
  BS8.pack "result" `BS.isInfixOf` bs @?= True
  BS8.pack "error" `BS.isInfixOf` bs @?= False

sameRequestHealth :: IO ()
sameRequestHealth = do
  let r1 = dispatch Success healthReq
      r2 = dispatch Success healthReq
  encodeResp r1 @?= encodeResp r2

namespaceReject :: IO ()
namespaceReject = do
  let req =
        RpcRequest
          { rpcMethod = "eth_getBalance"
          , reqId = IdInt 1
          , rpcParams = Aeson.Array mempty
          }
      bs = encodeResp (dispatch Success req)
  BS8.pack "-32601" `BS.isInfixOf` bs @?= True

extractResultHex :: BS.ByteString -> IO Hex0x
extractResultHex bs =
  case Aeson.eitherDecodeStrict bs of
    Left e -> assertFailure e
    Right v ->
      case v of
        Aeson.Object o ->
          case KM.lookup (Key.fromText "result") o of
            Just (Aeson.String t) ->
              case hexOfText t of
                Right h -> pure h
                Left err -> assertFailure (show err)
            Just other -> assertFailure ("result not a string: " ++ show other)
            Nothing -> assertFailure "missing result"
        _ -> assertFailure "expected JSON object"
