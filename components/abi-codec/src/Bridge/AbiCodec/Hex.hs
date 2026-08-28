-- | Wire hex rendering for the tagged result envelope.
--
-- PROTO-04: the result field's type renders hex and nothing else. A JSON number
-- or @null@ is unrepresentable because the data constructor is not exported and
-- there is no @Num@ instance.
{-# LANGUAGE OverloadedStrings #-}
module Bridge.AbiCodec.Hex
  ( Hex0x
  , HexError (..)
  , hexOfBytes
  , hexOfText
  , hexText
  , hexBytes
  ) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Encoding as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base16 as Base16
import qualified Data.Char as Char
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE

-- | A @0x@-prefixed even-nibble hex string on the wire.
--
-- The constructor is deliberately NOT exported: outside this module the only
-- ways to obtain a value are the smart constructors, every one of which
-- produces bytes.
newtype Hex0x = Hex0x BS.ByteString

-- | Errors from parsing a text hex string.
data HexError
  = MissingPrefix
  | OddNibbleCount Int
  | NonHexNibble Char
  deriving (Eq, Show)

-- | Wrap raw bytes as wire hex. Total — any 'ByteString' has an even nibble count.
hexOfBytes :: BS.ByteString -> Hex0x
hexOfBytes = Hex0x

-- | Parse a @0x@-prefixed even-length hex string.
hexOfText :: T.Text -> Either HexError Hex0x
hexOfText t
  | not (T.isPrefixOf "0x" t) = Left MissingPrefix
  | otherwise = go (T.drop 2 t)
  where
    go hexBody
      | n `mod` 2 /= 0 = Left (OddNibbleCount n)
      | otherwise =
          case firstBadNibble (T.unpack hexBody) of
            Just c -> Left (NonHexNibble c)
            Nothing ->
              case Base16.decode (TE.encodeUtf8 hexBody) of
                Left _ -> Left (NonHexNibble '?')
                Right bs -> Right (Hex0x bs)
      where
        n = T.length hexBody

firstBadNibble :: String -> Maybe Char
firstBadNibble = go
  where
    go [] = Nothing
    go (c : cs)
      | isHex c = go cs
      | otherwise = Just c

isHex :: Char -> Bool
isHex c = Char.isDigit c || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')

-- | Render as @0x@ + lowercase hex.
hexText :: Hex0x -> T.Text
hexText (Hex0x bs) = "0x" <> TE.decodeUtf8 (Base16.encode bs)

-- | The decoded bytes, for the ABI layer.
hexBytes :: Hex0x -> BS.ByteString
hexBytes (Hex0x bs) = bs

instance Aeson.ToJSON Hex0x where
  toJSON = Aeson.String . hexText
  toEncoding = Aeson.text . hexText
