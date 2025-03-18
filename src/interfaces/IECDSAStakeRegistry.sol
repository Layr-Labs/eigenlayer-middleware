// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC1271Upgradeable} from
    "@openzeppelin-upgrades/contracts/interfaces/IERC1271Upgradeable.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

// TODO: many of these errors do not have test coverage.

interface IECDSAStakeRegistryErrors {
    /// @notice Thrown when the lengths of the signers array and signatures array do not match.
    error LengthMismatch();
    /// @notice Thrown when encountering an invalid length for the signers or signatures array.
    error InvalidLength();
    /// @notice Thrown when encountering an invalid signature.
    error InvalidSignature();
    /// @notice Thrown when the threshold update is greater than BPS.
    error InvalidThreshold();
    /// @notice Thrown when missing operators in an update.
    error MustUpdateAllOperators();
    /// @notice Thrown when reference blocks must be for blocks that have already been confirmed.
    error InvalidReferenceBlock();
    /// @notice Thrown when operator weights were out of sync and the signed weight exceed the total.
    error InvalidSignedWeight();
    /// @notice Thrown when the total signed stake fails to meet the required threshold.
    error InsufficientSignedStake();
    /// @notice Thrown when an individual signer's weight fails to meet the required threshold.
    error InsufficientWeight();
    /// @notice Thrown when the quorum is invalid.
    error InvalidQuorum();
    /// @notice Thrown when the system finds a list of items unsorted.
    error NotSorted();
    /// @notice Thrown when registering an already registered operator.
    error OperatorAlreadyRegistered();
    /// @notice Thrown when de-registering or updating the stake for an unregisted operator.
    error OperatorNotRegistered();
}

interface IECDSAStakeRegistryTypes {
    /// @notice Parameters for a strategy and its weight multiplier.
    /// @param strategy The strategy contract reference.
    /// @param multiplier The multiplier applied to the strategy.
    struct StrategyParams {
        IStrategy strategy;
        uint96 multiplier;
    }

    /// @notice Configuration for a quorum's strategies.
    /// @param strategies An array of strategy parameters defining the quorum.
    struct Quorum {
        StrategyParams[] strategies;
    }
}

interface IECDSAStakeRegistryEvents is IECDSAStakeRegistryTypes {
    /*
     * @notice Emitted when the system registers an operator.
     * @param operator The address of the registered operator.
     * @param avs The address of the associated AVS.
     */
    event OperatorRegistered(address indexed operator, address indexed avs);

    /*
     * @notice Emitted when the system deregisters an operator.
     * @param operator The address of the deregistered operator.
     * @param avs The address of the associated AVS.
     */
    event OperatorDeregistered(address indexed operator, address indexed avs);

    /*
     * @notice Emitted when the system updates the quorum.
     * @param previous The previous quorum configuration.
     * @param current The new quorum configuration.
     */
    event QuorumUpdated(Quorum previous, Quorum current);

    /*
     * @notice Emitted when the weight to join the operator set updates.
     * @param previous The previous minimum weight.
     * @param current The new minimumWeight.
     */
    event MinimumWeightUpdated(uint256 previous, uint256 current);

    /*
     * @notice Emitted when the weight required to be an operator changes.
     * @param oldMinimumWeight The previous weight.
     * @param newMinimumWeight The updated weight.
     */
    event UpdateMinimumWeight(uint256 oldMinimumWeight, uint256 newMinimumWeight);

    /*
     * @notice Emitted when the system updates an operator's weight.
     * @param operator The address of the operator updated.
     * @param oldWeight The operator's weight before the update.
     * @param newWeight The operator's weight after the update.
     */
    event OperatorWeightUpdated(address indexed operator, uint256 oldWeight, uint256 newWeight);

    /*
     * @notice Emitted when the system updates the total weight.
     * @param oldTotalWeight The total weight before the update.
     * @param newTotalWeight The total weight after the update.
     */
    event TotalWeightUpdated(uint256 oldTotalWeight, uint256 newTotalWeight);

    /*
     * @notice Emits when setting a new threshold weight.
     */
    event ThresholdWeightUpdated(uint256 thresholdWeight);

    /*
     * @notice Emitted when an operator's signing key is updated.
     * @param operator The address of the operator whose signing key was updated.
     * @param updateBlock The block number at which the signing key was updated.
     * @param newSigningKey The operator's signing key after the update.
     * @param oldSigningKey The operator's signing key before the update.
     */
    event SigningKeyUpdate(
        address indexed operator,
        uint256 indexed updateBlock,
        address indexed newSigningKey,
        address oldSigningKey
    );
}

interface IECDSAStakeRegistry is
    IECDSAStakeRegistryErrors,
    IECDSAStakeRegistryEvents,
    IERC1271Upgradeable
{
    /* ACTIONS */

    /*
     * @notice Registers a new operator using a provided operators signature and signing key.
     * @param operatorSignature Contains the operator's signature, salt, and expiry.
     * @param signingKey The signing key to add to the operator's history.
     */
    function registerOperatorWithSignature(
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature,
        address signingKey
    ) external;

    /*
     * @notice Deregisters an existing operator.
     */
    function deregisterOperator() external;

    /*
     * @notice Updates the signing key for an operator.
     * @param newSigningKey The new signing key to set for the operator.
     * @dev Only callable by the operator themselves.
     */
    function updateOperatorSigningKey(
        address newSigningKey
    ) external;

    /*
     * @notice Updates the StakeRegistry's view of operators' stakes.
     * @param operators A list of operator addresses to update.
     * @dev Queries stakes from the Eigenlayer core DelegationManager contract.
     */
    function updateOperators(
        address[] memory operators
    ) external;

    /*
     * @notice Updates the quorum configuration and the set of operators.
     * @param quorum The new quorum configuration, including strategies and their new weights.
     * @param operators The list of operator addresses to update stakes for.
     */
    function updateQuorumConfig(
        IECDSAStakeRegistryTypes.Quorum memory quorum,
        address[] memory operators
    ) external;

    /*
     * @notice Updates the weight an operator must have to join the operator set.
     * @param newMinimumWeight The new weight an operator must have to join the operator set.
     * @param operators The list of operators to update after changing the minimum weight.
     */
    function updateMinimumWeight(uint256 newMinimumWeight, address[] memory operators) external;

    /*
     * @notice Sets a new cumulative threshold weight for message validation.
     * @param thresholdWeight The updated threshold weight required to validate a message.
     */
    function updateStakeThreshold(
        uint256 thresholdWeight
    ) external;

    /* VIEW */

    /*
     * @notice Retrieves the current stake quorum details.
     * @return The current quorum of strategies and weights.
     */
    function quorum() external view returns (IECDSAStakeRegistryTypes.Quorum memory);

    /*
     * @notice Retrieves the latest signing key for a given operator.
     * @param operator The address of the operator.
     * @return The latest signing key of the operator.
     */
    function getLatestOperatorSigningKey(
        address operator
    ) external view returns (address);

    /*
     * @notice Retrieves the signing key for an operator at a specific block.
     * @param operator The address of the operator.
     * @param blockNumber The block number to query at.
     * @return The signing key of the operator at the given block.
     */
    function getOperatorSigningKeyAtBlock(
        address operator,
        uint256 blockNumber
    ) external view returns (address);

    /*
     * @notice Retrieves the last recorded weight for a given operator.
     * @param operator The address of the operator.
     * @return The latest weight of the operator.
     */
    function getLastCheckpointOperatorWeight(
        address operator
    ) external view returns (uint256);

    /*
     * @notice Retrieves the last recorded total weight across all operators.
     * @return The latest total weight.
     */
    function getLastCheckpointTotalWeight() external view returns (uint256);

    /*
     * @notice Retrieves the last recorded threshold weight.
     * @return The latest threshold weight.
     */
    function getLastCheckpointThresholdWeight() external view returns (uint256);

    /*
     * @notice Returns whether an operator is currently registered.
     * @param operator The operator address to check.
     * @return Whether the operator is registered.
     */
    function operatorRegistered(
        address operator
    ) external view returns (bool);

    /*
     * @notice Returns the minimum weight required for operator participation.
     * @return The minimum weight threshold.
     */
    function minimumWeight() external view returns (uint256);

    /*
     * @notice Retrieves the operator's weight at a specific block number.
     * @param operator The address of the operator.
     * @param blockNumber The block number to query at.
     * @return The weight of the operator at the given block.
     */
    function getOperatorWeightAtBlock(
        address operator,
        uint32 blockNumber
    ) external view returns (uint256);

    /*
     * @notice Retrieves the operator's weight.
     * @param operator The address of the operator.
     * @return The current weight of the operator.
     */
    function getOperatorWeight(
        address operator
    ) external view returns (uint256);

    /*
     * @notice Updates operators for a specific quorum.
     * @param operatorsPerQuorum Array of operator addresses per quorum.
     * @param data Additional data (unused but kept for interface compatibility).
     */
    function updateOperatorsForQuorum(
        address[][] memory operatorsPerQuorum,
        bytes memory data
    ) external;

    /*
     * @notice Retrieves the total weight at a specific block number.
     * @param blockNumber The block number to query at.
     * @return The total weight at the given block.
     */
    function getLastCheckpointTotalWeightAtBlock(
        uint32 blockNumber
    ) external view returns (uint256);

    /*
     * @notice Retrieves the threshold weight at a specific block number.
     * @param blockNumber The block number to query at.
     * @return The threshold weight at the given block.
     */
    function getLastCheckpointThresholdWeightAtBlock(
        uint32 blockNumber
    ) external view returns (uint256);
}
