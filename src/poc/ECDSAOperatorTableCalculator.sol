// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    IAllocationManager,
    OperatorSet,
    IAllocationManagerTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

import {
    IStrategyManager,
    IStrategy
} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";

import "./interfaces/IECDSAOperatorTableCalculator.sol";

contract ECDSAOperatorTableCalculator is IECDSAOperatorTableCalculator {

	/// @notice The allocation manager core contract.
    IAllocationManager public immutable allocationManager;

    constructor(address _allocationManager) {
    	allocationManager = IAllocationManager(_allocationManager);
    }

    function calculateOperatorTable(OperatorSet calldata operatorSet) external view returns(ECDSAOperatorInfo[] memory operatorInfos) {
    	IStrategy[] memory strategies = allocationManager.getStrategiesInOperatorSet(operatorSet);
    	address[] memory operators = allocationManager.getMembers(operatorSet);
    	uint256[][] memory slashableStake = allocationManager.getMinimumSlashableStake(operatorSet, operators, strategies, uint32(block.number));
    	operatorInfos = new ECDSAOperatorInfo[](operators.length);
       	for (uint i = 0; i < operators.length; i++) {
       		uint96[] memory stakes = new uint96[](strategies.length);
    		for (uint j = 0; j < strategies.length; j++) {
    			stakes[j] = uint96(slashableStake[i][j]);
    		}
    		operatorInfos[i] = ECDSAOperatorInfo(operators[i], stakes);
    	}
    	return operatorInfos;
    }
}