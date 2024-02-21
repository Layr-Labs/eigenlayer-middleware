// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {DeployUtilsLocal} from "../../script/AVSContractsDeploy.s.sol";

contract LocalScriptTest is DeployUtilsLocal, Test {
    function test_AddressFrom() public {
        uint256 nonce  =vm.getNonce(address(this));
        address predicted = _addressFrom(address(this), nonce);
        address actual = _create();
        assertEq(predicted, actual, "addresses didnt match");
    }
    function testFuzz_AddressFrom(uint64 nonce) public {
        nonce = uint64(bound(nonce, 1, type(uint64).max));
        vm.assume(nonce != type(uint64).max);
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

}
