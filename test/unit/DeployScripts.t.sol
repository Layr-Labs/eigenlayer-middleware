// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {DeployUtilsLocal} from "../../script/AVSContractsDeploy.s.sol";
import {TimeMachine} from "../integration/TimeMachine.t.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import "eigenlayer-contracts/src/contracts/core/StrategyManager.sol";
import "eigenlayer-contracts/src/contracts/core/Slasher.sol";

contract LocalScriptTest is DeployUtilsLocal, Test, TimeMachine {
    function setUp() public {
        unpauser = makeAddr("unpauser");
        address pauser1 = makeAddr("pauser 2");
        address pauser2 = makeAddr("pauser 2");
        pausers.push(pauser1);
        pausers.push(pauser2);
    }
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
        uint256 initialState = createSnapshot();
        proxyAdmin = ProxyAdmin(_deployProxyAdmin());
        /// TODO: deploy each separately
        /// TODO: Need to precompute addresses since there is no validation in the constructors
        pauserRegistry = PauserRegistry(_deployPauserRegistry(pausers, unpauser));

        console.log(vm.getNonce(address(this)));
        strategyManager = StrategyManager(_deployStrategyManager(0));
        console.log(vm.getNonce(address(this)));

        slasher = Slasher(_deploySlasher());
        console.log(vm.getNonce(address(this)));
        /// TODO: verify state
        warpToLast();

        vm.revertTo(initialState);

        // _deployCore();

        /// TODO: Verify deployment state
    }
}
