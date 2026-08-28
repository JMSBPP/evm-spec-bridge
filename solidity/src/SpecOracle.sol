// SPDX-License-Identifier: MIT
// Phase 3 hand-written call site — GENERATED in Phase 9 (GEN-04).
pragma solidity ^0.8.34;

import {Vm, VM_ADDR} from "./Vm.sol";

// Hand-maintained in Phase 3; GENERATED in Phase 8/9.
uint8 constant TAG_SUCCESS = 0x01;
uint8 constant TAG_REJECTION = 0x02;
uint8 constant TAG_FAULT = 0x03;
uint16 constant PROTOCOL_VERSION = 1;

function callOracle(string memory method, string memory params) returns (bool ok, bytes memory ret) {
    (ok, ret) = VM_ADDR.call(abi.encodeWithSignature("rpc(string,string,string)", "evm_spec_bridge", method, params));
}

function decodeEnvelope(bytes memory ret) pure returns (uint16 version, uint8 tag, bytes memory body) {
    bytes memory payload = abi.decode(ret, (bytes));
    (version, tag, body) = abi.decode(payload, (uint16, uint8, bytes));
}

function vm_uint2str(uint256 n) pure returns (string memory) {
    if (n == 0) return "0";
    uint256 temp = n;
    uint256 digits;
    while (temp != 0) {
        digits++;
        temp /= 10;
    }
    bytes memory buffer = new bytes(digits);
    while (n != 0) {
        digits -= 1;
        buffer[digits] = bytes1(uint8(48 + (n % 10)));
        n /= 10;
    }
    return string(buffer);
}

function requireOutcome(string memory method, string memory params) returns (uint8 tag, bytes memory body) {
    (bool ok, bytes memory ret) = callOracle(method, params);
    require(ok, "oracle transport failure");
    bytes memory payload = abi.decode(ret, (bytes));
    uint16 version;
    (version, tag, body) = abi.decode(payload, (uint16, uint8, bytes));
    require(version == PROTOCOL_VERSION, "protocol version");
    require(tag == TAG_SUCCESS || tag == TAG_REJECTION || tag == TAG_FAULT, "unknown tag");
}
