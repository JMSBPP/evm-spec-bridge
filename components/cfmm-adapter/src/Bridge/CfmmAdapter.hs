-- | The only component permitted to depend on the cfmm spec.
--
-- Phase 1 placeholder — but it imports a REAL symbol from the spec on purpose.
-- A dependency that is declared but never used is one Stack could drop, which
-- would make the seam guard's positive control pass for the wrong reason.
module Bridge.CfmmAdapter (componentName, specReachable) where

import Panoptic.NId (fourLegNumLegs)

componentName :: String
componentName = "evm-spec-bridge-cfmm-adapter"

-- | Proves the spec is genuinely linked, not merely listed.
specReachable :: Int
specReachable = fourLegNumLegs
