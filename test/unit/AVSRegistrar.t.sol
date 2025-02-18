// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MockAVSDeployer} from "../utils/MockAVSDeployer.sol";
import {BN254} from "../../src/libraries/BN254.sol";
import {IRegistryCoordinator} from "../../src/interfaces/IRegistryCoordinator.sol";
import {IStakeRegistry} from "../../src/interfaces/IStakeRegistry.sol";
import {BitmapUtils} from "../../src/libraries/BitmapUtils.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAllocationManagerTypes} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {AVSRegistrarMock} from "../mocks/AVSRegistrarMock.sol";
import {console2 as console} from "forge-std/Test.sol";

contract AVSRegistrarTest is MockAVSDeployer {
    using BN254 for BN254.G1Point;

    AVSRegistrarMock public avsRegistrarMock;
    address internal operator = address(420);

    function setUp() public virtual {
        _deployMockEigenLayerAndAVS();
        vm.prank(address(serviceManager));
        allocationManager.updateAVSMetadataURI(address(serviceManager), "test-avs-metadata");
        avsRegistrarMock = new AVSRegistrarMock();
    }

    function testSetAVSRegistrar() public {
        vm.prank(address(serviceManager));
        allocationManager.setAVSRegistrar(
            address(serviceManager), IAVSRegistrar(address(avsRegistrarMock))
        );
        assertEq(
            address(allocationManager.getAVSRegistrar(address(serviceManager))),
            address(avsRegistrarMock)
        );
    }

    function testRegisterOperator() public {
        // Set up AVS registrar
        vm.prank(address(serviceManager));
        allocationManager.setAVSRegistrar(
            address(serviceManager), IAVSRegistrar(address(avsRegistrarMock))
        );

        // Create operator set
        uint32 operatorSetId = 1;
        IAllocationManagerTypes.CreateSetParams[] memory createSetParams =
            new IAllocationManagerTypes.CreateSetParams[](1);
        createSetParams[0] = IAllocationManagerTypes.CreateSetParams({
            operatorSetId: operatorSetId,
            strategies: new IStrategy[](0)
        });

        // Create operator set
        vm.prank(address(serviceManager));
        allocationManager.createOperatorSets(address(serviceManager), createSetParams);

        // Set up registration params
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = operatorSetId;
        bytes memory emptyBytes;

        delegationMock.setIsOperator(operator, true);

        // Register operator
        vm.prank(operator);
        allocationManager.registerForOperatorSets(
            address(operator),
            IAllocationManagerTypes.RegisterParams(
                address(serviceManager), operatorSetIds, emptyBytes
            )
        );
    }

    function testRegisterOperator_RevertsIfNotOperator() public {
        vm.prank(address(serviceManager));
        allocationManager.setAVSRegistrar(
            address(serviceManager), IAVSRegistrar(address(avsRegistrarMock))
        );

        // Create operator set
        uint32 operatorSetId = 1;
        IAllocationManagerTypes.CreateSetParams[] memory createSetParams =
            new IAllocationManagerTypes.CreateSetParams[](1);
        createSetParams[0] = IAllocationManagerTypes.CreateSetParams({
            operatorSetId: operatorSetId,
            strategies: new IStrategy[](0)
        });

        // Create operator set
        vm.prank(address(serviceManager));
        allocationManager.createOperatorSets(address(serviceManager), createSetParams);

        // Set up registration params
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = operatorSetId;
        bytes memory emptyBytes;

        delegationMock.setIsOperator(operator, false);

        // Register operator
        vm.prank(operator);

        vm.expectRevert();
        allocationManager.registerForOperatorSets(
            address(operator),
            IAllocationManagerTypes.RegisterParams(
                address(serviceManager), operatorSetIds, emptyBytes
            )
        );
    }

    function testAllocationManagerDeployed() public {
        assertTrue(address(allocationManager) != address(0), "AllocationManager not deployed");
        assertTrue(
            address(allocationManagerImplementation) != address(0),
            "AllocationManager implementation not deployed"
        );
    }
}
