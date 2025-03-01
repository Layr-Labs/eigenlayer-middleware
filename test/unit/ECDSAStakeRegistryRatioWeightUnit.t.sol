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
import {ECDSAStakeRegistryRatioWeight} from
    "../../src/unaudited/examples/ECDSAStakeRegistryRatioWeight.sol";
import {IAVSDirectory} from "../../src/unaudited/ECDSAStakeRegistry.sol";

contract RatioWeightECDSAStakeRegistryTest is ECDSAStakeRegistrySetup {
    /// @notice Event emitted when the weight ratio is updated
    event WeightRatioUpdated(uint256 oldRatio, uint256 newRatio);

    ECDSAStakeRegistryRatioWeight internal ratioWeightRegistry;

    function setUp() public virtual override {
        super.setUp();
        ratioWeightRegistry = new ECDSAStakeRegistryRatioWeight(
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

        uint32[] memory operatorSetIds = new uint32[](2);
        operatorSetIds[0] = 1;
        operatorSetIds[1] = 2;
        IECDSAStakeRegistryTypes.StrategyParams[][] memory strategyParamsArray =
            new IECDSAStakeRegistryTypes.StrategyParams[][](2);

        strategyParamsArray[0] = new IECDSAStakeRegistryTypes.StrategyParams[](2);
        strategyParamsArray[0][0] = IECDSAStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(900)),
            multiplier: 3000
        });
        strategyParamsArray[0][1] = IECDSAStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(901)),
            multiplier: 3000
        });

        strategyParamsArray[1] = new IECDSAStakeRegistryTypes.StrategyParams[](2);
        strategyParamsArray[1][0] = IECDSAStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(902)),
            multiplier: 3000
        });
        strategyParamsArray[1][1] = IECDSAStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(903)),
            multiplier: 3000
        });
        ratioWeightRegistry.initialize(
            address(mockServiceManager), 100, quorum, operatorSetIds, strategyParamsArray
        );
        // Register operator3 and operator4 to M2 quorum
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature;
        vm.prank(operator3);
        ratioWeightRegistry.registerOperatorM2Quorum(operatorSignature, operator3);
        vm.prank(operator4);
        ratioWeightRegistry.registerOperatorM2Quorum(operatorSignature, operator4);
    }

    function test_RevertsWhen_NotOwner_SetWeightRatio() public {
        address notOwner = address(0xBEEF);
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        ratioWeightRegistry.setWeightRatio(5000);
    }

    function test_RevertsWhen_InvalidRatio_SetWeightRatio() public {
        vm.expectRevert(
            abi.encodeWithSelector(ECDSAStakeRegistryRatioWeight.InvalidWeightRatio.selector, 10001)
        );
        ratioWeightRegistry.setWeightRatio(10001);
    }

    function test_When_Owner_SetWeightRatio() public {
        // Test setting ratio to 70% quorum weight, 30% operator set weight
        vm.expectEmit(true, true, true, true);
        emit WeightRatioUpdated(0, 7000);
        ratioWeightRegistry.setWeightRatio(7000);
        assertEq(ratioWeightRegistry.getWeightRatio(), 7000);
    }

    function test_WeightCalculation_WithDifferentRatios() public {
        // Initial weights should be equal since ratio is 0
        uint256 initialWeight = ratioWeightRegistry.getOperatorWeight(operator3);

        // Set ratio to 70% quorum weight, 30% operator set weight
        ratioWeightRegistry.setWeightRatio(7000);
        uint256 quorumWeight = ratioWeightRegistry.getQuorumWeight(operator3);
        uint256 operatorSetWeight = ratioWeightRegistry.getOperatorSetWeight(operator3);
        uint256 expectedWeight = (quorumWeight * 7000 / 10000) + (operatorSetWeight * 3000 / 10000);
        assertEq(ratioWeightRegistry.getOperatorWeight(operator3), expectedWeight);

        // Change ratio to 30% quorum weight, 70% operator set weight
        ratioWeightRegistry.setWeightRatio(3000);

        expectedWeight = (quorumWeight * 3000 / 10000) + (operatorSetWeight * 7000 / 10000);
        assertEq(ratioWeightRegistry.getOperatorWeight(operator3), expectedWeight);
    }

    function test_WeightCalculation_WithEqualRatio() public {
        // Set ratio to 50% quorum weight, 50% operator set weight
        ratioWeightRegistry.setWeightRatio(5000);
        uint256 quorumWeight = ratioWeightRegistry.getQuorumWeight(operator3);
        uint256 operatorSetWeight = ratioWeightRegistry.getOperatorSetWeight(operator3);

        uint256 expectedWeight = (quorumWeight * 5000 / 10000) + (operatorSetWeight * 5000 / 10000);
        assertEq(ratioWeightRegistry.getOperatorWeight(operator3), expectedWeight);
    }
}
