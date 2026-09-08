// SPDX-License-Identifier: MIT
// Smoke: hevm.call("echo", …) via ffi → relay → FakeHevm echo peer.
pragma solidity ^0.8.34;

import {hevm} from "../src/Hevm.sol";

contract HevmCallTest {
    function test_hevmCall_echo() public {
        bytes memory out = hevm.call("echo", "[1]");
        // relay prints compact JSON result; FakeHevm reflects params → `[1]`
        require(out.length >= 3, "empty result");
        require(out[0] == bytes1(uint8(0x5b)), "expected '['"); // 0x5b = '['
        require(out[1] == bytes1(uint8(0x31)), "expected '1'"); // 0x31 = '1'
        require(out[2] == bytes1(uint8(0x5d)), "expected ']'"); // 0x5d = ']'
    }
}
