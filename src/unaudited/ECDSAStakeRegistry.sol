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
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IServiceManager} from "../interfaces/IServiceManager.sol";

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {CheckpointsUpgradeable} from
    "@openzeppelin-upgrades/contracts/utils/CheckpointsUpgradeable.sol";
import {SignatureCheckerUpgradeable} from
    "@openzeppelin-upgrades/contracts/utils/cryptography/SignatureCheckerUpgradeable.sol";
import {IERC1271Upgradeable} from
    "@openzeppelin-upgrades/contracts/interfaces/IERC1271Upgradeable.sol";
import {
    IAVSDirectory,
    IAVSDirectoryTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

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
        IDelegationManager _delegationManager,
        IAllocationManager _allocationManager,
        address _avsRegistrar,
        IAVSDirectory _avsDirectory
    )
        ECDSAStakeRegistryStorage(_delegationManager, _allocationManager, _avsRegistrar, _avsDirectory)
    {
        // _disableInitializers();
    }

    /// @notice Modifier to ensure the caller is the AVS Registrar.
    modifier onlyAVSRegistrar() {
        if (msg.sender != address(avsRegistrar)) {
            revert InvalidSender();
        }
        _;
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

    function disableM2QuorumRegistration() external onlyOwner {
        if (isM2QuorumRegistrationDisabled) {
            revert M2QuorumRegistrationIsDisabled();
        }

        isM2QuorumRegistrationDisabled = true;
        emit M2QuorumRegistrationDisabled();
    }

    /// @inheritdoc IECDSAStakeRegistry
    function registerOperatorM2Quorum(
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature,
        address signingKey
    ) external {
        if (isM2QuorumRegistrationDisabled) {
            revert M2QuorumRegistrationIsDisabled();
        }
        if (operatorRegisteredOnAVSDirectory(msg.sender)) {
            revert OperatorAlreadyRegistered();
        }
        _registerOperatorM2Quorum(msg.sender, operatorSignature, signingKey);
    }

    /// @inheritdoc IECDSAStakeRegistry
    function deregisterOperatorM2Quorum() external {
        if (!operatorRegisteredOnAVSDirectory(msg.sender)) {
            revert OperatorNotRegistered();
        }

        _deregisterOperatorM2Quorum(msg.sender);
    }

    function onOperatorSetRegistered(
        address operator,
        address signingKey
    ) external onlyAVSRegistrar {
        // Update operator weight
        _updateOperatorWeight(operator);

        // Update signing key and p2p key
        _updateOperatorSigningKey(operator, signingKey);

        if (!operatorRegisteredOnAVSDirectory(operator)) {
            emit OperatorRegistered(operator, _serviceManager);
        }
    }

    function onOperatorSetDeregistered(
        address operator
    ) external onlyAVSRegistrar {
        // Update weights
        _updateOperatorWeight(operator);

        // Emit event
        if (!operatorRegisteredOnAVSDirectory(operator)) {
            emit OperatorDeregistered(operator, _serviceManager);
        }
    }

    /// @inheritdoc IECDSAStakeRegistry
    function updateOperatorSigningKey(
        address newSigningKey
    ) external {
        if (!operatorRegistered(msg.sender)) {
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

    /// @notice Sets the current operator set ids
    /// @param _ids The ids of the operator sets to set
    function setCurrentOperatorSetIds(
        uint32[] calldata _ids
    ) external onlyOwner {
        if (_ids.length == 0 || _ids.length > 10) {
            revert InvalidOperatorSetIdsLength();
        }
        currentOperatorSetIds = _ids;
    }

    /// @notice Sets the allocation manager
    /// @param _allocationManager The allocation manager to set
    function setAllocationManager(
        IAllocationManager _allocationManager
    ) external onlyOwner {
        allocationManager = _allocationManager;
    }

    /// @notice Sets the AVS Registrar
    /// @param _avsRegistrar The AVS Registrar to set
    function setAVSRegistrar(
        address _avsRegistrar
    ) external onlyOwner {
        avsRegistrar = _avsRegistrar;
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

    /// @notice Gets the current operator set ids
    /// @return The current operator set ids
    function getCurrentOperatorSetIds() external view returns (uint32[] memory) {
        return currentOperatorSetIds;
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
    function minimumWeight() external view returns (uint256) {
        return _minimumWeight;
    }

    /// @notice Calculates an operator's current weight based on their delegated stake
    /// @param _operator Address of the operator to calculate weight for
    /// @return Current weight of the operator (0 if below minimum threshold)
    /// @dev Queries mainnet delegation manager for current shares
    function getOperatorWeight(
        address _operator
    ) public view returns (uint256) {
        uint256 quorumWeight = getQuorumWeight(_operator);
        uint256 operatorSetWeight = getOperatorSetWeight(_operator);

        return quorumWeight + operatorSetWeight;
    }

    /// @notice Calculates operator's weight in the quorum
    /// @param operator The operator address to calculate weight for
    /// @return The operator's weight in quorum, or 0 if below minimum
    function getQuorumWeight(
        address operator
    ) public view returns (uint256) {
        // Get strategy params from quorum
        StrategyParams[] memory strategyParams = _quorum.strategies;
        uint256 weight;

        // Create strategy array for batch shares query
        IStrategy[] memory strategies = new IStrategy[](strategyParams.length);
        for (uint256 i; i < strategyParams.length; i++) {
            strategies[i] = strategyParams[i].strategy;
        }

        // Get operator's shares for all strategies
        uint256[] memory shares = DELEGATION_MANAGER.getOperatorShares(operator, strategies);

        // Calculate weighted sum of shares
        for (uint256 i; i < strategyParams.length; i++) {
            weight += shares[i] * strategyParams[i].multiplier;
        }
        // Divide by BPS to get final weight
        weight = weight / BPS;

        // Return 0 if below minimum weight
        if (weight >= _minimumWeight) {
            return weight;
        } else {
            return 0;
        }
    }

    /// @notice Calculates operator's available weight in current operator set
    /// @dev Weight calculation:
    ///      1. Check operator set membership
    ///      2. Get shares and allocation for each strategy
    ///      3. Calculate available proportion (currentMagnitude/maxMagnitude)
    ///      4. Sum up available shares weighted by proportion
    /// @param operator The operator address to calculate weight for
    /// @return The operator's available weight in set, or 0 if below minimum
    function getOperatorSetWeight(
        address operator
    ) public view returns (uint256) {
        // Return 0 if allocation manager not set
        if (address(allocationManager) == address(0)) {
            return 0;
        }

        uint256 totalWeight;

        // Loop through all operator sets
        for (uint256 setIndex = 0; setIndex < currentOperatorSetIds.length; setIndex++) {
            // Create operator set struct for current id
            OperatorSet memory operatorSet =
                OperatorSet({avs: address(_serviceManager), id: currentOperatorSetIds[setIndex]});

            // Check operator set membership
            if (!allocationManager.isMemberOfOperatorSet(operator, operatorSet)) {
                continue;
            }

            // Get strategies from operator set
            IStrategy[] memory strategies =
                allocationManager.getStrategiesInOperatorSet(operatorSet);
            if (strategies.length == 0) {
                continue;
            }

            // Get operator's shares for all strategies
            uint256[] memory shares = DELEGATION_MANAGER.getOperatorShares(operator, strategies);

            // Calculate available weight for each strategy
            for (uint256 i = 0; i < strategies.length; i++) {
                // Get allocation and max magnitude
                IAllocationManager.Allocation memory allocation =
                    allocationManager.getAllocation(operator, operatorSet, strategies[i]);
                uint64 maxMagnitude = allocationManager.getMaxMagnitude(operator, strategies[i]);

                if (maxMagnitude == 0) {
                    continue;
                }

                // Calculate available proportion
                uint256 slashableProportion =
                    uint256(allocation.currentMagnitude) * WAD / maxMagnitude;

                // Add weighted shares to total
                totalWeight += shares[i] * slashableProportion / WAD;
            }
        }

        // Return 0 if below minimum weight
        if (totalWeight >= _minimumWeight) {
            return totalWeight;
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

    /// @notice Checks if an operator is registered on the AVS Directory(M2).
    /// @param operator The address of the operator to check.
    /// @return bool True if the operator is registered on the AVS Directory, false otherwise.
    function operatorRegisteredOnAVSDirectory(
        address operator
    ) public view returns (bool) {
        return AVS_DIRECTORY.avsOperatorStatus(_serviceManager, operator)
            == IAVSDirectoryTypes.OperatorAVSRegistrationStatus.REGISTERED;
    }

    /// @notice Checks if an operator is registered on the current operator set.
    /// @param operator The address of the operator to check.
    /// @return bool True if the operator is registered on the current operator set, false otherwise.
    function operatorRegisteredOnCurrentOperatorSets(
        address operator
    ) public view returns (bool) {
        if (address(allocationManager) == address(0)) {
            return false;
        }

        // Check if operator is registered in any current set
        for (uint256 i = 0; i < currentOperatorSetIds.length; i++) {
            OperatorSet memory operatorSet =
                OperatorSet({avs: address(_serviceManager), id: currentOperatorSetIds[i]});
            if (allocationManager.isMemberOfOperatorSet(operator, operatorSet)) {
                return true;
            }
        }
        return false;
    }

    /// @notice Checks if an operator is registered on the AVS Directory or the current operator set.
    /// @param operator The address of the operator to check.
    /// @return bool True if the operator is registered on the AVS Directory or the current operator set, false otherwise.
    function operatorRegistered(
        address operator
    ) public view returns (bool) {
        return operatorRegisteredOnAVSDirectory(operator)
            || operatorRegisteredOnCurrentOperatorSets(operator);
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
    function _deregisterOperatorM2Quorum(
        address operator
    ) internal {
        if (!operatorRegisteredOnAVSDirectory(operator)) {
            revert OperatorNotRegistered();
        }

        int256 delta = _updateOperatorWeight(operator);
        _updateTotalWeight(delta);
        IServiceManager(_serviceManager).deregisterOperatorFromAVS(operator);
        if (!operatorRegisteredOnCurrentOperatorSets(operator)) {
            _totalOperators--;
            emit OperatorDeregistered(operator, address(_serviceManager));
        }
    }

    /// @dev registers an operator through a provided signature
    /// @param operatorSignature Contains the operator's signature, salt, and expiry
    /// @param signingKey The signing key to add to the operator's history
    function _registerOperatorM2Quorum(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature,
        address signingKey
    ) internal virtual {
        if (operatorRegisteredOnAVSDirectory(operator)) {
            revert OperatorAlreadyRegistered();
        }

        int256 delta = _updateOperatorWeight(operator);
        _updateTotalWeight(delta);
        _updateOperatorSigningKey(operator, signingKey);
        IServiceManager(_serviceManager).registerOperatorToAVS(operator, operatorSignature);
        if (!operatorRegisteredOnCurrentOperatorSets(operator)) {
            _totalOperators++;
            emit OperatorRegistered(operator, _serviceManager);
        }
    }

    /// @notice Deregisters an operator from a set of operator sets.
    /// @dev This function is used to deregister an operator from a set of operator sets.
    /// @param operator The address of the operator to deregister.
    function _deregisterOperatorFromOperatorSets(
        address operator
    ) internal virtual {
        IServiceManager(_serviceManager).deregisterOperatorFromOperatorSets(
            operator, currentOperatorSetIds
        );
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
        if (!operatorRegistered(operator)) {
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
