{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Bridge.JsonRpc (ProtocolFault (..), outcomeResponse, protocolFault)
import Bridge.Protocol
  ( GuardId (..)
  , SpecOutcome (..)
  , faultInternalError
  )

import qualified Control.Concurrent as Concurrent
import Control.Monad (forever)
import Data.Aeson (FromJSON (..), Value (..), withObject, (.:))
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Scientific (toRealFloat)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Vector as V
import Network.HTTP.Types (hContentType, status200)
import Network.HTTP.Types.Header (hContentLength)
import qualified Network.JSONRPC as RPC
import Network.Wai (Application, Response, responseLBS, strictRequestBody)
import Network.Wai.Handler.Warp (run)
import Options.Applicative
  (   Parser
  ,   ParserInfo
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
import qualified Data.Solidity.Abi.Codec as Abi
import Data.Solidity.Prim.Int (IntN, UIntN)
import Data.Solidity.Prim.Tuple ()
import System.IO (hPutStrLn, stderr)

data Mode = Success | Rejection | Fault | Boundary | Wedge
  deriving (Eq, Show, Read)

data RpcRequest = RpcRequest
  { rpcMethod :: Text
  , rpcReqId :: Value
  , rpcParams :: Value
  }

instance FromJSON RpcRequest where
  parseJSON = withObject "request" $ \o ->
    RpcRequest <$> o .: "method" <*> o .: "id" <*> o .: "params"

main :: IO ()
main = execParser optsInfo >>= \(Opts {optPort = p, optMode = m}) -> run p (app m)

data Opts = Opts {optPort :: Int, optMode :: Mode}

optsInfo :: ParserInfo Opts
optsInfo = info (Opts <$> portOpt <*> modeOpt) fullDesc

portOpt :: Parser Int
portOpt = option auto (long "port" <> short 'p' <> metavar "PORT" <> value 8899)

modeOpt :: Parser Mode
modeOpt =
  option
    readMode
    (long "mode" <> metavar "MODE" <> help "success | rejection | fault | boundary | wedge")

readMode :: ReadM Mode
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

app :: Mode -> Application
app mode request respond =
  case mode of
    Wedge -> wedgeHandler request respond
    _ -> normalHandler mode request respond

normalHandler :: Mode -> Application
normalHandler mode request respond = do
  body <- strictRequestBody request
  let resp =
        case Aeson.eitherDecode body of
          Left _ -> protocolFault (RPC.IdInt 0) ParseFailure
          Right rpc -> handleRpc mode rpc
  respond (jsonResp resp)

wedgeHandler :: Application
wedgeHandler request respond = do
  _body <- strictRequestBody request
  case Aeson.eitherDecode _body of
    Left _ -> respond (jsonResp (protocolFault (RPC.IdInt 0) ParseFailure))
    Right rpc -> do
      hPutStrLn stderr ("wedge: reached handler method=" ++ T.unpack (rpcMethod rpc))
      forever (Concurrent.threadDelay maxBound)

handleRpc :: Mode -> RpcRequest -> RPC.Response
handleRpc mode rpc =
  case rpcMethod rpc of
    "spec_probe" -> serveProbe mode (parseId (rpcReqId rpc))
    "spec_boundary" -> serveBoundary mode (parseId (rpcReqId rpc)) (rpcParams rpc)
    _ -> protocolFault (parseId (rpcReqId rpc)) (UnknownMethod (rpcMethod rpc))

serveProbe :: Mode -> RPC.Id -> RPC.Response
serveProbe Success rpcId = mustOutcome rpcId (SpecSuccess (BS.replicate 32 0xcd))
serveProbe Rejection rpcId = mustOutcome rpcId (SpecRejection GuardStrikeOutOfRange)
serveProbe Fault rpcId = mustOutcome rpcId (SpecTransportFault faultInternalError)
serveProbe Boundary rpcId = protocolFault rpcId (BadParams "spec_probe unavailable in boundary mode")
serveProbe Wedge rpcId = protocolFault rpcId (BadParams "spec_probe unavailable in wedge mode")

serveBoundary :: Mode -> RPC.Id -> Value -> RPC.Response
serveBoundary Boundary rpcId params =
  case parseBoundaryIndex params of
    Just idx | idx >= 0 && idx <= 4 -> mustOutcome rpcId (SpecSuccess (boundaryBody idx))
    _ -> protocolFault rpcId (BadParams "expected params array with one decimal index 0..4")
serveBoundary _ rpcId _ = protocolFault rpcId (BadParams "spec_boundary requires --mode boundary")

boundaryBody :: Int -> BS.ByteString
boundaryBody 0 = Abi.encode (0 :: UIntN 256) :: BS.ByteString
boundaryBody 1 = Abi.encode (18446744073709551616 :: UIntN 256) :: BS.ByteString
boundaryBody 2 = Abi.encode (-5 :: IntN 256) :: BS.ByteString
boundaryBody 3 = BS.empty
boundaryBody 4 = BS.replicate 32 0xcd
boundaryBody _ = BS.empty

parseBoundaryIndex :: Value -> Maybe Int
parseBoundaryIndex val =
  case val of
    Array arr ->
      case V.toList arr of
        [Number n] -> Just (truncate (toRealFloat n :: Double))
        _ -> Nothing
    _ -> Nothing

mustOutcome :: RPC.Id -> SpecOutcome BS.ByteString -> RPC.Response
mustOutcome rpcId o =
  case outcomeResponse rpcId o of
    Left _ -> protocolFault rpcId (BadParams "envelope encode failed")
    Right r -> r

parseId :: Value -> RPC.Id
parseId (Number n) = RPC.IdInt (truncate (toRealFloat n :: Double))
parseId (String t) = RPC.IdTxt t
parseId Null = RPC.IdInt 0
parseId _ = RPC.IdInt 0

jsonResp :: RPC.Response -> Response
jsonResp resp =
  let bs = Aeson.encode resp
   in responseLBS
        status200
        [ (hContentType, "application/json")
        , (hContentLength, TE.encodeUtf8 (T.pack (show (LBS.length bs))))
        ]
        bs
