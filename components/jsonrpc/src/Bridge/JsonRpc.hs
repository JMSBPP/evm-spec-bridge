-- | JSON-RPC 2.0 envelope, hand-rolled to own the error channel
--
-- Phase 1 placeholder. This module exists so the component is real — a package
-- with no modules is not evidence that the seam works.
module Bridge.JsonRpc (componentName) where

componentName :: String
componentName = "evm-spec-bridge-jsonrpc"
