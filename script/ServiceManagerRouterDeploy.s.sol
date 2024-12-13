// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ServiceManagerRouter} from "../src/ServiceManagerRouter.sol";
import "forge-std/Script.sol";

contract ServiceManagerRouterDeploy is Script {
    function run() external {
        vm.startBroadcast();

        ServiceManagerRouter router = new ServiceManagerRouter();

        vm.stopBroadcast();
    }
}
