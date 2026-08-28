-- | JSON-RPC channel discipline: spec outcomes live in @result@, never @error@.
--
-- PROTO-02. @Network.JSONRPC.Data@ gives @Response@ and @ResponseError@ as separate
-- constructors; @outcomeResponse@ returns @Response@ only. @protocolFault@ is the
-- sole path to @ResponseError@ and takes @ProtocolFault@ — a type with no conversion
-- from @SpecOutcome@.
--
-- alloy sends @\"id\":0@ (measured 02-01-PROBE-NOTES); the request @Id@ is echoed.
{-# LANGUAGE OverloadedStrings #-}
module Bridge.JsonRpc
  ( ProtocolFault (..)
  , outcomeResponse
  , protocolFault
  , componentName
  ) where

import Bridge.AbiCodec.Envelope (EnvelopeError, encodeEnvelope)
import Bridge.Protocol (SpecOutcome (..))

import Data.Aeson (Value (Null), toJSON)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import Data.Text (Text)
import qualified Data.Text as T
import Network.JSONRPC
  ( ErrorObj (..)
  , Id (..)
  , Response (..)
  , Ver (..)
  , errorMethod
  , errorParams
  , errorParse
  )

-- | Protocol-level faults — NOT constructible from a 'SpecOutcome'.
data ProtocolFault
  = UnknownMethod Text
  | BadParams Text
  | ParseFailure
  deriving (Eq, Show)

-- | All three outcomes, rejection included, become a success @Response@ carrying
-- the hex envelope in @result@. This function's body mentions @ResponseError@
-- zero times.
outcomeResponse :: Id -> SpecOutcome BS.ByteString -> Either EnvelopeError Response
outcomeResponse reqId o = do
  h <- encodeEnvelope o
  pure (Response V2 (toJSON h) reqId)

-- | The ONLY function that constructs @ResponseError@.
protocolFault :: Id -> ProtocolFault -> Response
protocolFault reqId fault = ResponseError V2 (faultToError fault) reqId

faultToError :: ProtocolFault -> ErrorObj
faultToError (UnknownMethod m) = errorMethod m
faultToError (BadParams msg) = errorParams Null (T.unpack msg)
faultToError ParseFailure = errorParse (BS8.pack "{}")

componentName :: String
componentName = "evm-spec-bridge-jsonrpc"
