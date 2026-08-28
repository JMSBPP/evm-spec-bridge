-- | Hex and ABI encoding for the tagged result envelope
module Bridge.AbiCodec
  ( componentName
  , Hex0x
  , HexError (..)
  , hexOfBytes
  , hexOfText
  , hexText
  , hexBytes
  , EnvelopeError (..)
  , encodeEnvelope
  , decodeEnvelope
  , tagSuccess
  , tagRejection
  , tagFault
  , tagOf
  ) where

import Bridge.AbiCodec.Envelope
import Bridge.AbiCodec.Hex

componentName :: String
componentName = "evm-spec-bridge-abi-codec"
