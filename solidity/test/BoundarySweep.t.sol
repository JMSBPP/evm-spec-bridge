// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {
    callOracle,
    decodeEnvelope,
    vm_uint2str,
    TAG_SUCCESS,
    PROTOCOL_VERSION
} from "../src/SpecOracle.sol";

contract BoundarySweepTest {
    event BoundaryRow(uint256 idx, uint256 lenRaw, uint256 lenPayload, uint256 lenBody, bytes32 bodyHash);

    function test_boundarySweep() public {
        _runCase(0, 32, 0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563);
        _runCase(1, 32, 0xd0efa0dfe4ed9e53ca9d02cb3744c3f0317da5057735ae4b2fec135adffb2c35);
        _runCase(2, 32, 0x7234c58e51ab4abdf62492ac6faf025ebff2afd4f861cebfa33d3e76667716a9);
        _runCase(3, 0, 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470);
        _runCase(4, 32, 0x1e316fd2d4aa483cfa2a178b564eb8ea0ab562421eca3ca32fe78da277452e45);
    }

    function _runCase(uint256 idx, uint256 expectedBodyLen, bytes32 expectedHash) internal {
        (bool ok, bytes memory ret) = callOracle("spec_boundary", string.concat("[", vm_uint2str(idx), "]"));
        require(ok, "transport");
        uint256 lenRaw = ret.length;
        bytes memory payload = abi.decode(ret, (bytes));
        uint256 lenPayload = payload.length;
        (uint16 v, uint8 tag, bytes memory body) = abi.decode(payload, (uint16, uint8, bytes));
        require(v == PROTOCOL_VERSION, "version");
        require(tag == TAG_SUCCESS, "tag");
        uint256 lenBody = body.length;
        require(lenPayload % 32 == 0, "payload mod");
        require(lenBody == expectedBodyLen, "body len");
        bytes32 h = keccak256(body);
        emit BoundaryRow(idx, lenRaw, lenPayload, lenBody, h);
        require(h == expectedHash, "body hash");
    }
}
