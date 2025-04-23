// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { OperatorSet } from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

struct ECDSAOperatorInfo {
	address pubkey;
	uint96[] stakes;
}

/// @title IECDSAOperatorTableCalculator
interface IECDSAOperatorTableCalculator {
	/**
	 * @notice calculates the operatorInfos for a given operatorSet
	 * @param operatorSet the operatorSet to calculate the operator table for
	 * @return operatorInfos the list of operatorInfos
	 */
	function calculateOperatorTable(OperatorSet calldata operatorSet) 
		external view returns(ECDSAOperatorInfo[] memory operatorInfos);
}