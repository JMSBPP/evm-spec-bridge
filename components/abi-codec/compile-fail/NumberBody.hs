{-# LANGUAGE OverloadedStrings #-}
module NumberBody where

import qualified Data.Aeson as Aeson
import Bridge.AbiCodec.Hex

main :: IO ()
main =
  let h = 42 :: Hex0x
   in print (Aeson.encode h)
