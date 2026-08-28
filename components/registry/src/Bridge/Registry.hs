-- | Method registry and pure dispatch for the JSON-RPC surface.
--
-- Phase 4: fixture methods and legacy dev methods. Handlers return 'Response'
-- via 'outcomeResponse' for outcomes; 'protocolFault' for request-level faults.
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
module Bridge.Registry
  ( LegacyMode (..)
  , RpcRequest (..)
  , healthBody
  , dispatch
  , componentName
  ) where

import Bridge.JsonRpc (ProtocolFault (..), outcomeResponse, protocolFault)
import Bridge.Protocol
  ( GuardId (..)
  , SpecOutcome (..)
  , faultInternalError
  )

import Data.Aeson (Value (..))
import Data.Scientific (toRealFloat)
import qualified Data.ByteString as BS
import qualified Data.Text as T
import qualified Data.Vector as V
import Network.JSONRPC (Id (..), Response (..))
import qualified Data.Solidity.Abi.Codec as Abi
import Data.Solidity.Prim.Int (IntN, UIntN)
import Data.Solidity.Prim.Tuple ()

-- | Phase 3 dev-mode flag — affects 'spec_probe' and 'spec_boundary' only.
data LegacyMode = Success | Rejection | Fault | Boundary | Wedge
  deriving (Eq, Show, Read)

-- | Parsed JSON-RPC request fields used by dispatch.
data RpcRequest = RpcRequest
  { rpcMethod :: T.Text
  , reqId :: Id
  , rpcParams :: Value
  }
  deriving (Eq, Show)

-- | Health-check payload: domain-shaped 32-byte sentinel (SRV-06).
healthBody :: BS.ByteString
healthBody = BS.replicate 32 0xcd

-- | Pure method dispatch. Response is a function of mode + request alone for
-- fixture methods; legacy dev methods consult 'LegacyMode'.
--
-- __INVARIANT (PROTO-10):__ @spec_health@, @spec_fixtureRejection@, and
-- @spec_fixtureTransportFault@ ignore 'LegacyMode' and any server-side mutable
-- state. The same request always yields the same response bytes.
dispatch :: LegacyMode -> RpcRequest -> Response
dispatch mode rpc
  | not (T.isPrefixOf "spec_" (rpcMethod rpc)) =
      protocolFault (reqId rpc) (UnknownMethod (rpcMethod rpc))
  | otherwise =
      case rpcMethod rpc of
        "spec_health" -> withEmptyParams rpc (mustOutcome (reqId rpc) (SpecSuccess healthBody))
        "spec_fixtureRejection" ->
          withEmptyParams rpc (mustOutcome (reqId rpc) (SpecRejection GuardStrikeOutOfRange))
        "spec_fixtureTransportFault" ->
          withEmptyParams rpc (mustOutcome (reqId rpc) (SpecTransportFault faultInternalError))
        "spec_probe" -> serveProbe mode (reqId rpc)
        "spec_boundary" -> serveBoundary mode (reqId rpc) (rpcParams rpc)
        _ -> protocolFault (reqId rpc) (UnknownMethod (rpcMethod rpc))

withEmptyParams :: RpcRequest -> Response -> Response
withEmptyParams rpc ok =
  case noParams rpc of
    Just fault -> fault
    Nothing -> ok

serveProbe :: LegacyMode -> Id -> Response
serveProbe Success rpcId = mustOutcome rpcId (SpecSuccess healthBody)
serveProbe Rejection rpcId = mustOutcome rpcId (SpecRejection GuardStrikeOutOfRange)
serveProbe Fault rpcId = mustOutcome rpcId (SpecTransportFault faultInternalError)
serveProbe Boundary rpcId =
  protocolFault rpcId (BadParams "spec_probe unavailable in boundary mode")
serveProbe Wedge rpcId =
  protocolFault rpcId (BadParams "spec_probe unavailable in wedge mode")

serveBoundary :: LegacyMode -> Id -> Value -> Response
serveBoundary Boundary rpcId params =
  case parseBoundaryIndex params of
    Just idx | idx >= 0 && idx <= 4 -> mustOutcome rpcId (SpecSuccess (boundaryBody idx))
    _ -> protocolFault rpcId (BadParams "expected params array with one decimal index 0..4")
serveBoundary _ rpcId _ =
  protocolFault rpcId (BadParams "spec_boundary requires --mode boundary")

noParams :: RpcRequest -> Maybe Response
noParams rpc =
  case rpcParams rpc of
    Array arr | arr == mempty -> Nothing
    _ -> Just (protocolFault (reqId rpc) (BadParams "expected empty params array"))

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

mustOutcome :: Id -> SpecOutcome BS.ByteString -> Response
mustOutcome rpcId o =
  case outcomeResponse rpcId o of
    Left _ -> protocolFault rpcId (BadParams "envelope encode failed")
    Right r -> r

componentName :: String
componentName = "evm-spec-bridge-registry"
