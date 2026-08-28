// SPDX-License-Identifier: MIT
// EXPECTED TO FAIL against --mode wedge. scripts/wedge-red-test.sh asserts the red.
pragma solidity ^0.8.34;

import {requireOutcome, TAG_SUCCESS} from "../src/SpecOracle.sol";

contract WedgeRedTest {
    function test_wedgedOracleIsRed() public {
        (uint8 tag,) = requireOutcome("spec_probe", "[]");
        require(tag == TAG_SUCCESS, "expected success");
    }
}
