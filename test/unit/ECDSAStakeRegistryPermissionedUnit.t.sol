// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

import {
    IECDSAStakeRegistry,
    IECDSAStakeRegistryTypes,
    IECDSAStakeRegistryErrors
} from "../../src/interfaces/IECDSAStakeRegistry.sol";
import {ECDSAStakeRegistrySetup} from "./ECDSAStakeRegistryUnit.t.sol";
import {ECDSAStakeRegistryPermissioned} from
    "../../src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol";
import {IAVSDirectory} from "../../src/unaudited/ECDSAStakeRegistry.sol";

contract PermissionedECDSAStakeRegistryTest is ECDSAStakeRegistrySetup {
    ECDSAStakeRegistryPermissioned internal permissionedRegistry;
    address internal operator6 = makeAddr("operator6");
    address internal operator7 = makeAddr("operator7");

    function setUp() public virtual override {
        super.setUp();
        permissionedRegistry = new ECDSAStakeRegistryPermissioned(
            IDelegationManager(address(mockDelegationManager)),
            IAllocationManager(address(mockAllocationManager)),
            mockAVSRegistrarAddr,
            IAVSDirectory(address(mockAVSDirectory))
        );

        IStrategy mockStrategy = IStrategy(address(0x1234));
        IECDSAStakeRegistryTypes.Quorum memory quorum = IECDSAStakeRegistryTypes.Quorum({
            strategies: new IECDSAStakeRegistryTypes.StrategyParams[](1)
        });
        quorum.strategies[0] =
            IECDSAStakeRegistryTypes.StrategyParams({strategy: mockStrategy, multiplier: 10000});

        // Create operator set IDs and strategy params
        uint32[] memory operatorSetIds = new uint32[](2);
        operatorSetIds[0] = 1;
        operatorSetIds[1] = 2;
        IECDSAStakeRegistryTypes.StrategyParams[][] memory strategyParamsArray =
            new IECDSAStakeRegistryTypes.StrategyParams[][](2);

        // Strategy params for first operator set
        strategyParamsArray[0] = new IECDSAStakeRegistryTypes.StrategyParams[](2);
        strategyParamsArray[0][0] = IECDSAStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(900)), // Lower address
            multiplier: 3000
        });
        strategyParamsArray[0][1] = IECDSAStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(901)), // Higher address
            multiplier: 3000
        });

        // Strategy params for second operator set
        strategyParamsArray[1] = new IECDSAStakeRegistryTypes.StrategyParams[](2);
        strategyParamsArray[1][0] = IECDSAStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(902)), // Lower address
            multiplier: 3000
        });
        strategyParamsArray[1][1] = IECDSAStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(903)), // Higher address
            multiplier: 3000
        });

        permissionedRegistry.initialize(
            address(mockServiceManager), 100, quorum, operatorSetIds, strategyParamsArray
        );

        permissionedRegistry.permitOperator(operator6);
        permissionedRegistry.permitOperator(operator7);

        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature;

        vm.prank(operator6);
        permissionedRegistry.registerOperatorM2Quorum(operatorSignature, operator6);

        vm.prank(operator7);
        permissionedRegistry.registerOperatorM2Quorum(operatorSignature, operator7);

        vm.roll(block.number + 1);
    }

    function test_RevertsWhen_NotOwner_PermitOperator() public {
        address notOwner = address(0xBEEF);
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        permissionedRegistry.permitOperator(operator1);
    }

    function test_When_Owner_PermitOperator() public {
        address operator8 = address(0xBEEF);
        permissionedRegistry.permitOperator(operator8);
    }

    function test_RevertsWhen_NotOwner_RevokeOperator() public {
        address notOwner = address(0xBEEF);
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        permissionedRegistry.revokeOperator(operator1);
    }

    function test_When_NotOperator_RevokeOperator() public {
        address notOperator = address(0xBEEF);
        permissionedRegistry.permitOperator(notOperator);

        permissionedRegistry.revokeOperator(notOperator);
    }

    function test_When_Owner_RevokeOperator() public {
        permissionedRegistry.revokeOperator(operator6);
    }

    function test_RevertsWhen_NotOwner_EjectOperator() public {
        address notOwner = address(0xBEEF);
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        permissionedRegistry.ejectOperator(operator6);
    }

    function test_RevertsWhen_NotOperator_EjectOperator() public {
        address notOperator = address(0xBEEF);
        vm.expectRevert();
        permissionedRegistry.ejectOperator(notOperator);
    }

    function test_When_Owner_EjectOperator() public {
        permissionedRegistry.ejectOperator(operator6);
    }

    function test_RevertsWhen_NotAllowlisted_RegisterOperatorM2Quorum() public {
        address operator8 = address(0xBEEF);

        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature;
        vm.expectRevert(
            abi.encodeWithSelector(ECDSAStakeRegistryPermissioned.OperatorNotAllowlisted.selector)
        );
        vm.prank(operator8);
        permissionedRegistry.registerOperatorM2Quorum(operatorSignature, operator8);
    }

    function test_WhenAllowlisted_RegisterOperatorM2Quorum() public {
        address operator8 = address(0xBEEF);
        permissionedRegistry.permitOperator(operator8);
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature;
        vm.prank(operator8);
        permissionedRegistry.registerOperatorM2Quorum(operatorSignature, operator8);
    }

    function test_DeregisterOperatorM2Quorum() public {
        address operator8 = address(0xBEEF);
        permissionedRegistry.permitOperator(operator8);
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature;
        vm.prank(operator8);
        permissionedRegistry.registerOperatorM2Quorum(operatorSignature, operator8);

        vm.prank(operator8);
        permissionedRegistry.deregisterOperatorM2Quorum();
    }
}
