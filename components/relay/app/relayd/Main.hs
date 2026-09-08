module Main (main) where

import Bridge.Relay.Daemon (Config (..), runRelayd)
import Bridge.Relay.Types (defaultQueueBound, defaultTimeoutSec)
import Options.Applicative
  ( Parser
  , ParserInfo
  , auto
  , execParser
  , fullDesc
  , help
  , info
  , long
  , metavar
  , option
  , strOption
  , value
  )

main :: IO ()
main = execParser optsInfo >>= runRelayd . toConfig

data Opts = Opts FilePath Int

optsInfo :: ParserInfo Opts
optsInfo = info (Opts <$> sockOpt <*> timeoutOpt) fullDesc

sockOpt :: Parser FilePath
sockOpt =
  strOption
    (long "sock" <> metavar "PATH" <> help "Unix socket path for the HEVM data plane")

timeoutOpt :: Parser Int
timeoutOpt =
  option
    auto
    (long "timeout" <> metavar "SEC" <> value defaultTimeoutSec <> help "outbound send timeout, seconds")

toConfig :: Opts -> Config
toConfig (Opts sock timeoutSec) =
  Config
    { cfgDataSock = sock
    , cfgCtlSock = sock <> ".ctl"
    , cfgTimeoutSec = timeoutSec
    , cfgQueueBound = defaultQueueBound
    }
