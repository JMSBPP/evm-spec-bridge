// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

// THROWAWAY. Deleted in plan 02-05 together with the rest of spike/.
//
// NO IMPORTS, ON PURPOSE. forge-std would need a submodule (deletion stops being
// `rm -rf spike/`), would bring a version we then have to pin, and would hand us a
// TYPED cheatcode binding -- the exact trap PITFALLS.md:100-115 MEASURED. On forge
// 1.5.1-stable the raw returndata of the cheatcode is `abi.encode(<coerced value>)`,
// NOT `abi.encode(<bytes>)`, so assigning the cheatcode's return straight into a
// `bytes memory` local sometimes reverts with a bare `EvmError: Revert` and sometimes
// returns SILENT GARBAGE that decodes without complaint. A silent wrong answer in an
// oracle is the failure this project exists to prevent, so we take the returndata RAW,
// record it, and decode deliberately.
//
// The interface below is declared only to document the cheatcode's signature. It is
// never used to make a call -- every call site goes through the low-level form.
interface VmLike {
    function rpc(string calldata, string calldata, string calldata) external returns (bytes memory);
}

address constant VM_ADDR = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

contract SpikeTest {
    // Observation channel. Emitted BEFORE anything is interpreted.
    // MEASURED on forge 1.5.1: for a PASSING test these show up only at -vvvv (-vvv
    // prints traces for failing tests only), and hand-rolled console.log calls to
    // 0x...636f are not surfaced in the "Logs:" section at any verbosity, so the
    // events are the record.
    event RawReturndata(uint256 length, bytes raw);
    event DecodedPayload(uint256 length, bytes decoded);

    // Hardcoded on purpose; the env-var alias is SRV-09, Phase 6.
    string constant URL = "http://127.0.0.1:8547";
    string constant METHOD = "spec_health";
    string constant PARAMS = "[]";

    // The stub's hardcoded result, verbatim from spike/stub-server/app/Main.hs:
    // the 32-byte big-endian ABI encoding of decimal 42.
    bytes constant EXPECTED = hex"000000000000000000000000000000000000000000000000000000000000002a";

    // Low-level ONLY. We own the (bool ok, bytes memory ret) split, so a cheatcode
    // revert reaches us as data instead of unwinding the test.
    function _rawRpc() private returns (bool ok, bytes memory ret) {
        (ok, ret) = address(VM_ADDR).call(
            abi.encodeWithSignature("rpc(string,string,string)", URL, METHOD, PARAMS)
        );
    }

    /// The full path: call, record, THEN interpret.
    function test_vmRpcReachesWarp() public {
        (bool ok, bytes memory ret) = _rawRpc();

        // OBSERVATION -- emitted verbatim before ok is even checked.
        emit RawReturndata(ret.length, ret);

        // Exit code before interpretation (Phase 1 rule, Solidity form). On failure
        // `ret` is the errdata: a CheatcodeError(string) (selector 0xeeaa9e6f) whose
        // string body names the cause -- run with -vvv to read it.
        require(ok, "vm.rpc reverted -- see -vvv for CheatcodeError body");
        require(ret.length > 0, "empty returndata");

        // INTERPRETATION. Whether this decode succeeds is the measurement; it is NOT
        // an assumption this test is shaped around.
        bytes memory decoded = abi.decode(ret, (bytes));
        emit DecodedPayload(decoded.length, decoded);

        require(
            keccak256(decoded) == keccak256(EXPECTED),
            "decoded payload != stub's 32-byte encoding of 42"
        );
    }

    /// Shape-only. No decode, no equality assertion, so the raw bytes stay observable
    /// even when the decode assertion above fails.
    function test_rawShapeIsRecorded() public {
        // `ok` is deliberately discarded: this function records the SHAPE, nothing else.
        (, bytes memory ret) = _rawRpc();
        emit RawReturndata(ret.length, ret);
    }
}
