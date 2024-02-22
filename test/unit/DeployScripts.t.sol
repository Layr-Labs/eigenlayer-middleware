// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {DeployUtilsLocal} from "../../script/AVSContractsDeploy.s.sol";
import {TimeMachine} from "../integration/TimeMachine.t.sol";

contract LocalScriptTest is DeployUtilsLocal, Test, TimeMachine {
    function test_AddressFrom() public {
        uint256 nonce = vm.getNonce(address(this));
        address predicted = _addressFrom(address(this), nonce);
        address actual = _create();
        assertEq(predicted, actual, "addresses didnt match");
    }
    function testFuzz_AddressFrom(uint64 nonce) public {
        vm.assume(nonce != 0 && nonce != type(uint64).max);
        vm.setNonce(address(this), nonce);
        console.log(nonce);
        address predicted = _addressFrom(address(this), nonce);
        address actual = _create();
        assertEq(predicted, actual, "addresses didnt match");
    }

    function _create() internal returns (address) {
        address addr;
        assembly {
            addr := create(0, 0, 0)
        }
        return addr;
    }

    function test_CoreLocal() public {
        createSnapshot();
        /// TODO: deploy each separately

        /// TODO: verify state
        warpToLast();

        _deployCore();

        /// TODO: Verify deployment state
    }
}
