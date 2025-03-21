// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./IntegrationDeployerLegacy.t.sol";

contract LegacyIntegrationTest is IntegrationDeployerLegacy {
    function setUp() public override {
        super.setUp();
    }

    function test_Setup() public {
        // Simple test to verify that the setup was successful
        assertEq(address(registryCoordinator) != address(0), true);
        assertEq(address(stakeRegistry) != address(0), true);
        assertEq(address(blsApkRegistry) != address(0), true);
        assertEq(address(indexRegistry) != address(0), true);
    }
}
