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

import {BitmapUtils} from "./libraries/BitmapUtils.sol";
import {SlashingRegistryCoordinator} from "./SlashingRegistryCoordinator.sol";
import {ISlashingRegistryCoordinator} from "./interfaces/ISlashingRegistryCoordinator.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

/**
 * @title A `RegistryCoordinator` that has three registries:
 *      1) a `StakeRegistry` that keeps track of operators' stakes
 *      2) a `BLSApkRegistry` that keeps track of operators' BLS public keys and aggregate BLS public keys for each quorum
 *      3) an `IndexRegistry` that keeps track of an ordered list of operators for each quorum
 *
 * @author Layr Labs, Inc.
 */
contract RegistryCoordinator is IRegistryCoordinator, SlashingRegistryCoordinator {
    using BitmapUtils for *;

    /// @notice the ServiceManager for this AVS, which forwards calls onto EigenLayer's core contracts
    IServiceManager public immutable serviceManager;

    constructor(
        IServiceManager _serviceManager,
        IStakeRegistry _stakeRegistry,
        IBLSApkRegistry _blsApkRegistry,
        IIndexRegistry _indexRegistry,
        IAllocationManager _allocationManager,
        IPauserRegistry _pauserRegistry
    )
        SlashingRegistryCoordinator(
            _stakeRegistry,
            _blsApkRegistry,
            _indexRegistry,
            _allocationManager,
            _pauserRegistry
        )
    {
        serviceManager = _serviceManager;
    }

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
        require(!m2QuorumsDisabled, M2QuorumsAlreadyDisabled());
        /**
         * If the operator has NEVER registered a pubkey before, use `params` to register
         * their pubkey in blsApkRegistry
         *
         * If the operator HAS registered a pubkey, `params` is ignored and the pubkey hash
         * (operatorId) is fetched instead
         */
        bytes32 operatorId = _getOrCreateOperatorId(msg.sender, params);

        // Register the operator in each of the registry contracts and update the operator's
        // quorum bitmap and registration status
        uint32[] memory numOperatorsPerQuorum = _registerOperator({
            operator: msg.sender,
            operatorId: operatorId,
            quorumNumbers: quorumNumbers,
            socket: socket
        }).numOperatorsPerQuorum;

        // For each quorum, validate that the new operator count does not exceed the maximum
        // (If it does, an operator needs to be replaced -- see `registerOperatorWithChurn`)
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);

            require(
                numOperatorsPerQuorum[i] <= _quorumParams[quorumNumber].maxOperatorCount,
                MaxQuorumsReached()
            );
        }

        // If the operator wasn't registered for any quorums, update their status
        // and register them with this AVS in EigenLayer core (DelegationManager)
        if (_operatorInfo[msg.sender].status != OperatorStatus.REGISTERED) {
            _operatorInfo[msg.sender] =
                OperatorInfo({operatorId: operatorId, status: OperatorStatus.REGISTERED});

            serviceManager.registerOperatorToAVS(msg.sender, operatorSignature);
            emit OperatorRegistered(msg.sender, operatorId);
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
        require(!m2QuorumsDisabled, M2QuorumsAlreadyDisabled());

        /**
         * If the operator has NEVER registered a pubkey before, use `params` to register
         * their pubkey in blsApkRegistry
         *
         * If the operator HAS registered a pubkey, `params` is ignored and the pubkey hash
         * (operatorId) is fetched instead
         */
        bytes32 operatorId = _getOrCreateOperatorId(msg.sender, params);

        _registerOperatorWithChurn({
            operator: msg.sender,
            operatorId: operatorId,
            quorumNumbers: quorumNumbers,
            socket: socket,
            operatorKickParams: operatorKickParams,
            churnApproverSignature: churnApproverSignature
        });

        // If the operator wasn't registered for any quorums, update their status
        // and register them with this AVS in EigenLayer core (DelegationManager)
        if (_operatorInfo[msg.sender].status != OperatorStatus.REGISTERED) {
            _operatorInfo[msg.sender] =
                OperatorInfo({operatorId: operatorId, status: OperatorStatus.REGISTERED});

            serviceManager.registerOperatorToAVS(msg.sender, operatorSignature);
            emit OperatorRegistered(msg.sender, operatorId);
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
        M2quorumBitmap = _getQuorumBitmap(quorumCount);

        // Enable operator sets mode
        operatorSetsEnabled = true;

        emit OperatorSetsEnabled();
    }

    /// @inheritdoc IRegistryCoordinator
    function disableM2QuorumRegistration() external onlyOwner {
        require(operatorSetsEnabled, OperatorSetsNotEnabled());

        m2QuorumsDisabled = true;

        emit M2QuorumsDisabled();
    }

    /// @dev Hook to allow for any post-deregister logic
    function _afterDeregisterOperator(
        address operator,
        bytes32 operatorId,
        bytes memory quorumNumbers,
        uint192 newBitmap
    ) internal virtual override {
        uint256 operatorM2QuorumBitmap = newBitmap.minus(M2quorumBitmap);
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

    /// @dev need to override function here since its defined in both these contracts
    function owner()
        public
        view
        override(SlashingRegistryCoordinator, ISlashingRegistryCoordinator)
        returns (address)
    {
        return OwnableUpgradeable.owner();
    }
}
