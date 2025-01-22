// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ServiceManagerRouter} from "../../src/ServiceManagerRouter.sol";
import "../utils/MockAVSDeployer.sol";

contract ServiceManagerRouter_UnitTests is MockAVSDeployer {
    ServiceManagerRouter public router;
    ServiceManagerMock public dummyServiceManager;
    address eoa = address(0xfedbad);
    address badReturn = address(0x000000000000000000000000000000000000dEaD);

    function setUp() public virtual {
        _deployMockEigenLayerAndAVS();
        router = new ServiceManagerRouter();

        // Deploy dummy serviceManager
        dummyServiceManager = new ServiceManagerMock(
            avsDirectory,
            rewardsCoordinatorImplementation,
            registryCoordinatorImplementation,
            stakeRegistryImplementation,
            permissionControllerMock,
            allocationManagerMock
        );

        _registerOperatorWithCoordinator(defaultOperator, MAX_QUORUM_BITMAP, defaultPubKey);
    }

    function test_getRestakeableStrategies_noStrats() public {
        address[] memory strategies = router.getRestakeableStrategies(address(dummyServiceManager));
        assertEq(strategies.length, 0);
    }

    function test_getRestakeableStrategies_multipleStrats() public {
        address[] memory strategies = router.getRestakeableStrategies(address(serviceManager));
        assertEq(strategies.length, 192);
    }

    function test_getRestakeableStrategies_badImplementation() public {
        address[] memory strategies = router.getRestakeableStrategies(address(emptyContract));
        assertEq(strategies.length, 1);
        assertEq(strategies[0], badReturn);
    }

    function test_getRestakeableStrategies_eoa() public {
        address[] memory strategies = router.getRestakeableStrategies(eoa);
        assertEq(strategies.length, 1);
        assertEq(strategies[0], badReturn);
    }

    function test_getOperatorRestakedStrategies_noStrats() public {
        address[] memory strategies =
            router.getOperatorRestakedStrategies(address(dummyServiceManager), defaultOperator);
        assertEq(strategies.length, 0);
    }

    function test_getOperatorRestakedStrategies_multipleStrats() public {
        address[] memory strategies =
            router.getOperatorRestakedStrategies(address(serviceManager), defaultOperator);
        assertEq(strategies.length, 192);
    }

    function test_getOperatorRestakedStrategies_badImplementation() public {
        address[] memory strategies =
            router.getOperatorRestakedStrategies(address(emptyContract), defaultOperator);
        assertEq(strategies.length, 1);
        assertEq(strategies[0], badReturn);
    }

    function test_getOperatorRestakedStrategies_eoa() public {
        address[] memory strategies = router.getOperatorRestakedStrategies(eoa, defaultOperator);
        assertEq(strategies.length, 1);
        assertEq(strategies[0], badReturn);
    }
}
