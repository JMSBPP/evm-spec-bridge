-- | The only component permitted to depend on the cfmm spec.
--
-- Phase 1 placeholder — but it uses a REAL symbol from the spec on purpose.
-- A dependency that is declared but never used is one the toolchain could drop,
-- which would let the seam guard's positive control pass for the wrong reason.
--
-- NOTE (learned the hard way): `stack build --dry-run`, which is what the seam
-- guard runs, resolves a BUILD PLAN and does not compile anything. This module
-- sat here for four plans with a type error in it while every check reported
-- green, because no check was pointed at compiling it. The CI `build` job is
-- what caught it.
module Bridge.CfmmAdapter (componentName, specNumLegs) where

import Panoptic.NId (PanopticTokenId, fourLegNumLegs)

componentName :: String
componentName = "evm-spec-bridge-cfmm-adapter"

-- | Proves the spec is genuinely linked, not merely listed.
--
-- Re-exports the spec's own function rather than a constant: `fourLegNumLegs`
-- is @PanopticTokenId -> Int@, and binding it to an @Int@ was the type error
-- above. Keeping the real signature means this breaks loudly if the spec's API
-- changes, which is the point of importing it at all.
specNumLegs :: PanopticTokenId -> Int
specNumLegs = fourLegNumLegs
