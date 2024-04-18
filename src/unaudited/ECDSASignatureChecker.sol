// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {IERC1271Upgradeable} from "@openzeppelin-upgrades/contracts/interfaces/IERC1271Upgradeable.sol";
import {CheckpointsUpgradeable} from "@openzeppelin-upgrades/contracts/utils/CheckpointsUpgradeable.sol";
import {SignatureCheckerUpgradeable} from "@openzeppelin-upgrades/contracts/utils/cryptography/SignatureCheckerUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

interface IECDSAStakeRegistry {
    function getOperatorWeightAtBlock(address _operator, uint32 _blockNumber) external;
    function getOperatorWeight(address _operator) external;

    function getTotalWeightAtBlock(uint32 _blockNumber) external;
    function getTotalWeight() external;
}

abstract contract ECDSASignatureChecker is OwnableUpgradeable, IERC1271Upgradeable{
    using SignatureCheckerUpgradeable for address;
    using CheckpointsUpgradeable for CheckpointsUpgradeable.History;

    /// @notice Indicates when the lengths of the signers array and signatures array do not match.
    error LengthMismatch();

    /// @notice Indicates encountering an invalid signature.
    error InvalidSignature();

    /// @notice Indicates encountering an invalid length for the signers or signatures array.
    error InvalidLength();

    /// @notice Indicates the system finds a list of items unsorted
    error NotSorted();

    /// @notice Indicates operator weights were out of sync and the signed weight exceed the total
    error InvalidSignedWeight();

    /// @notice Indicates the total signed stake fails to meet the required threshold.
    error InsufficientSignedStake();

    /// @notice Emits when setting a new threshold weight.
    event ThresholdWeightUpdated(uint256 _thresholdWeight);

    address internal stakeRegistry;

    /// @notice Tracks the threshold bps history using checkpoints
    CheckpointsUpgradeable.History internal _thresholdWeightHistory;

    constructor(address _stakeRegistry){
        stakeRegistry = _stakeRegistry;
    }

    function initialize() external initializer {
        __ECDSASignatureChecker_init();
    }

    function __ECDSASignatureChecker_init() internal onlyInitializing {}

    /**
     * @notice Sets a new cumulative threshold weight for message validation by operator set signatures.
     * @dev This function can only be invoked by the owner of the contract. It delegates the update to 
     * an internal function `_updateStakeThreshold`. 
     * @param _thresholdWeight The updated threshold weight required to validate a message. This is the 
     * cumulative weight that must be met or exceeded by the sum of the stakes of the signatories for 
     * a message to be deemed valid.
     */
    function updateStakeThreshold(uint256 _thresholdWeight) external onlyOwner {
        _updateStakeThreshold(_thresholdWeight);
    }


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

    /// @notice Ensures that signers are sorted in ascending order by address.
    /// @param _lastSigner The address of the last signer.
    /// @param _currentSigner The address of the current signer.
    function _validateSortedSigners(address _lastSigner, address _currentSigner) internal pure {
        if (_lastSigner >= _currentSigner){
            revert NotSorted();
        }
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
        if (!_signer.isValidSignatureNow(_dataHash, _signature)) {
            revert InvalidSignature();
        }
    }

    /// @notice Validates that the number of signers equals the number of signatures, and neither is zero.
    /// @param _signersLength The number of signers.
    /// @param _signaturesLength The number of signatures.
    function _validateSignaturesLength(
        uint256 _signersLength,
        uint256 _signaturesLength
    ) internal pure {
        if (_signersLength != _signaturesLength){
            revert LengthMismatch();
        }
        if (_signersLength == 0){
            revert InvalidLength();
        }
    }

    /// @notice Validates that the cumulative stake of signed messages meets or exceeds the required threshold.
    /// @param _signedWeight The cumulative weight of the signers that have signed the message.
    /// @param _referenceBlock The block number to verify the stake threshold for
    function _validateThresholdStake(uint256 _signedWeight, uint32 _referenceBlock) internal view {
        uint256 totalWeight = _getTotalWeight(_referenceBlock);
        if (_signedWeight > totalWeight){
            revert InvalidSignedWeight();
        }
        uint256 thresholdStake = _getThresholdStake(_referenceBlock);
        if (thresholdStake > _signedWeight){
            revert InsufficientSignedStake();
        }
    }




    /// @notice Retrieves the threshold stake for a given reference block.
    /// @param _referenceBlock The block number to query the threshold stake for.
    /// If set to the maximum uint32 value, it retrieves the latest threshold stake.
    /// @return The threshold stake in basis points for the reference block.
    function _getThresholdStake(uint32 _referenceBlock) internal view returns (uint256) {
        /// TODO: move threshold checkpoints to this contract
        if (_referenceBlock == type(uint32).max) {
            return _thresholdWeightHistory.latest();
        } else {
            return _thresholdWeightHistory.getAtBlock(_referenceBlock);
        }
    }

    /// @notice Retrieves the operator weight for a signer, either at the last checkpoint or a specified block.
    /// @param _signer The address of the signer whose weight is returned.
    /// @param _referenceBlock The block number to query the operator's weight at, or the maximum uint32 value for the last checkpoint.
    /// @return The weight of the operator.
    function _getOperatorWeight(
        address _signer,
        uint32 _referenceBlock
    ) internal view returns (uint256) {
        /// TODO: Call stake registry and get the stake
    }

    /// @notice Retrieve the total stake weight at a specific block or the latest if not specified.
    /// @dev If the `_referenceBlock` is the maximum value for uint32, the latest total weight is returned.
    /// @param _referenceBlock The block number to retrieve the total stake weight from.
    /// @return The total stake weight at the given block or the latest if the given block is the max uint32 value.
    function _getTotalWeight(uint32 _referenceBlock) internal view returns (uint256) {
        /// TODO: Call stake registry for this info
    }

    /// @dev Updates the stake threshold weight and records the history.
    /// @param _thresholdWeight The new threshold weight to set and record in the history.
    function _updateStakeThreshold(uint256 _thresholdWeight) internal {
        _thresholdWeightHistory.push(_thresholdWeight);
        emit ThresholdWeightUpdated(_thresholdWeight);
    }
}
