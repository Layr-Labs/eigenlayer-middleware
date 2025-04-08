// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./IECDSATypes.sol";

/**
 * @title IECDSAOperatorTableCalculator
 * @notice Interface for calculating operator tables for ECDSA signature verification
 * @dev This interface allows AVSs to customize how operator tables are generated
 *      while maintaining compatibility with the verification stack
 */
interface IECDSAOperatorTableCalculator {
    /**
     * @notice Calculates the operator information for a given operator set
     * @param operatorSet The operator set to calculate the table for
     * @return operatorInfos Array of operator information with their public keys and weights
     * @dev The returned array should be sorted in ascending order by public key
     *      to enable efficient binary search during verification
     */
    function calculateOperatorTable(IECDSATypes.OperatorSet calldata operatorSet) 
        external view returns(IECDSATypes.ECDSAOperatorInfo[] memory operatorInfos);
} 