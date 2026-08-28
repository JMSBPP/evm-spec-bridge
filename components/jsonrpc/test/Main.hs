-- | JSON-RPC channel discipline tests — assertions on encoded bytes.
{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Bridge.JsonRpc (ProtocolFault (..), outcomeResponse, protocolFault)
import Bridge.Protocol (GuardId (..), SpecOutcome (..))

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as T
import Network.JSONRPC (Id (..), Response)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "evm-spec-bridge-jsonrpc"
    [ testCase "rejection lands in result" rejectionInResult
    , testCase "rejection carries no guard text" rejectionNoGuardText
    , testCase "result is a JSON string" resultIsString
    , testCase "result is 0x-prefixed and even-nibble" resultHexShape
    , testCase "protocol faults use the reserved codes" protocolFaultCodes
    , testCase "id is echoed" idEchoed
    ]

encodeResp :: Response -> BS.ByteString
encodeResp r = LBS.toStrict (Aeson.encode r)

mustOutcome :: Id -> SpecOutcome BS.ByteString -> Response
mustOutcome reqId o =
  case outcomeResponse reqId o of
    Left err -> error (show err)
    Right r -> r

rejectionInResult :: IO ()
rejectionInResult = do
  let bs = encodeResp (mustOutcome (IdInt 0) (SpecRejection GuardStrikeOutOfRange))
  assertContains bs "result"
  assertNotContains bs "error"

rejectionNoGuardText :: IO ()
rejectionNoGuardText =
  mapM_
    ( \g -> do
        let bs = encodeResp (mustOutcome (IdInt 0) (SpecRejection g))
        assertNotContainsCI bs (show g)
    )
    [minBound .. maxBound]

resultIsString :: IO ()
resultIsString = do
  let bs = encodeResp (mustOutcome (IdInt 0) (SpecRejection GuardStrikeOutOfRange))
  case Aeson.eitherDecodeStrict bs of
    Left e -> assertFailure e
    Right v ->
      case v of
        Aeson.Object o ->
          case KM.lookup (Key.fromText "result") o of
            Just (Aeson.String _) -> pure ()
            Just other -> assertFailure ("result not a string: " ++ show other)
            Nothing -> assertFailure "missing result"
        _ -> assertFailure "expected JSON object"

resultHexShape :: IO ()
resultHexShape = do
  let bs = encodeResp (mustOutcome (IdInt 0) (SpecSuccess BS.empty))
  case Aeson.eitherDecodeStrict bs of
    Left e -> assertFailure e
    Right v ->
      case v of
        Aeson.Object o ->
          case KM.lookup (Key.fromText "result") o of
            Just (Aeson.String t) -> do
              T.isPrefixOf "0x" t @?= True
              even (T.length t - 2) @?= True
            Just other -> assertFailure ("expected string result: " ++ show other)
            Nothing -> assertFailure "missing result"
        _ -> assertFailure "expected JSON object"

protocolFaultCodes :: IO ()
protocolFaultCodes = do
  let bs1 = encodeResp (protocolFault (IdInt 0) (UnknownMethod "nope"))
      bs2 = encodeResp (protocolFault (IdInt 0) (BadParams "bad"))
      bs3 = encodeResp (protocolFault (IdInt 0) ParseFailure)
  assertContains bs1 "-32601"
  assertContains bs2 "-32602"
  assertContains bs3 "-32700"
  mapM_ (assertContains bs1) ["error"]
  mapM_ (assertContains bs2) ["error"]
  mapM_ (assertContains bs3) ["error"]

idEchoed :: IO ()
idEchoed = do
  let bs = encodeResp (mustOutcome (IdInt 7) (SpecSuccess BS.empty))
  assertContains bs "\"id\":7"

assertContains :: BS.ByteString -> String -> IO ()
assertContains hay needle =
  BS8.pack needle `BS.isInfixOf` hay @?= True

assertNotContains :: BS.ByteString -> String -> IO ()
assertNotContains hay needle =
  BS8.pack needle `BS.isInfixOf` hay @?= False

assertNotContainsCI :: BS.ByteString -> String -> IO ()
assertNotContainsCI hay needle =
  not (BS8.pack (map toLower needle) `BS.isInfixOf` BS8.map toLower hay) @?= True
  where
    toLower c
      | c >= 'A' && c <= 'Z' = toEnum (fromEnum c + 32)
      | otherwise = c
