// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

/**
 * @notice Minimal interface for an oracle contract that provides Operator Quality Scores.
 * These scores may represent any metric, which could include factor(s) such as:
 * - contributions to decentralization,
 * - observed performance (on- or off-chain),
 * - off-chain commitments,
 * - "trustability" broadly, or
 * - other holistic evaluations
 */
interface IOperatorQualityOracle {
    function operatorQualityScore(address operator) external view returns (uint256);
}