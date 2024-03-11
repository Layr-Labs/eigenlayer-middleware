// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {ECDSAStakeRegistryStorage, Quorum, StrategyParams} from "./ECDSAStakeRegistryStorage.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IServiceManager} from "../interfaces/IServiceManager.sol";

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {CheckpointsUpgradeable} from "@openzeppelin-upgrades/contracts/utils/CheckpointsUpgradeable.sol";
import {SignatureCheckerUpgradeable} from "@openzeppelin-upgrades/contracts/utils/cryptography/SignatureCheckerUpgradeable.sol";
import {IERC1271Upgradeable} from "@openzeppelin-upgrades/contracts/interfaces/IERC1271Upgradeable.sol";

/// @title ECDSA Stake Registry
/// @notice THIS CONTRACT IS NOT AUDITED
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
    /// @param _thresholdWeightBps The threshold weight in basis points.
    /// @param _quorum The quorum struct containing the details of the quorum thresholds.
    function initialize(
        address _serviceManager,
        uint256 _thresholdWeightBps,
        Quorum memory _quorum
    ) external initializer {
        __ECDSAStakeRegistry_init(_serviceManager, _thresholdWeightBps, _quorum);
    }

    /// @notice Registers a new operator using a provided signature
    /// @param _operatorSignature Contains the operator's signature, salt, and expiry
    function registerOperatorWithSignature(
        address _operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory _operatorSignature
    ) external {
        _registerOperatorWithSig(_operator, _operatorSignature);
    }

    /// @notice Deregisters an existing operator
    function deregisterOperator() external {
        _deregisterOperator(msg.sender);
    }

    /**
     * @notice Updates the StakeRegistry's view of one or more operators' stakes adding a new entry in their history of stake checkpoints, 
     * @dev Queries stakes from the Eigenlayer core DelegationManager contract
     * @param _operators A list of operator addresses to update
     */
    function updateOperators(address[] memory _operators) external {
        _updateOperators(_operators);
    }

    /// @notice Updates the strategies and their weights for the quourum
    /// @dev Access controlled to the contract owner
    /// @param _quorum The new quorum configuration
    function updateQuorumConfig(Quorum memory _quorum, address[] memory _operators) external onlyOwner {
        _updateQuorumConfig(_quorum);
        _updateOperators(_operators);
    }

    /// @notice Updates the weight an operator must have to join the operator set
    /// @dev Access controlled to the contract owner
    /// @param _newMinimumWeight The new weight an operator must have to join the operator set
    function updateMinimumWeight(uint256 _newMinimumWeight, address[] memory _operators) external onlyOwner {
        _updateMinimumWeight(_newMinimumWeight);
        _updateOperators(_operators);
    }

    /**
     * @notice Adjusts the cumulative threshold weight for a valid message to be signed by the operator set
     * @param _thresholdWeightBps The updated threshold weight.
     */
    function updateStakeThreshold(uint256 _thresholdWeightBps) external onlyOwner {
        _updateStakeThreshold(_thresholdWeightBps);
    }

    /// @notice Verifies if the provided signature data is valid for the given data hash.
    /// @param _dataHash The hash of the data that was signed.
    /// @param _signatureData Encoded signature data consisting of an array of signers, an array of signatures, and a reference block number.
    /// @return The function selector that indicates the signature is valid according to ERC1271 standard.
    function isValidSignature(
        bytes32 _dataHash,
        bytes memory _signatureData
    ) external view returns (bytes4) {
        (address[] memory signers, bytes[] memory signatures, uint32 referenceBlock) = abi.decode(
            _signatureData,
            (address[], bytes[], uint32)
        );
        _checkSignatures(_dataHash, signers, signatures, referenceBlock);
        return IERC1271Upgradeable.isValidSignature.selector;
    }

    /// @notice Retrieves the current stake quorum details.
    /// @return Quorum - The current quorum of strategies and weights
    function quorum() external view returns (Quorum memory) {
        return _quorum;
    }

    /// @notice Retrieves the last recorded weight for a given operator.
    /// @param _operator The address of the operator.
    /// @return uint256 - The latest weight of the operator.
    function getLastCheckpointOperatorWeight(address _operator) external view returns (uint256) {
        return _operatorWeightHistory[_operator].latest();
    }

    /// @notice Retrieves the last recorded total weight across all operators.
    /// @return uint256 - The latest total weight.
    function getLastCheckpointTotalWeight() external view returns (uint256) {
        return _totalWeightHistory.latest();
    }

    /// @notice Retrieves the operator's weight at a specific block number.
    /// @param _operator The address of the operator.
    /// @param _blockNumber The block number to get the operator weight for the quorum
    /// @return uint256 - The weight of the operator at the given block.
    function getOperatorWeightAtBlock(
        address _operator,
        uint32 _blockNumber
    ) external view returns (uint256) {
        return _operatorWeightHistory[_operator].getAtBlock(_blockNumber);
    }

    /// @notice Retrieves the total weight at a specific block number.
    /// @param _blockNumber The block number to get the total weight for the quorum
    /// @return uint256 - The total weight at the given block.
    function getLastCheckpointTotalWeightAtBlock(
        uint32 _blockNumber
    ) external view returns (uint256) {
        return _totalWeightHistory.getAtBlock(_blockNumber);
    }

    function operatorRegistered(address _operator) external view returns (bool) {
        return _operatorRegistered[_operator];
    }

    /// @notice Calculates the current weight of an operator based on their delegated stake in the strategies considered in the quorum
    /// @param _operator The address of the operator.
    /// @return uint256 - The current weight of the operator; returns 0 if below the threshold.
    function getOperatorWeight(address _operator) public view returns (uint256) {
        StrategyParams[] memory strategyParams = _quorum.strategies;
        uint256 weight;
        IStrategy[] memory strategies = new IStrategy[](strategyParams.length);
        for (uint256 i; i < strategyParams.length; i++) {
            strategies[i]=strategyParams[i].strategy;

        }
        uint256[] memory shares = DELEGATION_MANAGER.getOperatorShares(_operator, strategies);
        for (uint256 i; i<strategyParams.length; i++){
            weight += shares[i] * strategyParams[i].multiplier;

        }
        weight = weight / BPS;
        return weight >= minimumWeight ? weight : 0;
    }

    /// @notice Initializes state for the StakeRegistry
    /// @param _serviceManager The AVS' ServiceManager contract's address
    function __ECDSAStakeRegistry_init(
        address _serviceManager,
        uint256 _thresholdWeightBps,
        Quorum memory _quorum
    ) internal onlyInitializing {
        serviceManager = _serviceManager;
        _updateStakeThreshold(_thresholdWeightBps);
        _updateQuorumConfig(_quorum);
        __Ownable_init();
    }

    function updateOperatorsForQuorum(address[][] memory operatorsPerQuorum, bytes memory) external {
        _updateAllOperators(operatorsPerQuorum[0]);
    }

    function _updateAllOperators (address[] memory _operators) internal {
        if (_operators.length != _totalOperators) revert MustUpdateAllOperators();
        _updateOperators(_operators);
    }

    function _updateOperators(address[] memory _operators) internal {
        if (_operators.length != _totalOperators) revert MustUpdateAllOperators();
        int256 delta;
        for (uint256 i; i < _operators.length; i++) {
            delta += _updateOperatorWeight(_operators[i]);
        }
        _updateTotalWeight(delta);
    }

    function _updateStakeThreshold(uint256 _thresholdWeightBps) internal {
        _thresholdWeightBpsHistory.push(_thresholdWeightBps);
        emit ThresholdWeightUpdated(_thresholdWeightBps);
    }

    /// @dev Updates the weight an operator must have to join the operator set
    /// @param _newMinimumWeight The new weight an operator must have to join the operator set
    function _updateMinimumWeight(uint256 _newMinimumWeight) internal {
        uint256 oldMinimumWeight = minimumWeight;
        minimumWeight = _newMinimumWeight;
        emit MinimumWeightUpdated(oldMinimumWeight, _newMinimumWeight);
    }

    /// @dev Internal function to set the quorum configuration
    /// @param _newQuorum The new quorum configuration to set
    function _updateQuorumConfig(Quorum memory _newQuorum) internal {
        if (!_isValidQuorum(_newQuorum)) revert InvalidQuorum();
        Quorum memory oldQuorum = _quorum;
        delete _quorum;
        for (uint256 i; i < _newQuorum.strategies.length; i++) {
            _quorum.strategies.push(_newQuorum.strategies[i]);
        }
        emit QuorumUpdated(oldQuorum, _newQuorum);
    }

    /// @dev Internal function to deregister an operator
    /// @param _operator The operator's address to deregister
    function _deregisterOperator(address _operator) internal {
        if (!_operatorRegistered[_operator]) revert OperatorNotRegistered();
        _totalOperators--;
        delete _operatorRegistered[_operator];
        int256 delta = _updateOperatorWeight(_operator);
        _updateTotalWeight(delta);
        IServiceManager(serviceManager).deregisterOperatorFromAVS(_operator);
        emit OperatorDeregistered(_operator, address(serviceManager));
    }

    /// @dev registers an operator through a provided signature
    /// @param _operatorSignature Contains the operator's signature, salt, and expiry
    function _registerOperatorWithSig(
        address _operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory _operatorSignature
    ) internal virtual {
        if (_operatorRegistered[_operator]) revert OperatorAlreadyRegistered();
        _totalOperators++;
        _operatorRegistered[_operator] = true;
        int256 delta = _updateOperatorWeight(_operator);
        _updateTotalWeight(delta);
        IServiceManager(serviceManager).registerOperatorToAVS(_operator, _operatorSignature);
        emit OperatorRegistered(_operator, serviceManager);
    }

    /// @notice Updates the weight of an operator and returns the previous and current weights.
    /// @param _operator The address of the operator to update the weight of.
    function _updateOperatorWeight(address _operator) internal virtual returns (int256){
        int256 delta;
        uint256 oldWeight;
        uint256 newWeight;
        if (!_operatorRegistered[_operator]) {
            (oldWeight, ) = _operatorWeightHistory[_operator].push(0);
            delta -= int(oldWeight);
        } else {
            newWeight = getOperatorWeight(_operator);
            (oldWeight, ) = _operatorWeightHistory[_operator].push(newWeight);
            delta = int256(newWeight) - int256(oldWeight);
        }
        emit OperatorWeightUpdated(_operator, oldWeight, newWeight);
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

    /// @dev Verifies a quorum has:
    ///     1. Weights that add to 10_000 basis points
    ///     2. There are no duplicate strategies considered in the quorum
    /// @param _quorum The new quorum configuration
    /// @return bool Indicates if the quorum is valid
    function _isValidQuorum(Quorum memory _quorum) internal pure returns (bool) {
        StrategyParams[] memory strategies = _quorum.strategies;
        address lastStrategy;
        address currentStrategy;
        uint256 totalMultiplier;
        for (uint256 i; i < strategies.length; i++) {
            currentStrategy = address(strategies[i].strategy);
            if (lastStrategy >= currentStrategy) revert NotSorted();
            lastStrategy = currentStrategy;
            totalMultiplier += strategies[i].multiplier;
        }
        if (totalMultiplier != BPS) return false;
        return true;
    }

    /**
     * @notice Common logic to verify a batch of ECDSA signatures against a hash, using either last stake weight or at a specific block.
     * @param _dataHash The hash of the data the signers endorsed.
     * @param _signers A collection of addresses that endorsed the data hash.
     * @param _signatures A collection of signatures matching the signers.
     * @param _referenceBlock The block number for evaluating stake weight; use max uint32 for latest weight.
     */
    function _checkSignatures(
        bytes32 _dataHash,
        address[] memory _signers,
        bytes[] memory _signatures,
        uint32 _referenceBlock
    ) internal view {
        uint256 signersLength = _signers.length;
        address lastSigner;
        uint256 signedWeight;

        _validateSignaturesLength(signersLength, _signatures.length);
        for (uint256 i; i < signersLength; i++) {
            address currentSigner = _signers[i];

            _validateSortedSigners(lastSigner, currentSigner);
            _validateSignature(currentSigner, _dataHash, _signatures[i]);

            lastSigner = currentSigner;
            uint256 operatorWeight = _getOperatorWeight(currentSigner, _referenceBlock);
            signedWeight += operatorWeight;
        }

        _validateThresholdStake(signedWeight, _referenceBlock);
    }

    /// @notice Validates that the number of signers equals the number of signatures, and neither is zero.
    /// @param _signersLength The number of signers.
    /// @param _signaturesLength The number of signatures.
    function _validateSignaturesLength(
        uint256 _signersLength,
        uint256 _signaturesLength
    ) internal pure {
        if (_signersLength != _signaturesLength) revert LengthMismatch();
        if (_signersLength == 0) revert InvalidLength();
    }


    /// @notice Ensures that signers are sorted in ascending order by address.
    /// @param _lastSigner The address of the last signer.
    /// @param _currentSigner The address of the current signer.
    function _validateSortedSigners(address _lastSigner, address _currentSigner) internal pure {
        if (_lastSigner >= _currentSigner) revert NotSorted();
    }

    /// @notice Validates a given signature against the signer's address and data hash.
    /// @param _signer The address of the signer to validate.
    /// @param _dataHash The hash of the data that is signed.
    /// @param _signature The signature to validate.
    function _validateSignature(
        address _signer,
        bytes32 _dataHash,
        bytes memory _signature
    ) internal view {
        if (!_signer.isValidSignatureNow(_dataHash, _signature)) revert InvalidSignature();
    }


    /// @notice Retrieves the operator weight for a signer, either at the last checkpoint or a specified block.
    /// @param _signer The address of the signer whose weight is returned.
    /// @param _referenceBlock The block number to query the operator's weight at, or the maximum uint32 value for the last checkpoint.
    /// @return The weight of the operator.
    function _getOperatorWeight(
        address _signer,
        uint32 _referenceBlock
    ) internal view returns (uint256) {
        if (_referenceBlock == type(uint32).max) {
            return _operatorWeightHistory[_signer].latest();
        } else {
            return _operatorWeightHistory[_signer].getAtBlock(_referenceBlock);
        }
    }

    /// @notice Retrieve the total stake weight at a specific block or the latest if not specified.
    /// @dev If the `_referenceBlock` is the maximum value for uint32, the latest total weight is returned.
    /// @param _referenceBlock The block number to retrieve the total stake weight from.
    /// @return The total stake weight at the given block or the latest if the given block is the max uint32 value.
    function _getTotalWeight(uint32 _referenceBlock) internal view returns (uint256) {
        if (_referenceBlock == type(uint32).max) {
            return _totalWeightHistory.latest();
        } else {
            return _totalWeightHistory.getAtBlock(_referenceBlock);
        }
    }

    /// @notice Retrieves the threshold stake for a given reference block.
    /// @param _referenceBlock The block number to query the threshold stake for.
    /// If set to the maximum uint32 value, it retrieves the latest threshold stake.
    /// @return The threshold stake in basis points for the reference block.
    function _getThresholdStake(uint32 _referenceBlock) internal view returns (uint256) {
        if (_referenceBlock == type(uint32).max) {
            return _thresholdWeightBpsHistory.latest();
        } else {
            return _thresholdWeightBpsHistory.getAtBlock(_referenceBlock);
        }
    }

    /// @notice Validates that the cumulative stake of signed messages meets or exceeds the required threshold.
    /// @param _signedWeight The cumulative weight of the signers that have signed the message.
    /// @param _referenceBlock The block number to verify the stake threshold for
    function _validateThresholdStake(uint256 _signedWeight, uint32 _referenceBlock) internal view {
        uint256 totalWeight = _getTotalWeight(_referenceBlock);
        if (_signedWeight > totalWeight) revert InvalidSignedWeight();
        if (_getThresholdStake(_referenceBlock) > (_signedWeight * BPS) / totalWeight)
            revert InsufficientSignedStake();
    }
}
