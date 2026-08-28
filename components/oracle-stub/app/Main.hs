{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Bridge.Registry (LegacyMode (..))
import Bridge.Transport (serve)

import Options.Applicative
  ( Parser
  , ParserInfo
  , ReadM
  , auto
  , eitherReader
  , execParser
  , fullDesc
  , help
  , info
  , long
  , metavar
  , option
  , short
  , value
  )

main :: IO ()
main = execParser optsInfo >>= \(Opts {optPort = p, optMode = m}) -> serve m p

data Opts = Opts {optPort :: Int, optMode :: LegacyMode}

optsInfo :: ParserInfo Opts
optsInfo = info (Opts <$> portOpt <*> modeOpt) fullDesc

portOpt :: Parser Int
portOpt = option auto (long "port" <> short 'p' <> metavar "PORT" <> value 8899)

modeOpt :: Parser LegacyMode
modeOpt =
  option
    readMode
    (long "mode" <> metavar "MODE" <> help "success | rejection | fault | boundary | wedge")

readMode :: ReadM LegacyMode
readMode = eitherReader $ \s ->
  case map toLower s of
    "success" -> Right Success
    "rejection" -> Right Rejection
    "fault" -> Right Fault
    "boundary" -> Right Boundary
    "wedge" -> Right Wedge
    _ -> Left ("unknown mode: " ++ s)
  where
    toLower c
      | c >= 'A' && c <= 'Z' = toEnum (fromEnum c + 32)
      | otherwise = c
