{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Bridge.JsonRpc (ProtocolFault (..), protocolFault)
import Bridge.Registry (LegacyMode (..), RpcRequest (..), dispatch)
import Bridge.Transport (parseRequest)

import qualified Data.Aeson as Aeson
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
    "evm-spec-bridge-transport"
    [ testCase "rejects batch array" rejectsBatch
    , testCase "rejects unknown field" rejectsUnknownField
    , testCase "rejects null id" rejectsNullId
    , testCase "rejects missing id" rejectsMissingId
    , testCase "id echoed on unknown method error" idEchoUnknownMethod
    , testCase "same request same bytes for health" sameRequestHealth
    , testCase "strict unknown field faults" strictUnknownField
    , testCase "strict invalid json faults" strictInvalidJson
    , testCase "strict unknown field encodes -32602" strictUnknownFieldCode
    ]

encodeResp :: Response -> BS.ByteString
encodeResp r = LBS.toStrict (Aeson.encode r)

rejectsBatch :: IO ()
rejectsBatch = do
  case parseRequest (LBS.fromStrict (BS8.pack "[{\"jsonrpc\":\"2.0\"}]")) of
    Left (_, _) -> pure ()
    Right _ -> assertFailure "expected batch fault"

rejectsUnknownField :: IO ()
rejectsUnknownField = do
  let body =
        LBS.fromStrict
          ( BS8.pack
              "{\"jsonrpc\":\"2.0\",\"method\":\"spec_health\",\"params\":[],\"id\":0,\"foo\":1}"
          )
  case parseRequest body of
    Left (_, _) -> pure ()
    Right _ -> assertFailure "expected unknown field fault"

rejectsNullId :: IO ()
rejectsNullId = do
  let body =
        LBS.fromStrict
          ( BS8.pack "{\"jsonrpc\":\"2.0\",\"method\":\"spec_health\",\"params\":[],\"id\":null}"
          )
  case parseRequest body of
    Left (_, _) -> pure ()
    Right _ -> assertFailure "expected null id fault"

rejectsMissingId :: IO ()
rejectsMissingId = do
  let body =
        LBS.fromStrict
          (BS8.pack "{\"jsonrpc\":\"2.0\",\"method\":\"spec_health\",\"params\":[]}")
  case parseRequest body of
    Left (_, _) -> pure ()
    Right _ -> assertFailure "expected missing id fault"

idEchoUnknownMethod :: IO ()
idEchoUnknownMethod = do
  rpc <-
    case parseRequest
      ( LBS.fromStrict
          (BS8.pack "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[],\"id\":\"trace-1\"}")
      ) of
      Right r -> pure r
      Left _ -> assertFailure "expected parse success"
  let bs = encodeResp (dispatch Success rpc)
  BS8.pack "trace-1" `BS.isInfixOf` bs @?= True
  BS8.pack "-32601" `BS.isInfixOf` bs @?= True

sameRequestHealth :: IO ()
sameRequestHealth = do
  let req =
        RpcRequest
          { rpcMethod = "spec_health"
          , reqId = IdInt 7
          , rpcParams = Aeson.Array mempty
          }
      r1 = dispatch Success req
      r2 = dispatch Success req
  encodeResp r1 @?= encodeResp r2

strictUnknownField :: IO ()
strictUnknownField = do
  case parseRequest
    ( LBS.fromStrict
        (BS8.pack "{\"jsonrpc\":\"2.0\",\"method\":\"spec_health\",\"params\":[],\"id\":0,\"x\":1}")
    ) of
    Left (_, BadParams _) -> pure ()
    _ -> assertFailure "expected BadParams for unknown field"

strictInvalidJson :: IO ()
strictInvalidJson = do
  case parseRequest (LBS.fromStrict (BS8.pack "{")) of
    Left (_, ParseFailure) -> pure ()
    _ -> assertFailure "expected ParseFailure"

strictUnknownFieldCode :: IO ()
strictUnknownFieldCode = do
  let body =
        LBS.fromStrict
          (BS8.pack "{\"jsonrpc\":\"2.0\",\"method\":\"spec_health\",\"params\":[],\"id\":42,\"x\":1}")
  case parseRequest body of
    Left (faultId, fault) -> do
      faultId @?= IdInt 42
      let bs = encodeResp (protocolFault faultId fault)
      BS8.pack "-32602" `BS.isInfixOf` bs @?= True
      BS8.pack "\"id\":42" `BS.isInfixOf` bs @?= True
    Right _ -> assertFailure "expected fault"
