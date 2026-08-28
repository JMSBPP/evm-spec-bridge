// SPDX-License-Identifier: MIT
// Phase 4 fixture methods — hand-written; Phase 9 replaces call sites.
pragma solidity ^0.8.34;

import {callOracle, decodeEnvelope, TAG_REJECTION, TAG_FAULT, PROTOCOL_VERSION} from "../src/SpecOracle.sol";

contract SpecFixturesTest {
    function test_fixtureRejection_tagAndGuard() public {
        (bool ok, bytes memory ret) = callOracle("spec_fixtureRejection", "[]");
        require(ok, "transport");
        (uint16 v, uint8 tag, bytes memory body) = decodeEnvelope(ret);
        require(v == PROTOCOL_VERSION, "version");
        require(tag == TAG_REJECTION, "tag");
        uint8 guardId = abi.decode(body, (uint8));
        require(guardId == 3, "guard");
    }

    function test_fixtureTransportFault_tag() public {
        (bool ok, bytes memory ret) = callOracle("spec_fixtureTransportFault", "[]");
        require(ok, "transport");
        (uint16 v, uint8 tag,) = decodeEnvelope(ret);
        require(v == PROTOCOL_VERSION, "version");
        require(tag == TAG_FAULT, "tag");
    }
}
