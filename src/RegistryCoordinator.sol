// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {
    IAllocationManager,
    OperatorSet
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
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
 * @title A `RegistryCoordinator` that has four registries:
 *      1) a `StakeRegistry` that keeps track of operators' stakes
 *      2) a `BLSApkRegistry` that keeps track of operators' BLS public keys and aggregate BLS public keys for each quorum
 *      3) an `IndexRegistry` that keeps track of an ordered list of operators for each quorum
 *      4) a `SocketRegistry` that keeps track of operators' sockets (arbitrary strings)
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
        require(
            quorumNumbers.orderedBytesArrayToBitmap().isSubsetOf(m2QuorumBitmap()),
            OnlyM2QuorumsAllowed()
        );

        // Check if the operator has registered before
        bool operatorRegisteredBefore =
            _operatorInfo[msg.sender].status == OperatorStatus.REGISTERED;

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
        require(
            quorumNumbers.orderedBytesArrayToBitmap().isSubsetOf(m2QuorumBitmap()),
            OnlyM2QuorumsAllowed()
        );

        // Check if the operator has registered before
        bool operatorRegisteredBefore =
            _operatorInfo[msg.sender].status == OperatorStatus.REGISTERED;

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
        require(
            quorumNumbers.orderedBytesArrayToBitmap().isSubsetOf(m2QuorumBitmap()),
            OnlyM2QuorumsAllowed()
        );

        _deregisterOperator({
            operator: msg.sender,
            quorumNumbers: quorumNumbers,
            shouldForceDeregister: false
        });
    }

    /// @inheritdoc IRegistryCoordinator
    function disableM2QuorumRegistration() external onlyOwner {
        require(!isM2QuorumRegistrationDisabled, M2QuorumRegistrationIsDisabled());

        isM2QuorumRegistrationDisabled = true;

        emit M2QuorumRegistrationDisabled();
    }

    /// @inheritdoc ISlashingRegistryCoordinator
    function ejectOperator(
        address operator,
        bytes memory quorumNumbers
    )
        public
        virtual
        override(ISlashingRegistryCoordinator, SlashingRegistryCoordinator)
        onlyEjector
    {
        _ejectOperators(operator, quorumNumbers, true);
    }

    /**
     *
     *                            INTERNAL FUNCTIONS
     *
     */

    /**
     * @notice Internal function to handle operator registration with churn
     * @param operator The operator to register
     * @param operatorId The operator's ID
     * @param quorumNumbers The quorum numbers to register for
     * @param socket The operator's socket
     * @param operatorKickParams The parameters needed to kick operators from quorums that have reached their caps
     * @param churnApproverSignature The churnApprover's signature approving the registration
     */
    function _registerOperatorWithChurn(
        address operator,
        bytes32 operatorId,
        bytes memory quorumNumbers,
        string memory socket,
        OperatorKickParam[] memory operatorKickParams,
        SignatureWithSaltAndExpiry memory churnApproverSignature
    ) internal virtual override {
        // verify churnApprover's signature
        _verifyChurnApproverSignature(
            operator, operatorId, operatorKickParams, churnApproverSignature
        );

        // quorum bitmap and registration status
        RegisterResults memory results = _registerOperator({
            operator: operator,
            operatorId: operatorId,
            quorumNumbers: quorumNumbers,
            socket: socket,
            checkMaxOperatorCount: false
        });

        // Check that each quorum's operator count is below the configured maximum. If the max
        // is exceeded, use `operatorKickParams` to deregister an existing operator to make space
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            OperatorSetParam memory operatorSetParams = _quorumParams[uint8(quorumNumbers[i])];

            /**
             * If the new operator count for any quorum exceeds the maximum, validate
             * that churn can be performed, then deregister the specified operator
             */
            if (results.numOperatorsPerQuorum[i] > operatorSetParams.maxOperatorCount) {
                _validateChurn({
                    quorumNumber: uint8(quorumNumbers[i]),
                    totalQuorumStake: results.totalStakes[i],
                    newOperator: operator,
                    newOperatorStake: results.operatorStakes[i],
                    kickParams: operatorKickParams[i],
                    setParams: operatorSetParams
                });

                bytes memory singleQuorumNumber = new bytes(1);
                singleQuorumNumber[0] = quorumNumbers[i];
                _ejectOperators(operatorKickParams[i].operator, singleQuorumNumber, false);
            }
        }
    }

    /// @dev override the _ejectOperators function to handle M2 quorum ejection
    function _ejectOperators(
        address operator,
        bytes memory quorumNumbers,
        bool shouldRecordEjectionTimestamp
    ) internal virtual override {
        if (shouldRecordEjectionTimestamp) {
            lastEjectionTimestamp[operator] = block.timestamp;
        }

        OperatorInfo storage operatorInfo = _operatorInfo[operator];
        bytes32 operatorId = operatorInfo.operatorId;
        uint192 quorumsToRemove =
            uint192(BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers, quorumCount));
        uint192 currentBitmap = _currentOperatorBitmap(operatorId);
        if (operatorInfo.status == OperatorStatus.REGISTERED && !quorumsToRemove.isEmpty()) {
            // For each quorum number, check if it's an M2 quorum
            for (uint256 i = 0; i < quorumNumbers.length; i++) {
                bytes memory singleQuorumNumber = new bytes(1);
                singleQuorumNumber[0] = quorumNumbers[i];

                if (_isM2Quorum(uint8(quorumNumbers[i]))) {
                    // For M2 quorums, use _deregisterOperator
                    _deregisterOperator({
                        operator: operator,
                        quorumNumbers: singleQuorumNumber,
                        shouldForceDeregister: true
                    });
                } else {
                    // For non-M2 quorums, use _forceDeregisterOperator
                    _forceDeregisterOperator(operator, singleQuorumNumber);
                }
            }
        }
    }

    /// @dev override the _forceDeregisterOperator function to handle M2 quorum deregistration
    function _forceDeregisterOperator(
        address operator,
        bytes memory quorumNumbers
    ) internal virtual override {
        // filter out M2 quorums from the quorum numbers
        uint256 operatorSetBitmap =
            quorumNumbers.orderedBytesArrayToBitmap().minus(m2QuorumBitmap());
        if (!operatorSetBitmap.isEmpty()) {
            // call the parent _forceDeregisterOperator function for operator sets quorums
            super._forceDeregisterOperator(operator, operatorSetBitmap.bitmapToBytesArray());
        }
    }

    /// @dev Hook to prevent any new quorums from being created if operator sets are not enabled
    function _beforeCreateQuorum(
        uint8
    ) internal virtual override {
        // If operator sets are not enabled, set the m2 quorum bitmap to the current m2 quorum bitmap
        // and enable operator sets
        if (!operatorSetsEnabled) {
            _m2QuorumBitmap = m2QuorumBitmap();
            operatorSetsEnabled = true;
        }
    }

    /// @dev Hook to allow for any post-deregister logic
    function _afterDeregisterOperator(
        address operator,
        bytes32,
        bytes memory,
        uint192 newBitmap
    ) internal virtual override {
        // Bitmap representing all quorums including M2 and OperatorSet quorums
        uint256 totalQuorumBitmap = _getTotalQuorumBitmap();
        // Bitmap representing only OperatorSet quorums. Equal to 0 if operatorSets not enabled
        uint256 operatorSetQuorumBitmap = totalQuorumBitmap.minus(m2QuorumBitmap());
        // Operators updated M2 quorum bitmap, clear all the bits of operatorSetQuorumBitmap which gives the
        // operator's M2 quorum bitmap.
        uint256 operatorM2QuorumBitmap = newBitmap.minus(operatorSetQuorumBitmap);
        // If the operator is no longer registered for any M2 quorums, update their status and deregister
        // them from the AVS via the EigenLayer core contracts
        if (operatorM2QuorumBitmap.isEmpty()) {
            serviceManager.deregisterOperatorFromAVS(operator);
        }
    }

    /**
     * @dev Helper function to update operator stakes and deregister loiterers
     * Loiterers are AVS registered operators who have force deregistered from the OperatorSet/quorum
     * in the core EigenLayer contract AllocationManager but not deregistered from the OperatorSet/quorum
     * in this contract. Potentially due to out of gas errors in the deregistration callback. This function
     * will handle that edge case by deregistering the operator from the AVS if they are no longer registered
     * in the AllocationManager.
     */
    function _updateStakesAndDeregisterLoiterers(
        address[] memory operators,
        bytes32[] memory operatorIds,
        uint8 quorumNumber
    ) internal virtual override {
        bytes memory singleQuorumNumber = new bytes(1);
        singleQuorumNumber[0] = bytes1(quorumNumber);
        bool[] memory doesNotMeetStakeThreshold =
            stakeRegistry.updateOperatorsStake(operators, operatorIds, quorumNumber);

        for (uint256 i = 0; i < operators.length; ++i) {
            if (doesNotMeetStakeThreshold[i]) {
                _ejectOperators(operators[i], singleQuorumNumber, false);
            }
        }
    }

    /// @notice Return bitmap representing all quorums(Legacy M2 and OperatorSet) quorums
    function _getTotalQuorumBitmap() internal view returns (uint256) {
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
        return m2QuorumBitmap().isSet(quorumNumber);
    }

    /**
     *
     *                            VIEW FUNCTIONS
     *
     */

    /// @dev Returns a bitmap with all bits set up to `quorumCount`. Used for bit-masking quorum numbers
    /// and differentiating between operator sets and M2 quorums
    function m2QuorumBitmap() public view returns (uint256) {
        // If operator sets are enabled, return the current m2 quorum bitmap
        if (operatorSetsEnabled) {
            return _m2QuorumBitmap;
        }

        return _getTotalQuorumBitmap();
    }

    /// @notice Returns true if the quorum number is an M2 quorum
    function isM2Quorum(
        uint8 quorumNumber
    ) external view returns (bool) {
        return _isM2Quorum(quorumNumber);
    }
}
