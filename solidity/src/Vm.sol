// SPDX-License-Identifier: MIT
// Hand-declared deliberately — forge-std is a separately-versioned submodule and
// this repo's findings are scoped to Foundry 1.5.1/b0a9dd9. Do NOT rely on the
// `returns (bytes memory)` declaration — see PITFALLS.md:100-115.
pragma solidity ^0.8.34;

interface Vm {
    function rpc(string calldata, string calldata, string calldata) external returns (bytes memory);
}

address constant VM_ADDR = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
