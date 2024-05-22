// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

struct StrategyParams {
    IStrategy strategy; // The strategy contract reference
    uint96 multiplier; // The multiplier applied to the strategy
}

struct Quorum {
    StrategyParams[] strategies; // An array of strategy parameters to define the quorum
}

interface ECDSAStakeRegistryEventsAndErrors {
    /// @notice Emitted when the system registers an operator
    /// @param _operator The address of the registered operator
    /// @param _avs The address of the associated AVS
    event OperatorRegistered(address indexed _operator, address indexed _avs);

    /// @notice Emitted when the system deregisters an operator
    /// @param _operator The address of the deregistered operator
    /// @param _avs The address of the associated AVS
    event OperatorDeregistered(address indexed _operator, address indexed _avs);

    /// @notice Emitted when the system updates the quorum
    /// @param _old The previous quorum configuration
    /// @param _new The new quorum configuration
    event QuorumUpdated(Quorum _old, Quorum _new);

    /// @notice Emitted when the weight to join the operator set updates
    /// @param _old The previous minimum weight
    /// @param _new The new minimumWeight
    event MinimumWeightUpdated(uint256 _old, uint256 _new);

    /// @notice Emitted when the weight required to be an operator changes
    /// @param oldMinimumWeight The previous weight
    /// @param newMinimumWeight The updated weight
    event UpdateMinimumWeight(
        uint256 oldMinimumWeight,
        uint256 newMinimumWeight
    );

    /// @notice Emitted when the system updates an operator's weight
    /// @param _operator The address of the operator updated
    /// @param oldWeight The operator's weight before the update
    /// @param newWeight The operator's weight after the update
    event OperatorWeightUpdated(
        address indexed _operator,
        uint256 oldWeight,
        uint256 newWeight
    );

    /// @notice Emitted when the system updates the total weight
    /// @param oldTotalWeight The total weight before the update
    /// @param newTotalWeight The total weight after the update
    event TotalWeightUpdated(uint256 oldTotalWeight, uint256 newTotalWeight);

    /// @notice Emits when setting a new threshold weight.
    event ThresholdWeightUpdated(uint256 _thresholdWeight);

    /// @notice Emitted when an operator's signing key is updated
    /// @param operator The address of the operator whose signing key was updated
    /// @param updateBlock The block number at which the signing key was updated
    /// @param newSigningKey The operator's signing key after the update
    /// @param oldSigningKey The operator's signing key before the update
    event SigningKeyUpdate(
        address indexed operator,
        uint256 indexed updateBlock,
        address indexed newSigningKey,
        address oldSigningKey
    );
    /// @notice Indicates when the lengths of the signers array and signatures array do not match.
    error LengthMismatch();

    /// @notice Indicates encountering an invalid length for the signers or signatures array.
    error InvalidLength();

    /// @notice Indicates encountering an invalid signature.
    error InvalidSignature();

    /// @notice Thrown when the threshold update is greater than BPS
    error InvalidThreshold();

    /// @notice Thrown when missing operators in an update
    error MustUpdateAllOperators();

    /// @notice Reference blocks must be for blocks that have already been confirmed
    error InvalidReferenceBlock();

    /// @notice Indicates operator weights were out of sync and the signed weight exceed the total
    error InvalidSignedWeight();

    /// @notice Indicates the total signed stake fails to meet the required threshold.
    error InsufficientSignedStake();

    /// @notice Indicates an individual signer's weight fails to meet the required threshold.
    error InsufficientWeight();

    /// @notice Indicates the quorum is invalid
    error InvalidQuorum();

    /// @notice Indicates the system finds a list of items unsorted
    error NotSorted();

    /// @notice Thrown when registering an already registered operator
    error OperatorAlreadyRegistered();

    /// @notice Thrown when de-registering or updating the stake for an unregisted operator
    error OperatorNotRegistered();
}
