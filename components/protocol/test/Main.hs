-- | Phase 1 test harness.
--
-- Deliberately NOT using tasty-discover: a discovery mechanism that finds zero
-- tests reports success, which is indistinguishable from a suite that ran. The
-- test tree is written by hand so a missing test is a missing line, not a
-- silent zero.
module Main (main) where

import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

import qualified Bridge.Protocol as Protocol

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "evm-spec-bridge"
  [ testCase "protocol component is linked and reachable" $
      Protocol.componentName @?= "evm-spec-bridge-protocol"
  ]
