// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    IECDSAStakeRegistry,
    ECDSAStakeRegistryStorage,
    IECDSAStakeRegistryTypes
} from "./ECDSAStakeRegistryStorage.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IServiceManager} from "../interfaces/IServiceManager.sol";

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {CheckpointsUpgradeable} from
    "@openzeppelin-upgrades/contracts/utils/CheckpointsUpgradeable.sol";
import {SignatureCheckerUpgradeable} from
    "@openzeppelin-upgrades/contracts/utils/cryptography/SignatureCheckerUpgradeable.sol";
import {IERC1271Upgradeable} from
    "@openzeppelin-upgrades/contracts/interfaces/IERC1271Upgradeable.sol";

/// @title ECDSA Stake Registry
/// @dev THIS CONTRACT IS NOT AUDITED
/// @notice Manages operator registration and quorum updates for an AVS using ECDSA signatures.
contract ECDSAStakeRegistry is
    IERC1271Upgradeable,
    OwnableUpgradeable,
    ECDSAStakeRegistryStorage
{
    using SignatureCheckerUpgradeable for address;
    using CheckpointsUpgradeable for CheckpointsUpgradeable.History;

    /// @dev Constructor to create ECDSAStakeRegistry.
    /// @param _delegationManager Address of the DelegationManager contract that this registry interacts with.
    constructor(
        IDelegationManager _delegationManager
    ) ECDSAStakeRegistryStorage(_delegationManager) {
        // _disableInitializers();
    }

    /// @notice Initializes the contract with the given parameters.
    /// @param _serviceManager The address of the service manager.
    /// @param thresholdWeight The threshold weight in basis points.
    /// @param quorum The quorum struct containing the details of the quorum thresholds.
    function initialize(
        address _serviceManager,
        uint256 thresholdWeight,
        IECDSAStakeRegistryTypes.Quorum memory quorum
    ) external initializer {
        __ECDSAStakeRegistry_init(_serviceManager, thresholdWeight, quorum);
    }

    /// @notice Initializes state for the StakeRegistry
    /// @param _serviceManagerAddr The AVS' ServiceManager contract's address
    function __ECDSAStakeRegistry_init(
        address _serviceManagerAddr,
        uint256 thresholdWeight,
        IECDSAStakeRegistryTypes.Quorum memory quorum
    ) internal onlyInitializing {
        _serviceManager = _serviceManagerAddr;
        _updateStakeThreshold(thresholdWeight);
        _updateQuorumConfig(quorum);
        __Ownable_init();
    }

    /// @inheritdoc IECDSAStakeRegistry
    function registerOperatorWithSignature(
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature,
        address signingKey
    ) external {
        _registerOperatorWithSig(msg.sender, operatorSignature, signingKey);
    }

    /// @inheritdoc IECDSAStakeRegistry
    function deregisterOperator() external {
        _deregisterOperator(msg.sender);
    }

    /// @inheritdoc IECDSAStakeRegistry
    function updateOperatorSigningKey(
        address newSigningKey
    ) external {
        if (!_operatorRegistered[msg.sender]) {
            revert OperatorNotRegistered();
        }
        _updateOperatorSigningKey(msg.sender, newSigningKey);
    }

    /// @inheritdoc IECDSAStakeRegistry
    function updateOperators(
        address[] memory operators
    ) external {
        _updateOperators(operators);
    }

    /// @inheritdoc IECDSAStakeRegistry
    function updateQuorumConfig(
        IECDSAStakeRegistryTypes.Quorum memory quorum,
        address[] memory operators
    ) external onlyOwner {
        _updateQuorumConfig(quorum);
        _updateOperators(operators);
    }

    /// @inheritdoc IECDSAStakeRegistry
    function updateMinimumWeight(
        uint256 newMinimumWeight,
        address[] memory operators
    ) external onlyOwner {
        _updateMinimumWeight(newMinimumWeight);
        _updateOperators(operators);
    }

    /// @inheritdoc IECDSAStakeRegistry
    function updateStakeThreshold(
        uint256 thresholdWeight
    ) external onlyOwner {
        _updateStakeThreshold(thresholdWeight);
    }

    function isValidSignature(
        bytes32 digest,
        bytes memory _signatureData
    ) external view returns (bytes4) {
        (address[] memory operators, bytes[] memory signatures, uint32 referenceBlock) =
            abi.decode(_signatureData, (address[], bytes[], uint32));
        _checkSignatures(digest, operators, signatures, referenceBlock);
        return IERC1271Upgradeable.isValidSignature.selector;
    }

    /// @inheritdoc IECDSAStakeRegistry
    function quorum() external view returns (IECDSAStakeRegistryTypes.Quorum memory) {
        return _quorum;
    }

    /// @inheritdoc IECDSAStakeRegistry
    function getLatestOperatorSigningKey(
        address operator
    ) external view returns (address) {
        return address(uint160(_operatorSigningKeyHistory[operator].latest()));
    }

    /// @inheritdoc IECDSAStakeRegistry
    function getOperatorSigningKeyAtBlock(
        address operator,
        uint256 blockNumber
    ) external view returns (address) {
        return address(uint160(_operatorSigningKeyHistory[operator].getAtBlock(blockNumber)));
    }

    /// @inheritdoc IECDSAStakeRegistry
    function getLastCheckpointOperatorWeight(
        address operator
    ) external view returns (uint256) {
        return _operatorWeightHistory[operator].latest();
    }

    /// @inheritdoc IECDSAStakeRegistry
    function getLastCheckpointTotalWeight() external view returns (uint256) {
        return _totalWeightHistory.latest();
    }

    /// @inheritdoc IECDSAStakeRegistry
    function getLastCheckpointThresholdWeight() external view returns (uint256) {
        return _thresholdWeightHistory.latest();
    }

    /// @inheritdoc IECDSAStakeRegistry
    function getOperatorWeightAtBlock(
        address operator,
        uint32 blockNumber
    ) external view returns (uint256) {
        return _operatorWeightHistory[operator].getAtBlock(blockNumber);
    }

    /// @inheritdoc IECDSAStakeRegistry
    function getLastCheckpointTotalWeightAtBlock(
        uint32 blockNumber
    ) external view returns (uint256) {
        return _totalWeightHistory.getAtBlock(blockNumber);
    }

    /// @inheritdoc IECDSAStakeRegistry
    function getLastCheckpointThresholdWeightAtBlock(
        uint32 blockNumber
    ) external view returns (uint256) {
        return _thresholdWeightHistory.getAtBlock(blockNumber);
    }

    /// @inheritdoc IECDSAStakeRegistry
    function operatorRegistered(
        address operator
    ) external view returns (bool) {
        return _operatorRegistered[operator];
    }

    /// @inheritdoc IECDSAStakeRegistry
    function minimumWeight() external view returns (uint256) {
        return _minimumWeight;
    }

    /// @inheritdoc IECDSAStakeRegistry
    function getOperatorWeight(
        address operator
    ) public view returns (uint256) {
        StrategyParams[] memory strategyParams = _quorum.strategies;
        uint256 weight;
        IStrategy[] memory strategies = new IStrategy[](strategyParams.length);
        for (uint256 i; i < strategyParams.length; i++) {
            strategies[i] = strategyParams[i].strategy;
        }
        uint256[] memory shares = DELEGATION_MANAGER.getOperatorShares(operator, strategies);
        for (uint256 i; i < strategyParams.length; i++) {
            weight += shares[i] * strategyParams[i].multiplier;
        }
        weight = weight / BPS;

        if (weight >= _minimumWeight) {
            return weight;
        } else {
            return 0;
        }
    }

    /// @inheritdoc IECDSAStakeRegistry
    function updateOperatorsForQuorum(
        address[][] memory operatorsPerQuorum,
        bytes memory
    ) external {
        _updateAllOperators(operatorsPerQuorum[0]);
    }

    /// @dev Updates the list of operators if the provided list has the correct number of operators.
    /// Reverts if the provided list of operators does not match the expected total count of operators.
    /// @param operators The list of operator addresses to update.
    function _updateAllOperators(
        address[] memory operators
    ) internal {
        if (operators.length != _totalOperators) {
            revert MustUpdateAllOperators();
        }
        _updateOperators(operators);
    }

    /// @dev Updates the weights for a given list of operator addresses.
    /// When passing an operator that isn't registered, then 0 is added to their history
    /// @param operators An array of addresses for which to update the weights.
    function _updateOperators(
        address[] memory operators
    ) internal {
        int256 delta;
        for (uint256 i; i < operators.length; i++) {
            delta += _updateOperatorWeight(operators[i]);
        }
        _updateTotalWeight(delta);
    }

    /// @dev Updates the stake threshold weight and records the history.
    /// @param thresholdWeight The new threshold weight to set and record in the history.
    function _updateStakeThreshold(
        uint256 thresholdWeight
    ) internal {
        _thresholdWeightHistory.push(thresholdWeight);
        emit ThresholdWeightUpdated(thresholdWeight);
    }

    /// @dev Updates the weight an operator must have to join the operator set
    /// @param newMinimumWeight The new weight an operator must have to join the operator set
    function _updateMinimumWeight(
        uint256 newMinimumWeight
    ) internal {
        uint256 oldMinimumWeight = _minimumWeight;
        _minimumWeight = newMinimumWeight;
        emit MinimumWeightUpdated(oldMinimumWeight, newMinimumWeight);
    }

    /// @notice Updates the quorum configuration
    /// @dev Replaces the current quorum configuration with `newQuorum` if valid.
    /// Reverts with `InvalidQuorum` if the new quorum configuration is not valid.
    /// Emits `QuorumUpdated` event with the old and new quorum configurations.
    /// @param newQuorum The new quorum configuration to set.
    function _updateQuorumConfig(
        IECDSAStakeRegistryTypes.Quorum memory newQuorum
    ) internal {
        if (!_isValidQuorum(newQuorum)) {
            revert InvalidQuorum();
        }
        IECDSAStakeRegistryTypes.Quorum memory oldQuorum = _quorum;
        delete _quorum;
        for (uint256 i; i < newQuorum.strategies.length; i++) {
            _quorum.strategies.push(newQuorum.strategies[i]);
        }
        emit QuorumUpdated(oldQuorum, newQuorum);
    }

    /// @dev Internal function to deregister an operator
    /// @param operator The operator's address to deregister
    function _deregisterOperator(
        address operator
    ) internal {
        if (!_operatorRegistered[operator]) {
            revert OperatorNotRegistered();
        }
        _totalOperators--;
        delete _operatorRegistered[operator];
        int256 delta = _updateOperatorWeight(operator);
        _updateTotalWeight(delta);
        IServiceManager(_serviceManager).deregisterOperatorFromAVS(operator);
        emit OperatorDeregistered(operator, address(_serviceManager));
    }

    /// @dev registers an operator through a provided signature
    /// @param operatorSignature Contains the operator's signature, salt, and expiry
    /// @param signingKey The signing key to add to the operator's history
    function _registerOperatorWithSig(
        address operator,
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature,
        address signingKey
    ) internal virtual {
        if (_operatorRegistered[operator]) {
            revert OperatorAlreadyRegistered();
        }
        _totalOperators++;
        _operatorRegistered[operator] = true;
        int256 delta = _updateOperatorWeight(operator);
        _updateTotalWeight(delta);
        _updateOperatorSigningKey(operator, signingKey);
        IServiceManager(_serviceManager).registerOperatorToAVS(operator, operatorSignature);
        emit OperatorRegistered(operator, _serviceManager);
    }

    /// @dev Internal function to update an operator's signing key
    /// @param operator The address of the operator to update the signing key for
    /// @param newSigningKey The new signing key to set for the operator
    function _updateOperatorSigningKey(address operator, address newSigningKey) internal {
        address oldSigningKey = address(uint160(_operatorSigningKeyHistory[operator].latest()));
        if (newSigningKey == oldSigningKey) {
            return;
        }
        _operatorSigningKeyHistory[operator].push(uint160(newSigningKey));
        emit SigningKeyUpdate(operator, block.number, newSigningKey, oldSigningKey);
    }

    /// @notice Updates the weight of an operator and returns the previous and current weights.
    /// @param operator The address of the operator to update the weight of.
    function _updateOperatorWeight(
        address operator
    ) internal virtual returns (int256) {
        int256 delta;
        uint256 newWeight;
        uint256 oldWeight = _operatorWeightHistory[operator].latest();
        if (!_operatorRegistered[operator]) {
            delta -= int256(oldWeight);
            if (delta == 0) {
                return delta;
            }
            _operatorWeightHistory[operator].push(0);
        } else {
            newWeight = getOperatorWeight(operator);
            delta = int256(newWeight) - int256(oldWeight);
            if (delta == 0) {
                return delta;
            }
            _operatorWeightHistory[operator].push(newWeight);
        }
        emit OperatorWeightUpdated(operator, oldWeight, newWeight);
        return delta;
    }

    /// @dev Internal function to update the total weight of the stake
    /// @param delta The change in stake applied last total weight
    /// @return oldTotalWeight The weight before the update
    /// @return newTotalWeight The updated weight after applying the delta
    function _updateTotalWeight(
        int256 delta
    ) internal returns (uint256 oldTotalWeight, uint256 newTotalWeight) {
        oldTotalWeight = _totalWeightHistory.latest();
        int256 newWeight = int256(oldTotalWeight) + delta;
        newTotalWeight = uint256(newWeight);
        _totalWeightHistory.push(newTotalWeight);
        emit TotalWeightUpdated(oldTotalWeight, newTotalWeight);
    }

    /**
     * @dev Verifies that a specified quorum configuration is valid. A valid quorum has:
     *      1. Weights that sum to exactly 10,000 basis points, ensuring proportional representation.
     *      2. Unique strategies without duplicates to maintain quorum integrity.
     * @param quorum The quorum configuration to be validated.
     * @return bool True if the quorum configuration is valid, otherwise false.
     */
    function _isValidQuorum(
        IECDSAStakeRegistryTypes.Quorum memory quorum
    ) internal pure returns (bool) {
        StrategyParams[] memory strategies = quorum.strategies;
        address lastStrategy;
        address currentStrategy;
        uint256 totalMultiplier;
        for (uint256 i; i < strategies.length; i++) {
            currentStrategy = address(strategies[i].strategy);
            if (lastStrategy >= currentStrategy) revert NotSorted();
            lastStrategy = currentStrategy;
            totalMultiplier += strategies[i].multiplier;
        }
        if (totalMultiplier != BPS) {
            return false;
        } else {
            return true;
        }
    }

    /**
     * @notice Common logic to verify a batch of ECDSA signatures against a hash, using either last stake weight or at a specific block.
     * @param digest The hash of the data the signers endorsed.
     * @param operators A collection of addresses that endorsed the data hash.
     * @param signatures A collection of signatures matching the signers.
     * @param referenceBlock The block number for evaluating stake weight; use max uint32 for latest weight.
     */
    function _checkSignatures(
        bytes32 digest,
        address[] memory operators,
        bytes[] memory signatures,
        uint32 referenceBlock
    ) internal view {
        uint256 signersLength = operators.length;
        address currentOperator;
        address lastOperator;
        address signer;
        uint256 signedWeight;

        _validateSignaturesLength(signersLength, signatures.length);
        for (uint256 i; i < signersLength; i++) {
            currentOperator = operators[i];
            signer = _getOperatorSigningKey(currentOperator, referenceBlock);

            _validateSortedSigners(lastOperator, currentOperator);
            _validateSignature(signer, digest, signatures[i]);

            lastOperator = currentOperator;
            uint256 operatorWeight = _getOperatorWeight(currentOperator, referenceBlock);
            signedWeight += operatorWeight;
        }

        _validateThresholdStake(signedWeight, referenceBlock);
    }

    /// @notice Validates that the number of signers equals the number of signatures, and neither is zero.
    /// @param signersLength The number of signers.
    /// @param signaturesLength The number of signatures.
    function _validateSignaturesLength(
        uint256 signersLength,
        uint256 signaturesLength
    ) internal pure {
        if (signersLength != signaturesLength) {
            revert LengthMismatch();
        }
        if (signersLength == 0) {
            revert InvalidLength();
        }
    }

    /// @notice Ensures that signers are sorted in ascending order by address.
    /// @param lastSigner The address of the last signer.
    /// @param currentSigner The address of the current signer.
    function _validateSortedSigners(address lastSigner, address currentSigner) internal pure {
        if (lastSigner >= currentSigner) {
            revert NotSorted();
        }
    }

    /// @notice Validates a given signature against the signer's address and data hash.
    /// @param signer The address of the signer to validate.
    /// @param digest The hash of the data that is signed.
    /// @param signature The signature to validate.
    function _validateSignature(
        address signer,
        bytes32 digest,
        bytes memory signature
    ) internal view {
        if (!signer.isValidSignatureNow(digest, signature)) {
            revert InvalidSignature();
        }
    }

    /// @notice Retrieves the operator weight for a signer, either at the last checkpoint or a specified block.
    /// @param operator The operator to query their signing key history for
    /// @param referenceBlock The block number to query the operator's weight at, or the maximum uint32 value for the last checkpoint.
    /// @return The weight of the operator.
    function _getOperatorSigningKey(
        address operator,
        uint32 referenceBlock
    ) internal view returns (address) {
        if (referenceBlock >= block.number) {
            revert InvalidReferenceBlock();
        }
        return address(uint160(_operatorSigningKeyHistory[operator].getAtBlock(referenceBlock)));
    }

    /// @notice Retrieves the operator weight for a signer, either at the last checkpoint or a specified block.
    /// @param signer The address of the signer whose weight is returned.
    /// @param referenceBlock The block number to query the operator's weight at, or the maximum uint32 value for the last checkpoint.
    /// @return The weight of the operator.
    function _getOperatorWeight(
        address signer,
        uint32 referenceBlock
    ) internal view returns (uint256) {
        if (referenceBlock >= block.number) {
            revert InvalidReferenceBlock();
        }
        return _operatorWeightHistory[signer].getAtBlock(referenceBlock);
    }

    /// @notice Retrieve the total stake weight at a specific block or the latest if not specified.
    /// @dev If the `referenceBlock` is the maximum value for uint32, the latest total weight is returned.
    /// @param referenceBlock The block number to retrieve the total stake weight from.
    /// @return The total stake weight at the given block or the latest if the given block is the max uint32 value.
    function _getTotalWeight(
        uint32 referenceBlock
    ) internal view returns (uint256) {
        if (referenceBlock >= block.number) {
            revert InvalidReferenceBlock();
        }
        return _totalWeightHistory.getAtBlock(referenceBlock);
    }

    /// @notice Retrieves the threshold stake for a given reference block.
    /// @param referenceBlock The block number to query the threshold stake for.
    /// If set to the maximum uint32 value, it retrieves the latest threshold stake.
    /// @return The threshold stake in basis points for the reference block.
    function _getThresholdStake(
        uint32 referenceBlock
    ) internal view returns (uint256) {
        if (referenceBlock >= block.number) {
            revert InvalidReferenceBlock();
        }
        return _thresholdWeightHistory.getAtBlock(referenceBlock);
    }

    /// @notice Validates that the cumulative stake of signed messages meets or exceeds the required threshold.
    /// @param signedWeight The cumulative weight of the signers that have signed the message.
    /// @param referenceBlock The block number to verify the stake threshold for
    function _validateThresholdStake(uint256 signedWeight, uint32 referenceBlock) internal view {
        uint256 totalWeight = _getTotalWeight(referenceBlock);
        if (signedWeight > totalWeight) {
            revert InvalidSignedWeight();
        }
        uint256 thresholdStake = _getThresholdStake(referenceBlock);
        if (thresholdStake > signedWeight) {
            revert InsufficientSignedStake();
        }
    }
}
