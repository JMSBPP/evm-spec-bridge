-- | Hex-ABI envelope: abi.encode(uint16 version, uint8 tag, bytes body).
--
-- PROTO-03. Version travels FIRST so a mismatch is caught where the payload is
-- decoded. Tag values: @0x01@ success, @0x02@ rejection, @0x03@ fault.
-- @0x00@ is RESERVED — PITFALLS.md:164 measured JSON @null@ arrives as 32 zero
-- bytes with @success == true@; a zero tag would decode as valid success.
--
-- If the even-nibble or word-multiple assertion in 'encodeEnvelope' ever fires
-- against @web3-solidity-1.1.0.0@, suspect the library — not the caller.
{-# LANGUAGE DataKinds #-}
module Bridge.AbiCodec.Envelope
  ( EnvelopeError (..)
  , tagSuccess
  , tagRejection
  , tagFault
  , tagOf
  , encodeEnvelope
  , decodeEnvelope
  ) where

import Bridge.AbiCodec.Hex (Hex0x, hexBytes, hexOfBytes)
import Bridge.Protocol
  ( FaultCode (..)
  , SpecOutcome (..)
  , protocolVersion
  )

import Data.ByteArray (convert)
import qualified Data.ByteString as BS
import qualified Data.Solidity.Abi.Codec as Abi
import Data.Solidity.Prim.Bytes (Bytes)
import Data.Solidity.Prim.Int (UIntN)
import Data.Solidity.Prim.Tuple ()
import Data.Word (Word8, Word16)

-- | Wire tag for 'SpecSuccess'.
tagSuccess :: Word8
tagSuccess = 0x01

-- | Wire tag for 'SpecRejection'.
tagRejection :: Word8
tagRejection = 0x02

-- | Wire tag for 'SpecTransportFault'.
tagFault :: Word8
tagFault = 0x03

-- | Map a 'SpecOutcome' to its wire tag. Total — no catch-all.
tagOf :: SpecOutcome a -> Word8
tagOf (SpecSuccess _) = tagSuccess
tagOf (SpecRejection _) = tagRejection
tagOf (SpecTransportFault _) = tagFault

-- | Errors decoding or encoding the envelope.
data EnvelopeError
  = OddNibbleEmitted Int
  | UnknownTag Word8
  | ShortEnvelope Int
  | VersionMismatch Word16 Word16
  | AbiDecodeFailed String
  deriving (Eq, Show)

type EnvelopeTuple = (UIntN 16, UIntN 8, Bytes)

-- | Encode a three-outcome value to even-nibble hex ABI envelope.
encodeEnvelope :: SpecOutcome BS.ByteString -> Either EnvelopeError Hex0x
encodeEnvelope o = do
  body <- bodyOf o
  let ver = fromIntegral protocolVersion :: UIntN 16
      tag = fromIntegral (tagOf o) :: UIntN 8
      raw = Abi.encode (ver, tag, body) :: BS.ByteString
  assertLayout raw
  pure (hexOfBytes raw)

-- | Decode even-nibble hex ABI envelope to a three-outcome value.
decodeEnvelope :: Hex0x -> Either EnvelopeError (SpecOutcome BS.ByteString)
decodeEnvelope h = do
  let raw = hexBytes h
  whenShort raw
  (ver, tag, body) <-
    either (Left . AbiDecodeFailed) Right (Abi.decode raw :: Either String EnvelopeTuple)
  let verW16 = word16OfUInt ver
  whenVersion (verW16 /= protocolVersion) (VersionMismatch protocolVersion verW16)
  outcomeOf tag body

bodyOf :: SpecOutcome BS.ByteString -> Either EnvelopeError Bytes
bodyOf (SpecSuccess bs) = pure (convert bs)
bodyOf (SpecRejection g) =
  pure $
    convert (Abi.encode (fromIntegral (fromEnum g) :: UIntN 8) :: BS.ByteString)
bodyOf (SpecTransportFault (FaultCode fc)) =
  pure $
    convert (Abi.encode (fromIntegral fc :: UIntN 16) :: BS.ByteString)

assertLayout :: BS.ByteString -> Either EnvelopeError ()
assertLayout raw
  | odd (BS.length raw) = Left (OddNibbleEmitted (2 * BS.length raw))
  | BS.length raw `mod` 32 /= 0 = Left (OddNibbleEmitted (2 * BS.length raw))
  | otherwise = Right ()

whenShort :: BS.ByteString -> Either EnvelopeError ()
whenShort raw
  | BS.length raw < 96 = Left (ShortEnvelope (BS.length raw))
  | otherwise = Right ()

outcomeOf :: UIntN 8 -> Bytes -> Either EnvelopeError (SpecOutcome BS.ByteString)
outcomeOf tag body
  | word8OfUInt tag == tagSuccess =
      pure (SpecSuccess (convert body))
  | word8OfUInt tag == tagRejection = do
      gid <-
        either (Left . AbiDecodeFailed) Right (Abi.decode (convert body :: BS.ByteString) :: Either String (UIntN 8))
      pure (SpecRejection (toEnum (fromIntegral (word8OfUInt gid))))
  | word8OfUInt tag == tagFault = do
      fc <-
        either (Left . AbiDecodeFailed) Right (Abi.decode (convert body :: BS.ByteString) :: Either String (UIntN 16))
      pure (SpecTransportFault (FaultCode (word16OfUInt fc)))
  | otherwise = Left (UnknownTag (word8OfUInt tag))

word8OfUInt :: UIntN 8 -> Word8
word8OfUInt u = fromIntegral u

word16OfUInt :: UIntN 16 -> Word16
word16OfUInt u = fromIntegral u

whenVersion :: Bool -> EnvelopeError -> Either EnvelopeError ()
whenVersion True err = Left err
whenVersion False _ = Right ()
