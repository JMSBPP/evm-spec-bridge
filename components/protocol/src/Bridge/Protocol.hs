-- | Wire protocol types for the evm-spec-bridge oracle.
--
-- PROTO-01: spec success, spec rejection and transport fault are three
-- CONSTRUCTORS, not a record with a status field. A status field would permit
-- @outcome { outcomeStatus = Success }@ over a value still carrying rejection
-- data; constructors make that unrepresentable, so no partial function can
-- turn one outcome into another.
--
-- This module is TYPES ONLY: its sole import is @Data.Word@. No JSON library and
-- no ABI library is in scope here -- JSON-RPC framing is @Bridge.JsonRpc@
-- (03-04) and the hex-ABI envelope is @Bridge.AbiCodec.Envelope@ (03-03).
-- Keeping the encoding out means the outcome type can be read without reading a
-- codec, and it keeps this component's dependency list at @base@ alone.
--
-- (The encoder and JSON module names are deliberately NOT spelled out in this
-- comment: the automated check for "no encoding dependency here" greps for them,
-- and prose that trips a structural check trains people to ignore the check.)
--
-- CFMM-01: @protocol@ is a CORE component. It must remain satisfiable from the
-- snapshot alone (see @stack-core.yaml@ and @scripts/seam-guard.sh@), so the
-- guard enum below is OURS and is not derived from the spec's guard type.
-- Naming a constructor after a cfmm guard creates no package dependency.
-- @cfmm-adapter@ -- the only component permitted a spec edge -- maps the spec's
-- guard onto 'GuardId' with an exhaustive match, and that match is the compile
-- error INTEG-02 asks for.
module Bridge.Protocol
  ( -- * The three outcomes
    SpecOutcome (..)

    -- * Rejection identity
  , GuardId (..)

    -- * Protocol faults
  , FaultCode (..)
  , faultDeadlineExceeded
  , faultSpecUnavailable
  , faultMalformedRequest
  , faultUnsupportedMethod
  , faultInternalError

    -- * Protocol version
  , protocolVersion

    -- * Component identity
  , componentName
  ) where

import Data.Word (Word16)

-- | The result of asking the spec a question.
--
-- Exactly three constructors, and deliberately no fourth: a non-answer is not
-- an outcome. The call site that receives one of these must produce a verdict
-- from it, which is what makes a wedged oracle red rather than silently green.
--
-- @a@ is the success payload, left polymorphic so the encoding layer can
-- instantiate it (03-03 uses @SpecOutcome ByteString@) without this module
-- knowing what a byte string is for.
--
-- Note on 'SpecTransportFault': on the wire it is never a successful response
-- at all -- Foundry collapses every transport failure into one untyped revert.
-- It exists here because the SERVER can classify its own faults, and because
-- the fixture methods must be able to produce one deliberately.
data SpecOutcome a
  = SpecSuccess a
    -- ^ The spec evaluated the request and returned a payload.
  | SpecRejection GuardId
    -- ^ The spec evaluated the request and a named guard refused it.
    -- Guard IDENTITY only: INTEG-02 forbids a free-text guard string, because
    -- a string that exists is a string a consumer will begin matching on.
  | SpecTransportFault FaultCode
    -- ^ The spec was never asked, or its answer never arrived intact.
  deriving (Eq, Show)

-- | The closed set of guards a rejection can name.
--
-- Closed and NAMED: INTEG-02. 'Enum' and 'Bounded' are load-bearing, not
-- convenience -- they let a test write @[minBound .. maxBound]@ and assert
-- total coverage, so a guard added here without a corresponding mapping or
-- encoding is caught by a test rather than by a reader.
--
-- cfmm vocabulary in a core component is deliberate: PROJECT.md's "cfmm-first,
-- generalize later" decision. Constructor names are not dependencies.
--
-- The 'Enum' index IS the wire value (03-03 encodes @fromEnum@ as a @uint8@).
-- Constructors are therefore APPEND-ONLY: reordering or removing one silently
-- renumbers every guard already deployed.
data GuardId
  = GuardUnknownMarket
    -- ^ 0 -- the requested market is not one the spec knows.
  | GuardExpiryInPast
    -- ^ 1 -- the order's expiry is at or before the evaluation time.
  | GuardNotionalOutOfRange
    -- ^ 2 -- notional is zero, negative, or above the market's cap.
  | GuardStrikeOutOfRange
    -- ^ 3 -- strike is outside the market's admissible strike band.
  | GuardImpliedVolOutOfRange
    -- ^ 4 -- implied volatility is non-positive or above the cap.
  | GuardInsufficientCollateral
    -- ^ 5 -- posted collateral does not cover the order's requirement.
  | GuardInvariantViolated
    -- ^ 6 -- the trade would move the pool off its invariant.
  deriving (Eq, Show, Enum, Bounded)

-- | A protocol- or transport-level fault code.
--
-- A newtype rather than a bare 'Word16' so a fault code cannot be passed where
-- a 'protocolVersion' is wanted, and vice versa -- both are @uint16@ on the
-- wire and would otherwise be interchangeable.
--
-- These classify OUR failures, never the spec's verdict. Nothing here can be
-- reached from a 'SpecRejection': that is the RPC-02 split -- the spec
-- evaluates guards, the bridge classifies errors.
newtype FaultCode = FaultCode Word16
  deriving (Eq, Show)

-- | 0 is deliberately unassigned, for the same reason tag @0x00@ is reserved
-- in the envelope: an all-zeroes decode must not name a real fault.
faultDeadlineExceeded :: FaultCode
faultDeadlineExceeded = FaultCode 1

-- | The spec could not be reached or refused to start.
faultSpecUnavailable :: FaultCode
faultSpecUnavailable = FaultCode 2

-- | A request arrived that this protocol could not parse.
faultMalformedRequest :: FaultCode
faultMalformedRequest = FaultCode 3

-- | A request named a method this server does not implement.
faultUnsupportedMethod :: FaultCode
faultUnsupportedMethod = FaultCode 4

-- | A fault the bridge could not classify further.
faultInternalError :: FaultCode
faultInternalError = FaultCode 5

-- | PROTO-07: every response carries the protocol version.
--
-- Defined ONCE, here. Construction sites must reference this binding rather
-- than write @1@ -- a literal repeated at each site is a version that can be
-- bumped in four places and forgotten in the fifth.
--
-- Word 0 of the envelope (03-03), ahead of the tag, so a version mismatch is
-- caught where the payload is actually decoded.
protocolVersion :: Word16
protocolVersion = 1

-- | Identity of this component, asserted by the Phase 1 linkage test.
componentName :: String
componentName = "evm-spec-bridge-protocol"
