// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {ISignatureUtilsMixin} from
    "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {
    IAllocationManager,
    OperatorSet,
    IAllocationManagerTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {ISemVerMixin} from "eigenlayer-contracts/src/contracts/interfaces/ISemVerMixin.sol";
import {AllocationManager} from "eigenlayer-contracts/src/contracts/core/AllocationManager.sol";
import {SemVerMixin} from "eigenlayer-contracts/src/contracts/mixins/SemVerMixin.sol";

import {IBLSApkRegistry, IBLSApkRegistryTypes} from "./interfaces/IBLSApkRegistry.sol";
import {IStakeRegistry, IStakeRegistryTypes} from "./interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "./interfaces/IIndexRegistry.sol";
import {ISlashingRegistryCoordinator} from "./interfaces/ISlashingRegistryCoordinator.sol";
import {ISocketRegistry} from "./interfaces/ISocketRegistry.sol";

import {BitmapUtils} from "./libraries/BitmapUtils.sol";
import {BN254} from "./libraries/BN254.sol";
import {SignatureCheckerLib} from "./libraries/SignatureCheckerLib.sol";
import {QuorumBitmapHistoryLib} from "./libraries/QuorumBitmapHistoryLib.sol";

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {EIP712Upgradeable} from
    "@openzeppelin-upgrades/contracts/utils/cryptography/EIP712Upgradeable.sol";

import {Pausable} from "eigenlayer-contracts/src/contracts/permissions/Pausable.sol";
import {SlashingRegistryCoordinatorStorage} from "./SlashingRegistryCoordinatorStorage.sol";

/**
 * @title A `RegistryCoordinator` that has four registries:
 *      1) a `StakeRegistry` that keeps track of operators' stakes
 *      2) a `BLSApkRegistry` that keeps track of operators' BLS public keys and aggregate BLS public keys for each quorum
 *      3) an `IndexRegistry` that keeps track of an ordered list of operators for each quorum
 *      4) a `SocketRegistry` that keeps track of operators' sockets (arbitrary strings)
 *
 * @author Layr Labs, Inc.
 */
contract SlashingRegistryCoordinator is
    SlashingRegistryCoordinatorStorage,
    Initializable,
    SemVerMixin,
    Pausable,
    OwnableUpgradeable,
    EIP712Upgradeable,
    ISignatureUtilsMixin
{
    using BitmapUtils for *;
    using BN254 for BN254.G1Point;

    modifier onlyAllocationManager() {
        _checkAllocationManager();
        _;
    }

    modifier onlyEjector() {
        _checkEjector();
        _;
    }

    /// @dev Checks that `quorumNumber` corresponds to a quorum that has been created
    /// via `initialize` or `createQuorum`
    modifier quorumExists(
        uint8 quorumNumber
    ) {
        _checkQuorumExists(quorumNumber);
        _;
    }

    constructor(
        IStakeRegistry _stakeRegistry,
        IBLSApkRegistry _blsApkRegistry,
        IIndexRegistry _indexRegistry,
        ISocketRegistry _socketRegistry,
        IAllocationManager _allocationManager,
        IPauserRegistry _pauserRegistry,
        string memory _version
    )
        SlashingRegistryCoordinatorStorage(
            _stakeRegistry,
            _blsApkRegistry,
            _indexRegistry,
            _socketRegistry,
            _allocationManager
        )
        SemVerMixin(_version)
        Pausable(_pauserRegistry)
    {
        _disableInitializers();
    }

    /**
     *
     *                         EXTERNAL FUNCTIONS
     *
     */
    function initialize(
        address initialOwner,
        address churnApprover,
        address ejector,
        uint256 initialPausedStatus,
        address avs
    ) external initializer {
        __EIP712_init("AVSRegistryCoordinator", "v0.0.1");
        _transferOwnership(initialOwner);
        _setChurnApprover(churnApprover);
        _setPausedStatus(initialPausedStatus);
        _setEjector(ejector);
        _setAVS(avs);
    }

    /// @inheritdoc ISlashingRegistryCoordinator
    function createTotalDelegatedStakeQuorum(
        OperatorSetParam memory operatorSetParams,
        uint96 minimumStake,
        IStakeRegistryTypes.StrategyParams[] memory strategyParams
    ) external virtual onlyOwner {
        _createQuorum(
            operatorSetParams,
            minimumStake,
            strategyParams,
            IStakeRegistryTypes.StakeType.TOTAL_DELEGATED,
            0
        );
    }

    /// @inheritdoc ISlashingRegistryCoordinator
    function createSlashableStakeQuorum(
        OperatorSetParam memory operatorSetParams,
        uint96 minimumStake,
        IStakeRegistryTypes.StrategyParams[] memory strategyParams,
        uint32 lookAheadPeriod
    ) external virtual onlyOwner {
        _createQuorum(
            operatorSetParams,
            minimumStake,
            strategyParams,
            IStakeRegistryTypes.StakeType.TOTAL_SLASHABLE,
            lookAheadPeriod
        );
    }

    /// @inheritdoc IAVSRegistrar
    function registerOperator(
        address operator,
        address avs,
        uint32[] memory operatorSetIds,
        bytes calldata data
    ) external override onlyAllocationManager onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) {
        require(supportsAVS(avs), InvalidAVS());
        bytes memory quorumNumbers = _getQuorumNumbers(operatorSetIds);

        (
            RegistrationType registrationType,
            string memory socket,
            IBLSApkRegistryTypes.PubkeyRegistrationParams memory params
        ) = abi.decode(
            data, (RegistrationType, string, IBLSApkRegistryTypes.PubkeyRegistrationParams)
        );

        /**
         * If the operator has NEVER registered a pubkey before, use `params` to register
         * their pubkey in blsApkRegistry
         *
         * If the operator HAS registered a pubkey, `params` is ignored and the pubkey hash
         * (operatorId) is fetched instead
         */
        bytes32 operatorId = _getOrCreateOperatorId(operator, params);

        if (registrationType == RegistrationType.NORMAL) {
            uint32[] memory numOperatorsPerQuorum = _registerOperator({
                operator: operator,
                operatorId: operatorId,
                quorumNumbers: quorumNumbers,
                socket: socket,
                checkMaxOperatorCount: true
            }).numOperatorsPerQuorum;

            // For each quorum, validate that the new operator count does not exceed the maximum
            // (If it does, an operator needs to be replaced -- see `registerOperatorWithChurn`)
            for (uint256 i = 0; i < quorumNumbers.length; i++) {
                uint8 quorumNumber = uint8(quorumNumbers[i]);

                require(
                    numOperatorsPerQuorum[i] <= _quorumParams[quorumNumber].maxOperatorCount,
                    MaxOperatorCountReached()
                );
            }
        } else if (registrationType == RegistrationType.CHURN) {
            // Decode registration data from bytes
            (
                ,
                ,
                ,
                OperatorKickParam[] memory operatorKickParams,
                SignatureWithSaltAndExpiry memory churnApproverSignature
            ) = abi.decode(
                data,
                (
                    RegistrationType,
                    string,
                    IBLSApkRegistryTypes.PubkeyRegistrationParams,
                    OperatorKickParam[],
                    SignatureWithSaltAndExpiry
                )
            );
            _registerOperatorWithChurn({
                operator: operator,
                operatorId: operatorId,
                quorumNumbers: quorumNumbers,
                socket: socket,
                operatorKickParams: operatorKickParams,
                churnApproverSignature: churnApproverSignature
            });
        } else {
            revert InvalidRegistrationType();
        }
    }

    /// @inheritdoc IAVSRegistrar
    function deregisterOperator(
        address operator,
        address avs,
        uint32[] memory operatorSetIds
    ) external override onlyAllocationManager onlyWhenNotPaused(PAUSED_DEREGISTER_OPERATOR) {
        require(supportsAVS(avs), InvalidAVS());
        bytes memory quorumNumbers = _getQuorumNumbers(operatorSetIds);
        _deregisterOperator({operator: operator, quorumNumbers: quorumNumbers});
    }

    /// @inheritdoc ISlashingRegistryCoordinator
    function updateOperators(
        address[] memory operators
    ) external override onlyWhenNotPaused(PAUSED_UPDATE_OPERATOR) {
        for (uint256 i = 0; i < operators.length; i++) {
            // create single-element arrays for the operator and operatorId
            address[] memory singleOperator = new address[](1);
            singleOperator[0] = operators[i];
            bytes32[] memory singleOperatorId = new bytes32[](1);
            singleOperatorId[0] = _operatorInfo[operators[i]].operatorId;

            uint192 currentBitmap = _currentOperatorBitmap(singleOperatorId[0]);
            bytes memory quorumNumbers = currentBitmap.bitmapToBytesArray();
            for (uint256 j = 0; j < quorumNumbers.length; j++) {
                // update the operator's stake for each quorum
                _updateOperatorsStakes(singleOperator, singleOperatorId, uint8(quorumNumbers[j]));
            }
        }
    }

    /// @inheritdoc ISlashingRegistryCoordinator
    function updateOperatorsForQuorum(
        address[][] memory operatorsPerQuorum,
        bytes calldata quorumNumbers
    ) external onlyWhenNotPaused(PAUSED_UPDATE_OPERATOR) {
        // Input validation
        // - all quorums should exist (checked against `quorumCount` in orderedBytesArrayToBitmap)
        // - there should be no duplicates in `quorumNumbers`
        // - there should be one list of operators per quorum
        BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers, quorumCount);
        require(operatorsPerQuorum.length == quorumNumbers.length, InputLengthMismatch());

        // For each quorum, update ALL registered operators
        for (uint256 i = 0; i < quorumNumbers.length; ++i) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);

            // Ensure we've passed in the correct number of operators for this quorum
            address[] memory currQuorumOperators = operatorsPerQuorum[i];
            require(
                currQuorumOperators.length == indexRegistry.totalOperatorsForQuorum(quorumNumber),
                QuorumOperatorCountMismatch()
            );

            bytes32[] memory operatorIds = new bytes32[](currQuorumOperators.length);
            address prevOperatorAddress = address(0);
            // For each operator:
            // - check that they are registered for this quorum
            // - check that their address is strictly greater than the last operator
            // ... then, update their stakes
            for (uint256 j = 0; j < currQuorumOperators.length; ++j) {
                address operator = currQuorumOperators[j];

                operatorIds[j] = _operatorInfo[operator].operatorId;
                {
                    uint192 currentBitmap = _currentOperatorBitmap(operatorIds[j]);
                    // Check that the operator is registered
                    require(
                        BitmapUtils.isSet(currentBitmap, quorumNumber), NotRegisteredForQuorum()
                    );
                    // Prevent duplicate operators
                    require(operator > prevOperatorAddress, NotSorted());
                }

                prevOperatorAddress = operator;
            }

            _updateOperatorsStakes(currQuorumOperators, operatorIds, quorumNumber);

            // Update timestamp that all operators in quorum have been updated all at once
            quorumUpdateBlockNumber[quorumNumber] = block.number;
            emit QuorumBlockNumberUpdated(quorumNumber, block.number);
        }
    }

    /// @inheritdoc ISlashingRegistryCoordinator
    function updateSocket(
        string memory socket
    ) external {
        require(_operatorInfo[msg.sender].status == OperatorStatus.REGISTERED, NotRegistered());
        _setOperatorSocket(_operatorInfo[msg.sender].operatorId, socket);
    }

    /**
     *
     *                         EXTERNAL FUNCTIONS - EJECTOR
     *
     */

    /// @inheritdoc ISlashingRegistryCoordinator
    function ejectOperator(
        address operator,
        bytes memory quorumNumbers
    ) public virtual onlyEjector {
        lastEjectionTimestamp[operator] = block.timestamp;
        _kickOperator(operator, quorumNumbers);
    }

    /**
     *
     *                         EXTERNAL FUNCTIONS - OWNER
     *
     */

    /// @inheritdoc ISlashingRegistryCoordinator
    function setOperatorSetParams(
        uint8 quorumNumber,
        OperatorSetParam memory operatorSetParams
    ) external onlyOwner quorumExists(quorumNumber) {
        _setOperatorSetParams(quorumNumber, operatorSetParams);
    }

    /**
     * @notice Sets the churnApprover, which approves operator registration with churn
     * (see `registerOperatorWithChurn`)
     * @param _churnApprover the new churn approver
     * @dev only callable by the owner
     */
    function setChurnApprover(
        address _churnApprover
    ) external onlyOwner {
        _setChurnApprover(_churnApprover);
    }

    /// @inheritdoc ISlashingRegistryCoordinator
    function setEjector(
        address _ejector
    ) external onlyOwner {
        _setEjector(_ejector);
    }

    /// @inheritdoc ISlashingRegistryCoordinator
    function setAVS(
        address _avs
    ) external onlyOwner {
        _setAVS(_avs);
    }

    /// @inheritdoc ISlashingRegistryCoordinator
    function setEjectionCooldown(
        uint256 _ejectionCooldown
    ) external onlyOwner {
        uint256 prevEjectionCooldown = ejectionCooldown;
        ejectionCooldown = _ejectionCooldown;
        emit EjectionCooldownUpdated(prevEjectionCooldown, _ejectionCooldown);
    }

    /**
     *
     *                         INTERNAL FUNCTIONS
     *
     */

    /**
     * @notice Internal function to handle operator ejection logic
     * @param operator The operator to force deregister from the avs
     * @param quorumNumbers The quorum numbers to eject the operator from
     */
    function _kickOperator(address operator, bytes memory quorumNumbers) internal virtual {
        OperatorInfo storage operatorInfo = _operatorInfo[operator];
        // Only proceed if operator is currently registered
        require(operatorInfo.status == OperatorStatus.REGISTERED, OperatorNotRegistered());

        bytes32 operatorId = operatorInfo.operatorId;
        uint192 quorumsToRemove =
            uint192(BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers, quorumCount));
        uint192 currentBitmap = _currentOperatorBitmap(operatorId);

        // Check if operator is registered for all quorums we're trying to remove them from
        if (quorumsToRemove.isSubsetOf(currentBitmap)) {
            _forceDeregisterOperator(operator, quorumNumbers);
        }
    }

    /**
     * @notice Register the operator for one or more quorums. This method updates the
     * operator's quorum bitmap, socket, and status, then registers them with each registry.
     */
    function _registerOperator(
        address operator,
        bytes32 operatorId,
        bytes memory quorumNumbers,
        string memory socket,
        bool checkMaxOperatorCount
    ) internal virtual returns (RegisterResults memory results) {
        /**
         * Get bitmap of quorums to register for and operator's current bitmap. Validate that:
         * - we're trying to register for at least 1 quorum
         * - the quorums we're registering for exist (checked against `quorumCount` in orderedBytesArrayToBitmap)
         * - the operator is not currently registered for any quorums we're registering for
         * Then, calculate the operator's new bitmap after registration
         */
        uint192 quorumsToAdd =
            uint192(BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers, quorumCount));
        uint192 currentBitmap = _currentOperatorBitmap(operatorId);

        // call hook to allow for any pre-register logic
        _beforeRegisterOperator(operator, operatorId, quorumNumbers, currentBitmap);

        require(!quorumsToAdd.isEmpty(), BitmapEmpty());
        require(quorumsToAdd.noBitsInCommon(currentBitmap), AlreadyRegisteredForQuorums());
        uint192 newBitmap = uint192(currentBitmap.plus(quorumsToAdd));

        // Check that the operator can reregister if ejected
        require(
            lastEjectionTimestamp[operator] + ejectionCooldown < block.timestamp,
            CannotReregisterYet()
        );

        /**
         * Update operator's bitmap, socket, and status. Only update operatorInfo if needed:
         * if we're `REGISTERED`, the operatorId and status are already correct.
         */
        _updateOperatorBitmap({operatorId: operatorId, newBitmap: newBitmap});

        _setOperatorSocket(operatorId, socket);

        // If the operator wasn't registered for any quorums, update their status
        // and register them with this AVS in EigenLayer core (DelegationManager)
        if (_operatorInfo[operator].status != OperatorStatus.REGISTERED) {
            _operatorInfo[operator] = OperatorInfo(operatorId, OperatorStatus.REGISTERED);
            emit OperatorRegistered(operator, operatorId);
        }

        // Register the operator with the BLSApkRegistry, StakeRegistry, and IndexRegistry
        blsApkRegistry.registerOperator(operator, quorumNumbers);
        (results.operatorStakes, results.totalStakes) =
            stakeRegistry.registerOperator(operator, operatorId, quorumNumbers);
        results.numOperatorsPerQuorum = indexRegistry.registerOperator(operatorId, quorumNumbers);

        if (checkMaxOperatorCount) {
            for (uint256 i = 0; i < quorumNumbers.length; i++) {
                OperatorSetParam memory operatorSetParams = _quorumParams[uint8(quorumNumbers[i])];
                require(
                    results.numOperatorsPerQuorum[i] <= operatorSetParams.maxOperatorCount,
                    MaxOperatorCountReached()
                );
            }
        }

        // call hook to allow for any post-register logic
        _afterRegisterOperator(operator, operatorId, quorumNumbers, newBitmap);

        return results;
    }

    function _registerOperatorWithChurn(
        address operator,
        bytes32 operatorId,
        bytes memory quorumNumbers,
        string memory socket,
        OperatorKickParam[] memory operatorKickParams,
        SignatureWithSaltAndExpiry memory churnApproverSignature
    ) internal virtual {
        require(operatorKickParams.length == quorumNumbers.length, InputLengthMismatch());

        // Verify the churn approver's signature for the registering operator and kick params
        _verifyChurnApproverSignature({
            registeringOperator: operator,
            registeringOperatorId: operatorId,
            operatorKickParams: operatorKickParams,
            churnApproverSignature: churnApproverSignature
        });

        // Register the operator in each of the registry contracts and update the operator's
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
                _kickOperator(operatorKickParams[i].operator, singleQuorumNumber);
            }
        }
    }

    /**
     * @dev Deregister the operator from one or more quorums
     * This method updates the operator's quorum bitmap and status, then deregisters
     * the operator with the BLSApkRegistry, IndexRegistry, and StakeRegistry
     * @param operator the operator to deregister
     * @param quorumNumbers the quorum numbers to deregister from
     * the core EigenLayer contract AllocationManager
     */
    function _deregisterOperator(address operator, bytes memory quorumNumbers) internal virtual {
        // Fetch the operator's info and ensure they are registered
        OperatorInfo storage operatorInfo = _operatorInfo[operator];
        bytes32 operatorId = operatorInfo.operatorId;
        uint192 currentBitmap = _currentOperatorBitmap(operatorId);

        // call hook to allow for any pre-deregister logic
        _beforeDeregisterOperator(operator, operatorId, quorumNumbers, currentBitmap);

        require(operatorInfo.status == OperatorStatus.REGISTERED, NotRegistered());

        /**
         * Get bitmap of quorums to deregister from and operator's current bitmap. Validate that:
         * - we're trying to deregister from at least 1 quorum
         * - the quorums we're deregistering from exist (checked against `quorumCount` in orderedBytesArrayToBitmap)
         * - the operator is currently registered for any quorums we're trying to deregister from
         * Then, calculate the operator's new bitmap after deregistration
         */
        uint192 quorumsToRemove =
            uint192(BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers, quorumCount));
        require(!quorumsToRemove.isEmpty(), BitmapCannotBeZero());
        require(quorumsToRemove.isSubsetOf(currentBitmap), NotRegisteredForQuorum());
        uint192 newBitmap = uint192(currentBitmap.minus(quorumsToRemove));

        // Update operator's bitmap and status
        _updateOperatorBitmap({operatorId: operatorId, newBitmap: newBitmap});

        // If the operator is no longer registered for any quorums, update their status and deregister
        // them from the AVS via the EigenLayer core contracts
        if (newBitmap.isEmpty()) {
            _operatorInfo[operator].status = OperatorStatus.DEREGISTERED;
            emit OperatorDeregistered(operator, operatorId);
        }

        // Deregister operator with each of the registry contracts
        blsApkRegistry.deregisterOperator(operator, quorumNumbers);
        stakeRegistry.deregisterOperator(operatorId, quorumNumbers);
        indexRegistry.deregisterOperator(operatorId, quorumNumbers);

        // call hook to allow for any post-deregister logic
        _afterDeregisterOperator(operator, operatorId, quorumNumbers, newBitmap);
    }

    /**
     * @notice Helper function to handle operator set deregistration for OperatorSets quorums. This is used
     * when an operator is force-deregistered from a set of quorums.
     * Due to deregistration being possible in the AllocationManager but not in the AVS as a result of the
     * try/catch in `AllocationManager.deregisterFromOperatorSets`, we need to first check that the operator
     * is not already deregistered from the OperatorSet in the AllocationManager.
     * @param operator The operator to deregister
     * @param quorumNumbers The quorum numbers the operator is force-deregistered from
     */
    function _forceDeregisterOperator(
        address operator,
        bytes memory quorumNumbers
    ) internal virtual {
        allocationManager.deregisterFromOperatorSets(
            IAllocationManagerTypes.DeregisterParams({
                operator: operator,
                avs: avs,
                operatorSetIds: _getOperatorSetIds(quorumNumbers)
            })
        );
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
    ) internal virtual {
        bytes memory singleQuorumNumber = new bytes(1);
        singleQuorumNumber[0] = bytes1(quorumNumber);
        bool[] memory doesNotMeetStakeThreshold =
            stakeRegistry.updateOperatorsStake(operators, operatorIds, quorumNumber);
        for (uint256 j = 0; j < operators.length; ++j) {
            // If the operator does not have the minimum stake, they need to be force deregistered.
            if (doesNotMeetStakeThreshold[j]) {
                _kickOperator(operators[j], singleQuorumNumber);
            }
        }
    }

    /**
     * @notice Checks if the caller is the ejector
     * @dev Reverts if the caller is not the ejector
     */
    function _checkEjector() internal view {
        require(msg.sender == ejector, OnlyEjector());
    }

    function _checkAllocationManager() internal view {
        require(msg.sender == address(allocationManager), OnlyAllocationManager());
    }

    /**
     * @notice Checks if a quorum exists
     * @param quorumNumber The quorum number to check
     * @dev Reverts if the quorum does not exist
     */
    function _checkQuorumExists(
        uint8 quorumNumber
    ) internal view {
        require(quorumNumber < quorumCount, QuorumDoesNotExist());
    }

    /**
     * @notice Fetches an operator's pubkey hash from the BLSApkRegistry. If the
     * operator has not registered a pubkey, attempts to register a pubkey using
     * `params`
     * @param operator the operator whose pubkey to query from the BLSApkRegistry
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @dev `params` can be empty if the operator has already registered a pubkey in the BLSApkRegistry
     */
    function _getOrCreateOperatorId(
        address operator,
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params
    ) internal returns (bytes32 operatorId) {
        return blsApkRegistry.getOrRegisterOperatorId(
            operator, params, pubkeyRegistrationMessageHash(operator)
        );
    }

    /**
     * @notice Validates that an incoming operator is eligible to replace an existing
     * operator based on the stake of both
     * @dev In order to churn, the incoming operator needs to have more stake than the
     * existing operator by a proportion given by `kickBIPsOfOperatorStake`
     * @dev In order to be churned out, the existing operator needs to have a proportion
     * of the total quorum stake less than `kickBIPsOfTotalStake`
     * @param quorumNumber `newOperator` is trying to replace an operator in this quorum
     * @param totalQuorumStake the total stake of all operators in the quorum, after the
     * `newOperator` registers
     * @param newOperator the incoming operator
     * @param newOperatorStake the incoming operator's stake
     * @param kickParams the quorum number and existing operator to replace
     * @dev the existing operator's registration to this quorum isn't checked here, but
     * if we attempt to deregister them, this will be checked in `_deregisterOperator`
     * @param setParams config for this quorum containing `kickBIPsX` stake proportions
     * mentioned above
     */
    function _validateChurn(
        uint8 quorumNumber,
        uint96 totalQuorumStake,
        address newOperator,
        uint96 newOperatorStake,
        OperatorKickParam memory kickParams,
        OperatorSetParam memory setParams
    ) internal view {
        address operatorToKick = kickParams.operator;
        bytes32 idToKick = _operatorInfo[operatorToKick].operatorId;
        require(newOperator != operatorToKick, CannotChurnSelf());
        require(kickParams.quorumNumber == quorumNumber, QuorumOperatorCountMismatch());

        // Get the target operator's stake and check that it is below the kick thresholds
        uint96 operatorToKickStake = stakeRegistry.getCurrentStake(idToKick, quorumNumber);
        require(
            newOperatorStake > _individualKickThreshold(operatorToKickStake, setParams),
            InsufficientStakeForChurn()
        );
        require(
            operatorToKickStake < _totalKickThreshold(totalQuorumStake, setParams),
            CannotKickOperatorAboveThreshold()
        );
    }

    /**
     * @notice Returns the stake threshold required for an incoming operator to replace an existing operator
     * The incoming operator must have more stake than the return value.
     */
    function _individualKickThreshold(
        uint96 operatorStake,
        OperatorSetParam memory setParams
    ) internal pure returns (uint96) {
        return operatorStake * setParams.kickBIPsOfOperatorStake / BIPS_DENOMINATOR;
    }

    /**
     * @notice Returns the total stake threshold required for an operator to remain in a quorum.
     * The operator must have at least the returned stake amount to keep their position.
     */
    function _totalKickThreshold(
        uint96 totalStake,
        OperatorSetParam memory setParams
    ) internal pure returns (uint96) {
        return totalStake * setParams.kickBIPsOfTotalStake / BIPS_DENOMINATOR;
    }

    /**
     * @notice Updates an operator's socket address in the SocketRegistry
     * @param operatorId The unique identifier of the operator
     * @param socket The new socket address to set for the operator
     * @dev Emits an OperatorSocketUpdate event after updating
     */
    function _setOperatorSocket(bytes32 operatorId, string memory socket) internal {
        socketRegistry.setOperatorSocket(operatorId, socket);
        emit OperatorSocketUpdate(operatorId, socket);
    }

    /// @notice verifies churnApprover's signature on operator churn approval and increments the churnApprover nonce
    function _verifyChurnApproverSignature(
        address registeringOperator,
        bytes32 registeringOperatorId,
        OperatorKickParam[] memory operatorKickParams,
        SignatureWithSaltAndExpiry memory churnApproverSignature
    ) internal {
        // make sure the salt hasn't been used already
        require(!isChurnApproverSaltUsed[churnApproverSignature.salt], ChurnApproverSaltUsed());
        require(churnApproverSignature.expiry >= block.timestamp, SignatureExpired());

        // set salt used to true
        isChurnApproverSaltUsed[churnApproverSignature.salt] = true;

        // check the churnApprover's signature
        SignatureCheckerLib.isValidSignature(
            churnApprover,
            calculateOperatorChurnApprovalDigestHash(
                registeringOperator,
                registeringOperatorId,
                operatorKickParams,
                churnApproverSignature.salt,
                churnApproverSignature.expiry
            ),
            churnApproverSignature.signature
        );
    }

    /**
     * @notice Creates a quorum and initializes it in each registry contract
     * @param operatorSetParams configures the quorum's max operator count and churn parameters
     * @param minimumStake sets the minimum stake required for an operator to register or remain
     * registered
     * @param strategyParams a list of strategies and multipliers used by the StakeRegistry to
     * calculate an operator's stake weight for the quorum
     */
    function _createQuorum(
        OperatorSetParam memory operatorSetParams,
        uint96 minimumStake,
        IStakeRegistryTypes.StrategyParams[] memory strategyParams,
        IStakeRegistryTypes.StakeType stakeType,
        uint32 lookAheadPeriod
    ) internal {
        // The previous quorum count is the new quorum's number,
        // this is because quorum numbers begin from index 0.
        uint8 quorumNumber = quorumCount;

        // Hook to allow for any pre-create quorum logic
        _beforeCreateQuorum(quorumNumber);

        // Increment the total quorum count. Fails if we're already at the max
        require(quorumNumber < MAX_QUORUM_COUNT, MaxQuorumsReached());
        quorumCount += 1;

        // Initialize the quorum here and in each registry
        _setOperatorSetParams(quorumNumber, operatorSetParams);

        // Create array of CreateSetParams for the new quorum
        IAllocationManagerTypes.CreateSetParams[] memory createSetParams =
            new IAllocationManagerTypes.CreateSetParams[](1);

        // Extract strategies from strategyParams
        IStrategy[] memory strategies = new IStrategy[](strategyParams.length);
        for (uint256 i = 0; i < strategyParams.length; i++) {
            strategies[i] = strategyParams[i].strategy;
        }

        // Initialize CreateSetParams with quorumNumber as operatorSetId
        createSetParams[0] = IAllocationManagerTypes.CreateSetParams({
            operatorSetId: quorumNumber,
            strategies: strategies
        });
        allocationManager.createOperatorSets({avs: avs, params: createSetParams});

        // Initialize stake registry based on stake type
        if (stakeType == IStakeRegistryTypes.StakeType.TOTAL_DELEGATED) {
            stakeRegistry.initializeDelegatedStakeQuorum(quorumNumber, minimumStake, strategyParams);
        } else if (stakeType == IStakeRegistryTypes.StakeType.TOTAL_SLASHABLE) {
            // For slashable stake quorums, ensure lookAheadPeriod is less than DEALLOCATION_DELAY
            require(
                AllocationManager(address(allocationManager)).DEALLOCATION_DELAY() > lookAheadPeriod,
                LookAheadPeriodTooLong()
            );
            stakeRegistry.initializeSlashableStakeQuorum(
                quorumNumber, minimumStake, lookAheadPeriod, strategyParams
            );
        }

        indexRegistry.initializeQuorum(quorumNumber);
        blsApkRegistry.initializeQuorum(quorumNumber);

        emit QuorumCreated({
            quorumNumber: quorumNumber,
            operatorSetParams: operatorSetParams,
            minimumStake: minimumStake,
            strategyParams: strategyParams,
            stakeType: stakeType,
            lookAheadPeriod: lookAheadPeriod
        });

        // Hook to allow for any post-create quorum logic
        _afterCreateQuorum(quorumNumber);
    }

    /**
     * @notice Record an update to an operator's quorum bitmap.
     * @param newBitmap is the most up-to-date set of bitmaps the operator is registered for
     */
    function _updateOperatorBitmap(bytes32 operatorId, uint192 newBitmap) internal {
        QuorumBitmapHistoryLib.updateOperatorBitmap(_operatorBitmapHistory, operatorId, newBitmap);
    }

    /// @notice Get the most recent bitmap for the operator, returning an empty bitmap if
    /// the operator is not registered.
    function _currentOperatorBitmap(
        bytes32 operatorId
    ) internal view returns (uint192) {
        return QuorumBitmapHistoryLib.currentOperatorBitmap(_operatorBitmapHistory, operatorId);
    }

    /**
     * @notice Returns the index of the quorumBitmap for the provided `operatorId` at the given `blockNumber`
     * @dev Reverts if the operator had not yet (ever) registered at `blockNumber`
     * @dev This function is designed to find proper inputs to the `getQuorumBitmapAtBlockNumberByIndex` function
     */
    function _getQuorumBitmapIndexAtBlockNumber(
        uint32 blockNumber,
        bytes32 operatorId
    ) internal view returns (uint32 index) {
        return QuorumBitmapHistoryLib.getQuorumBitmapIndexAtBlockNumber(
            _operatorBitmapHistory, blockNumber, operatorId
        );
    }

    /// @notice Returns the quorum numbers for the provided `OperatorSetIds`
    /// OperatorSetIds are used in the AllocationManager to identify operator sets for a given AVS
    function _getQuorumNumbers(
        uint32[] memory operatorSetIds
    ) internal pure returns (bytes memory) {
        bytes memory quorumNumbers = new bytes(operatorSetIds.length);
        for (uint256 i = 0; i < operatorSetIds.length; i++) {
            quorumNumbers[i] = bytes1(uint8(operatorSetIds[i]));
        }
        return quorumNumbers;
    }

    function _getOperatorSetIds(
        bytes memory quorumNumbers
    ) internal pure returns (uint32[] memory) {
        uint32[] memory operatorSetIds = new uint32[](quorumNumbers.length);
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            operatorSetIds[i] = uint32(uint8(quorumNumbers[i]));
        }
        return operatorSetIds;
    }

    function _setOperatorSetParams(
        uint8 quorumNumber,
        OperatorSetParam memory operatorSetParams
    ) internal {
        _quorumParams[quorumNumber] = operatorSetParams;
        emit OperatorSetParamsUpdated(quorumNumber, operatorSetParams);
    }

    function _setChurnApprover(
        address newChurnApprover
    ) internal {
        emit ChurnApproverUpdated(churnApprover, newChurnApprover);
        churnApprover = newChurnApprover;
    }

    function _setEjector(
        address newEjector
    ) internal {
        emit EjectorUpdated(ejector, newEjector);
        ejector = newEjector;
    }

    function _setAVS(
        address _avs
    ) internal {
        address prevAVS = avs;
        emit AVSUpdated(prevAVS, _avs);
        avs = _avs;
    }

    /// @dev Hook to allow for any pre-create quorum logic
    function _beforeCreateQuorum(
        uint8 quorumNumber
    ) internal virtual {}

    /// @dev Hook to allow for any post-create quorum logic
    function _afterCreateQuorum(
        uint8 quorumNumber
    ) internal virtual {}

    /// @dev Hook to allow for any pre-register logic in `_registerOperator`
    function _beforeRegisterOperator(
        address operator,
        bytes32 operatorId,
        bytes memory quorumNumbers,
        uint192 currentBitmap
    ) internal virtual {}

    /// @dev Hook to allow for any post-register logic in `_registerOperator`
    function _afterRegisterOperator(
        address operator,
        bytes32 operatorId,
        bytes memory quorumNumbers,
        uint192 newBitmap
    ) internal virtual {}

    /// @dev Hook to allow for any pre-deregister logic in `_deregisterOperator`
    function _beforeDeregisterOperator(
        address operator,
        bytes32 operatorId,
        bytes memory quorumNumbers,
        uint192 currentBitmap
    ) internal virtual {}

    /// @dev Hook to allow for any post-deregister logic in `_deregisterOperator`
    function _afterDeregisterOperator(
        address operator,
        bytes32 operatorId,
        bytes memory quorumNumbers,
        uint192 newBitmap
    ) internal virtual {}

    /**
     *
     *                         VIEW FUNCTIONS
     *
     */

    /// @notice Returns the operator set params for the given `quorumNumber`
    function getOperatorSetParams(
        uint8 quorumNumber
    ) external view returns (OperatorSetParam memory) {
        return _quorumParams[quorumNumber];
    }

    /// @notice Returns the operator struct for the given `operator`
    function getOperator(
        address operator
    ) external view returns (OperatorInfo memory) {
        return _operatorInfo[operator];
    }

    /// @notice Returns the operatorId for the given `operator`
    function getOperatorId(
        address operator
    ) external view returns (bytes32) {
        return _operatorInfo[operator].operatorId;
    }

    /// @notice Returns the operator address for the given `operatorId`
    function getOperatorFromId(
        bytes32 operatorId
    ) external view returns (address) {
        return blsApkRegistry.getOperatorFromPubkeyHash(operatorId);
    }

    /// @notice Returns the status for the given `operator`
    function getOperatorStatus(
        address operator
    ) external view returns (ISlashingRegistryCoordinator.OperatorStatus) {
        return _operatorInfo[operator].status;
    }

    /**
     * @notice Returns the indices of the quorumBitmaps for the provided `operatorIds` at the given `blockNumber`
     * @dev Reverts if any of the `operatorIds` was not (yet) registered at `blockNumber`
     * @dev This function is designed to find proper inputs to the `getQuorumBitmapAtBlockNumberByIndex` function
     */
    function getQuorumBitmapIndicesAtBlockNumber(
        uint32 blockNumber,
        bytes32[] memory operatorIds
    ) external view returns (uint32[] memory) {
        return QuorumBitmapHistoryLib.getQuorumBitmapIndicesAtBlockNumber(
            _operatorBitmapHistory, blockNumber, operatorIds
        );
    }

    /**
     * @notice Returns the quorum bitmap for the given `operatorId` at the given `blockNumber` via the `index`,
     * reverting if `index` is incorrect
     * @dev This function is meant to be used in concert with `getQuorumBitmapIndicesAtBlockNumber`, which
     * helps off-chain processes to fetch the correct `index` input
     */
    function getQuorumBitmapAtBlockNumberByIndex(
        bytes32 operatorId,
        uint32 blockNumber,
        uint256 index
    ) external view returns (uint192) {
        return QuorumBitmapHistoryLib.getQuorumBitmapAtBlockNumberByIndex(
            _operatorBitmapHistory, operatorId, blockNumber, index
        );
    }

    /// @notice Returns the `index`th entry in the operator with `operatorId`'s bitmap history
    function getQuorumBitmapUpdateByIndex(
        bytes32 operatorId,
        uint256 index
    ) external view returns (QuorumBitmapUpdate memory) {
        return _operatorBitmapHistory[operatorId][index];
    }

    /// @notice Returns the current quorum bitmap for the given `operatorId` or 0 if the operator is not registered for any quorum
    function getCurrentQuorumBitmap(
        bytes32 operatorId
    ) external view returns (uint192) {
        return _currentOperatorBitmap(operatorId);
    }

    /// @notice Returns the length of the quorum bitmap history for the given `operatorId`
    function getQuorumBitmapHistoryLength(
        bytes32 operatorId
    ) external view returns (uint256) {
        return _operatorBitmapHistory[operatorId].length;
    }

    /**
     * @notice Public function for the the churnApprover signature hash calculation when operators are being kicked from quorums
     * @param registeringOperatorId The id of the registering operator
     * @param operatorKickParams The parameters needed to kick the operator from the quorums that have reached their caps
     * @param salt The salt to use for the churnApprover's signature
     * @param expiry The desired expiry time of the churnApprover's signature
     */
    function calculateOperatorChurnApprovalDigestHash(
        address registeringOperator,
        bytes32 registeringOperatorId,
        OperatorKickParam[] memory operatorKickParams,
        bytes32 salt,
        uint256 expiry
    ) public view returns (bytes32) {
        // calculate the digest hash
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    OPERATOR_CHURN_APPROVAL_TYPEHASH,
                    registeringOperator,
                    registeringOperatorId,
                    operatorKickParams,
                    salt,
                    expiry
                )
            )
        );
    }

    /**
     * @notice Returns the message hash that an operator must sign to register their BLS public key.
     * @param operator is the address of the operator registering their BLS public key
     */
    function pubkeyRegistrationMessageHash(
        address operator
    ) public view returns (BN254.G1Point memory) {
        return BN254.hashToG1(calculatePubkeyRegistrationMessageHash(operator));
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

    function supportsAVS(
        address _avs
    ) public view virtual returns (bool) {
        return _avs == address(avs);
    }

    /**
     * @notice Returns the domain separator used for EIP-712 signatures
     * @return The domain separator
     */
    function domainSeparator() external view virtual override returns (bytes32) {
        return _domainSeparatorV4();
    }
}
