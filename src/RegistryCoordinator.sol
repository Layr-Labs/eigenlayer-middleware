// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {
    IAllocationManager,
    OperatorSet
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {ISignatureUtilsMixin} from
    "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {ISemVerMixin} from "eigenlayer-contracts/src/contracts/interfaces/ISemVerMixin.sol";
import {SemVerMixin} from "eigenlayer-contracts/src/contracts/mixins/SemVerMixin.sol";
import {IBLSApkRegistry, IBLSApkRegistryTypes} from "./interfaces/IBLSApkRegistry.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "./interfaces/IIndexRegistry.sol";
import {IServiceManager} from "./interfaces/IServiceManager.sol";
import {
    IRegistryCoordinator, IRegistryCoordinatorTypes
} from "./interfaces/IRegistryCoordinator.sol";
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
contract RegistryCoordinator is RegistryCoordinatorStorage, SlashingRegistryCoordinator {
    using BitmapUtils for *;

    constructor(
        IRegistryCoordinatorTypes.RegistryCoordinatorParams memory params
    )
        RegistryCoordinatorStorage(params.serviceManager)
        SlashingRegistryCoordinator(
            params.slashingParams.stakeRegistry,
            params.slashingParams.blsApkRegistry,
            params.slashingParams.indexRegistry,
            params.slashingParams.socketRegistry,
            params.slashingParams.allocationManager,
            params.slashingParams.pauserRegistry,
            "v0.0.1"
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

        _deregisterOperator({operator: msg.sender, quorumNumbers: quorumNumbers});
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

    /// @dev override the _kickOperator function to handle M2 quorum forced deregistration
    function _kickOperator(
        address operator,
        bytes memory quorumNumbers
    ) internal virtual override {
        OperatorInfo storage operatorInfo = _operatorInfo[operator];
        uint192 quorumsToRemove =
            uint192(BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers, quorumCount));
        if (operatorInfo.status == OperatorStatus.REGISTERED && !quorumsToRemove.isEmpty()) {
            // Allocate memory once outside the loop
            bytes memory singleQuorumNumber = new bytes(1);
            // For each quorum number, check if it's an M2 quorum
            for (uint256 i = 0; i < quorumNumbers.length; i++) {
                singleQuorumNumber[0] = quorumNumbers[i];

                if (isM2Quorum(uint8(quorumNumbers[i]))) {
                    // For M2 quorums, use _deregisterOperator
                    _deregisterOperator({operator: operator, quorumNumbers: singleQuorumNumber});
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
            _enableOperatorSets();
        }
    }

    /// @dev Internal function to enable operator sets and set the M2 quorum bitmap
    function _enableOperatorSets() internal {
        require(!operatorSetsEnabled, OperatorSetsAlreadyEnabled());
        _m2QuorumBitmap = _getTotalQuorumBitmap();
        operatorSetsEnabled = true;
        emit OperatorSetsEnabled();
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
     * @dev Helper function to update operator stakes and deregister operators with insufficient stake
     * This function handles two cases:
     * 1. Operators who no longer meet the minimum stake requirement for a quorum
     * 2. Operators who have been force-deregistered from the AllocationManager but not from this contract
     * (e.g. due to out of gas errors in the deregistration callback)
     * @param operators The list of operators to check and update
     * @param operatorIds The corresponding operator IDs
     * @param quorumNumber The quorum number to check stakes for
     */
    function _updateOperatorsStakes(
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
                _kickOperator(operators[i], singleQuorumNumber);
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
    ) public view returns (bool) {
        return m2QuorumBitmap().isSet(quorumNumber);
    }

    /**
     * @notice Returns the domain separator used for EIP-712 signatures
     * @return The domain separator
     */
    function domainSeparator() external view virtual override returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice Returns the version of the contract
     * @return The version string
     */
    function version()
        public
        view
        virtual
        override(ISemVerMixin, SemVerMixin)
        returns (string memory)
    {
        return "v0.0.1";
    }
}
