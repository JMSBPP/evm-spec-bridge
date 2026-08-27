-- | Phase 1 executable: reports its identity and exits.
--
-- Deliberately trivial. Its purpose is to be a REAL -threaded GHC binary whose
-- linkage can be inspected with ldd, so the runtime image's contents are decided
-- from evidence rather than from a list someone copied.
module Main (main) where

import qualified Bridge.Transport as Transport
import System.Environment (getArgs)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["--version"] -> putStrLn (Transport.componentName <> " 0.1.0.0")
    _             -> putStrLn (Transport.componentName <> " 0.1.0.0 (pass --version)")
