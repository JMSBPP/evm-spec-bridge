{-# LANGUAGE OverloadedStrings #-}
module RawConstructor where

import qualified Data.ByteString as BS
import Bridge.AbiCodec.Hex

main :: IO ()
main = print (Hex0x (BS.pack [0x01]))
