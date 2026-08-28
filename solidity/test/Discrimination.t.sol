// SPDX-License-Identifier: MIT
// Phase 3 hand-written — Phase 9 replaces generated call sites.
pragma solidity ^0.8.34;

import {callOracle, decodeEnvelope, TAG_SUCCESS, TAG_REJECTION, TAG_FAULT, PROTOCOL_VERSION} from "../src/SpecOracle.sol";

contract DiscriminationTest {
    function test_rejection_isReadAsRejection() public {
        (bool ok, bytes memory ret) = callOracle("spec_probe", "[]");
        require(ok, "transport");
        (uint16 v, uint8 tag, bytes memory body) = decodeEnvelope(ret);
        require(v == PROTOCOL_VERSION, "version");
        require(tag == TAG_REJECTION, "tag");
        uint8 guardId = abi.decode(body, (uint8));
        require(guardId == 3, "guard");
    }

    function test_deadServer_doesNotLookLikeRejection() public {
        (bool ok,) = callOracle("spec_probe", "[]");
        require(!ok, "expected transport failure");
    }

    function test_success_isReadAsSuccess() public {
        (bool ok, bytes memory ret) = callOracle("spec_probe", "[]");
        require(ok, "transport");
        (uint16 v, uint8 tag,) = decodeEnvelope(ret);
        require(v == PROTOCOL_VERSION, "version");
        require(tag == TAG_SUCCESS, "tag");
    }

    function test_faultPath_carriesVersion() public {
        (bool ok, bytes memory ret) = callOracle("spec_probe", "[]");
        require(ok, "transport");
        (uint16 v, uint8 tag,) = decodeEnvelope(ret);
        require(v == PROTOCOL_VERSION, "version");
        require(tag == TAG_FAULT, "tag");
    }
}
