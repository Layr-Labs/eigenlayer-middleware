// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IBLSApkRegistry, IBLSApkRegistryTypes} from "./interfaces/IBLSApkRegistry.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "./interfaces/IIndexRegistry.sol";
import {IServiceManager} from "./interfaces/IServiceManager.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";
import {ISocketRegistry} from "./interfaces/ISocketRegistry.sol";

import {BitmapUtils} from "./libraries/BitmapUtils.sol";
import {SlashingRegistryCoordinator} from "./SlashingRegistryCoordinator.sol";
import {ISlashingRegistryCoordinator} from "./interfaces/ISlashingRegistryCoordinator.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {RegistryCoordinatorStorage} from "./RegistryCoordinatorStorage.sol";

/**
 * @title A `RegistryCoordinator` that has three registries:
 *      1) a `StakeRegistry` that keeps track of operators' stakes
 *      2) a `BLSApkRegistry` that keeps track of operators' BLS public keys and aggregate BLS public keys for each quorum
 *      3) an `IndexRegistry` that keeps track of an ordered list of operators for each quorum
 *
 * @author Layr Labs, Inc.
 */
contract RegistryCoordinator is RegistryCoordinatorStorage {
    using BitmapUtils for *;

    constructor(
        IServiceManager _serviceManager,
        IStakeRegistry _stakeRegistry,
        IBLSApkRegistry _blsApkRegistry,
        IIndexRegistry _indexRegistry,
        ISocketRegistry _socketRegistry,
        IAllocationManager _allocationManager,
        IPauserRegistry _pauserRegistry
    )
        RegistryCoordinatorStorage(
            _serviceManager,
            _stakeRegistry,
            _blsApkRegistry,
            _indexRegistry,
            _socketRegistry,
            _allocationManager,
            _pauserRegistry
        ) 
    {}

    /**
     *
     *                         EXTERNAL FUNCTIONS
     *
     */

    /// @inheritdoc IRegistryCoordinator
    function registerOperator(
        bytes memory quorumNumbers,
        string memory socket,
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params,
        SignatureWithSaltAndExpiry memory operatorSignature
    ) external onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) {
        require(!isM2QuorumRegistrationDisabled, M2QuorumRegistrationIsDisabled());
        
        // Check if the operator has registered before
        bool operatorRegisteredBefore = _operatorInfo[msg.sender].status == OperatorStatus.REGISTERED;

        // register the operator with the registry coordinator
        _registerOperator({
            operator: msg.sender,
            operatorId: _getOrCreateOperatorId(msg.sender, params),
            quorumNumbers: quorumNumbers,
            socket: socket,
            checkMaxOperatorCount: true
        });

        // If the operator has never registered before, register them with the AVSDirectory
        if (!operatorRegisteredBefore) {
            serviceManager.registerOperatorToAVS(msg.sender, operatorSignature);
        }
    }

    /// @inheritdoc IRegistryCoordinator
    function registerOperatorWithChurn(
        bytes calldata quorumNumbers,
        string memory socket,
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params,
        OperatorKickParam[] memory operatorKickParams,
        SignatureWithSaltAndExpiry memory churnApproverSignature,
        SignatureWithSaltAndExpiry memory operatorSignature
    ) external onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) {
        require(!isM2QuorumRegistrationDisabled, M2QuorumRegistrationIsDisabled());

        // Check if the operator has registered before
        bool operatorRegisteredBefore = _operatorInfo[msg.sender].status == OperatorStatus.REGISTERED;

        // register the operator with the registry coordinator with churn
        _registerOperatorWithChurn({
            operator: msg.sender,
            operatorId: _getOrCreateOperatorId(msg.sender, params),
            quorumNumbers: quorumNumbers,
            socket: socket,
            operatorKickParams: operatorKickParams,
            churnApproverSignature: churnApproverSignature
        });

        // If the operator has never registered before, register them with the AVSDirectory
        if (!operatorRegisteredBefore) {
            serviceManager.registerOperatorToAVS(msg.sender, operatorSignature);
        }
    }

    /// @inheritdoc IRegistryCoordinator
    function deregisterOperator(
        bytes memory quorumNumbers
    ) external override onlyWhenNotPaused(PAUSED_DEREGISTER_OPERATOR) {
        // Check that the quorum numbers are M2 quorums
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            require(
                !operatorSetsEnabled || _isM2Quorum(uint8(quorumNumbers[i])), OperatorSetQuorum()
            );
        }
        _deregisterOperator({operator: msg.sender, quorumNumbers: quorumNumbers});
    }

    /// @inheritdoc IRegistryCoordinator
    function enableOperatorSets() external onlyOwner {
        require(!operatorSetsEnabled, OperatorSetsAlreadyEnabled());

        // Set the bitmap for M2 quorums
        m2QuorumBitmap = _getQuorumBitmap(quorumCount);

        // Enable operator sets mode
        operatorSetsEnabled = true;

        emit OperatorSetsEnabled();
    }

    /// @inheritdoc IRegistryCoordinator
    function disableM2QuorumRegistration() external onlyOwner {
        require(!isM2QuorumRegistrationDisabled, M2QuorumRegistrationIsDisabled());

        isM2QuorumRegistrationDisabled = true;

        emit M2QuorumRegistrationDisabled();
    }

    /**
     *
     *                            INTERNAL FUNCTIONS
     *
     */

    /// @dev override the _forceDeregisterOperator function to handle M2 quorum deregistration
    function _forceDeregisterOperator(address operator, bytes memory quorumNumbers) internal virtual override {
        // filter out M2 quorums from the quorum numbers
        uint256 operatorSetBitmap = quorumNumbers.orderedBytesArrayToBitmap().minus(m2QuorumBitmap);
        if (!operatorSetBitmap.isEmpty()) {
            // call the parent _forceDeregisterOperator function for operator sets quorums
            super._forceDeregisterOperator(operator, operatorSetBitmap.bitmapToBytesArray());
        }
    }

    /// @dev Hook to prevent any new quorums from being created if operator sets are not enabled
    function _beforeCreateQuorum(
        uint8 quorumNumber
    ) internal virtual override {
        require(operatorSetsEnabled, OperatorSetsNotEnabled());
    }

    /// @dev Hook to allow for any post-deregister logic
    function _afterDeregisterOperator(
        address operator,
        bytes32 operatorId,
        bytes memory quorumNumbers,
        uint192 newBitmap
    ) internal virtual override {
        uint256 operatorM2QuorumBitmap = newBitmap.minus(m2QuorumBitmap);
        // If the operator is no longer registered for any M2 quorums, update their status and deregister
        // them from the AVS via the EigenLayer core contracts
        if (operatorM2QuorumBitmap.isEmpty()) {
            serviceManager.deregisterOperatorFromAVS(operator);
        }
    }

    /// @dev Returns a bitmap with all bits set up to `quorumCount`. Used for bit-masking quorum numbers
    /// and differentiating between operator sets and M2 quorums
    function _getQuorumBitmap(
        uint256 quorumCount
    ) internal pure returns (uint256) {
        // This creates a number where all bits up to quorumCount are set to 1
        // For example:
        // quorumCount = 3 -> 0111 (7 in decimal)
        // quorumCount = 5 -> 011111 (31 in decimal)
        // This is a safe operation since we limit MAX_QUORUM_COUNT to 192
        return (1 << quorumCount) - 1;
    }

    /// @notice Returns true if the quorum number is an M2 quorum
    /// @dev We use bitwise and to check if the quorum number is an M2 quorum
    function _isM2Quorum(
        uint8 quorumNumber
    ) internal view returns (bool) {
        return m2QuorumBitmap.isSet(quorumNumber);
    }

    /**
     *
     *                            VIEW FUNCTIONS
     *
     */

    /// @notice Returns true if the quorum number is an M2 quorum
    function isM2Quorum(
        uint8 quorumNumber
    ) external view returns (bool) {
        return _isM2Quorum(quorumNumber);
    }

    /**
     * @notice Returns the message hash that an operator must sign to register their BLS public key.
     * @param operator is the address of the operator registering their BLS public key
     */
    function calculatePubkeyRegistrationMessageHash(
        address operator
    ) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(PUBKEY_REGISTRATION_TYPEHASH, operator)));
    }
}
