-- | ABI envelope codec tests — hand-written tree (no tasty-discover).
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Bridge.AbiCodec.Envelope
  ( EnvelopeError (..)
  , decodeEnvelope
  , encodeEnvelope
  )
import Bridge.AbiCodec.Hex (hexBytes, hexOfBytes, hexText)
import Bridge.Protocol
  ( FaultCode (..)
  , GuardId (..)
  , SpecOutcome (..)
  , protocolVersion
  )

import qualified Data.ByteString as BS
import qualified Data.Solidity.Abi.Codec as Abi
import Data.Solidity.Prim.Bytes (Bytes)
import Data.Solidity.Prim.Int (UIntN)
import Data.Solidity.Prim.Tuple ()
import qualified Data.Text as T
import Test.QuickCheck
  ( Gen
  , Property
  , arbitrary
  , choose
  , elements
  , forAll
  , oneof
  , property
  , vectorOf
  , (===)
  , (.&&.)
  )
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.QuickCheck (testProperty)

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "evm-spec-bridge-abi-codec"
    [ testProperty "envelope round-trips" $
        forAll genSpecOutcome roundTrip
    , testProperty "emitted hex is even-nibble" $
        forAll genSpecOutcome evenNibble
    , testProperty "protocolVersion survives" $
        forAll genSpecOutcome versionSurvives
    , testCase "tag 0x00 is rejected" tagZeroRejected
    , testCase "golden vector" goldenVector
    ]

genSpecOutcome :: Gen (SpecOutcome BS.ByteString)
genSpecOutcome =
  oneof
    [ SpecSuccess <$> bodyGen
    , SpecRejection <$> elements [minBound .. maxBound]
    , SpecTransportFault . FaultCode <$> choose (1, 5)
    ]
  where
    bodyGen = do
      n <- choose (0, 64)
      bs <- vectorOf n arbitrary
      pure (BS.pack bs)

roundTrip :: SpecOutcome BS.ByteString -> Property
roundTrip o =
  case encodeEnvelope o of
    Left _ -> property False
    Right h -> decodeEnvelope h === Right o

evenNibble :: SpecOutcome BS.ByteString -> Property
evenNibble o =
  case encodeEnvelope o of
    Left _ -> property True
    Right h ->
      let t = hexText h
       in (T.isPrefixOf "0x" t .&&. even (T.length t - 2))

versionSurvives :: SpecOutcome BS.ByteString -> Property
versionSurvives o =
  case encodeEnvelope o of
    Left _ -> property True
    Right h ->
      case Abi.decode (hexBytes h) :: Either String (UIntN 16, UIntN 8, Bytes) of
        Left _ -> property False
        Right (ver, _, _) -> fromIntegral ver === protocolVersion

tagZeroRejected :: IO ()
tagZeroRejected = do
  let ver = Abi.encode (1 :: UIntN 16) :: BS.ByteString
      tagZero = Abi.encode (0 :: UIntN 8) :: BS.ByteString
      body = Abi.encode (3 :: UIntN 8) :: BS.ByteString
      offset = Abi.encode (96 :: UIntN 256) :: BS.ByteString
      len = Abi.encode (32 :: UIntN 256) :: BS.ByteString
      raw = ver <> tagZero <> offset <> len <> body
      h = hexOfBytes raw
  decodeEnvelope h @?= Left (UnknownTag 0)

-- Populated from encodeEnvelope (SpecRejection GuardStrikeOutOfRange) — 03-03-T4.
goldenHex :: T.Text
goldenHex =
  "0x0000000000000000000000000000000000000000000000000000000000000001\
  \0000000000000000000000000000000000000000000000000000000000000002\
  \0000000000000000000000000000000000000000000000000000000000000060\
  \0000000000000000000000000000000000000000000000000000000000000020\
  \0000000000000000000000000000000000000000000000000000000000000003"

goldenVector :: IO ()
goldenVector = do
  let v = SpecRejection GuardStrikeOutOfRange
  case encodeEnvelope v of
    Left err -> fail ("golden encode failed: " ++ show err)
    Right h -> hexText h @?= goldenHex
