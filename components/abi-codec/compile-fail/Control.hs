{-# LANGUAGE OverloadedStrings #-}
module Control where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import Bridge.AbiCodec.Hex

main :: IO ()
main = print (Aeson.encode (hexOfBytes (BS.pack [0x01])))
