// SPDX-License-Identifier: MIT
// HEVM cheat surface via StdCheats-style `vm.ffi` → `relay` → relayd → HEVM.
// Named `hevm` so call sites read `hevm.call(method, params)` (library member).
// Hand-declared Vm (no forge-std submodule) — same cheat address as StdCheats.
pragma solidity ^0.8.34;

import {Vm, VM_ADDR} from "./Vm.sol";

library hevm {
    /// @notice JSON-RPC call to the HEVM peer through the Unix-socket relay.
    /// @param method JSON-RPC method name (opaque to the relay).
    /// @param paramsJson JSON-RPC params value as a JSON string (e.g. `"[1]"`).
    /// @return resultStdout Raw stdout from `relay send` (JSON-RPC `result` encoding).
    function call(string memory method, string memory paramsJson) internal returns (bytes memory resultStdout) {
        string[] memory inputs = new string[](4);
        inputs[0] = "relay";
        inputs[1] = "send";
        inputs[2] = method;
        inputs[3] = paramsJson;
        // Low-level call: do not trust interface return encoding across forge pins
        // (same rationale as SpecOracle.callOracle / PITFALLS.md).
        (bool ok, bytes memory ret) = VM_ADDR.call(abi.encodeWithSignature("ffi(string[])", inputs));
        require(ok, "hevm.call: ffi failed");
        resultStdout = abi.decode(ret, (bytes));
    }
}
