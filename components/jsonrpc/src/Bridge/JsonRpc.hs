-- | JSON-RPC 2.0 envelope. NOT hand-rolled -- the types come from json-rpc-1.1.2's
-- Network.JSONRPC.Data (in LTS 24.55). Its Interface module is rejected: TCP-conduit
-- transports only, which cannot answer Foundry's HTTP POST. See 02-CONTEXT.md.
--
-- Phase 1 placeholder. This module exists so the component is real — a package
-- with no modules is not evidence that the seam works.
module Bridge.JsonRpc (componentName) where

componentName :: String
componentName = "evm-spec-bridge-jsonrpc"
