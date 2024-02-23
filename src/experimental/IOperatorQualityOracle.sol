// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

interface IOperatorQualityOracle {
    function operatorQualityScore(address operator) external view returns (uint256);
}