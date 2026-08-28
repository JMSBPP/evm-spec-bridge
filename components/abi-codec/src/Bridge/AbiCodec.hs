-- | Hex and ABI encoding for the tagged result envelope
module Bridge.AbiCodec
  ( componentName
  , Hex0x
  , HexError (..)
  , hexOfBytes
  , hexOfText
  , hexText
  , hexBytes
  ) where

import Bridge.AbiCodec.Hex

componentName :: String
componentName = "evm-spec-bridge-abi-codec"
