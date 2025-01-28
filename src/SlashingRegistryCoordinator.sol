// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {
    IAllocationManager,
    OperatorSet,
    IAllocationManagerTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

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
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

import {Pausable} from "eigenlayer-contracts/src/contracts/permissions/Pausable.sol";
import {SlashingRegistryCoordinatorStorage} from "./SlashingRegistryCoordinatorStorage.sol";

/**
 * @title A `RegistryCoordinator` that has three registries:
 *      1) a `StakeRegistry` that keeps track of operators' stakes
 *      2) a `BLSApkRegistry` that keeps track of operators' BLS public keys and aggregate BLS public keys for each quorum
 *      3) an `IndexRegistry` that keeps track of an ordered list of operators for each quorum
 *
 * @author Layr Labs, Inc.
 */
contract SlashingRegistryCoordinator is
    EIP712,
    Initializable,
    Pausable,
    OwnableUpgradeable,
    SlashingRegistryCoordinatorStorage,
    ISignatureUtils
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
        IPauserRegistry _pauserRegistry
    )
        SlashingRegistryCoordinatorStorage(
            _stakeRegistry,
            _blsApkRegistry,
            _indexRegistry,
            _socketRegistry,
            _allocationManager
        )
        EIP712("AVSRegistryCoordinator", "v0.0.1")
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
        address _initialOwner,
        address _churnApprover,
        address _ejector,
        uint256 _initialPausedStatus,
        address _accountIdentifier
    ) external initializer {
        _transferOwnership(_initialOwner);
        _setChurnApprover(_churnApprover);
        _setPausedStatus(_initialPausedStatus);
        _setEjector(_ejector);
        _setAccountIdentifier(_accountIdentifier);
        // Add registry contracts to the registries array
        registries.push(address(stakeRegistry));
        registries.push(address(blsApkRegistry));
        registries.push(address(indexRegistry));

        // Set the AVS to be OperatorSets compatible
        operatorSetsEnabled = true;

        // Set the AVS to not accept M2 quorums
        m2QuorumsDisabled = true;
    }

    /**
     * @notice Creates a quorum and initializes it in each registry contract
     * @param operatorSetParams configures the quorum's max operator count and churn parameters
     * @param minimumStake sets the minimum stake required for an operator to register or remain
     * registered
     * @param strategyParams a list of strategies and multipliers used by the StakeRegistry to
     * calculate an operator's stake weight for the quorum
     *  @dev For m2 AVS this function has the same behavior as createQuorum before
     *       For migrated AVS that enable operator sets this will create a quorum that measures total delegated stake for operator set
     *
     */
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

    function createSlashableStakeQuorum(
        OperatorSetParam memory operatorSetParams,
        uint96 minimumStake,
        IStakeRegistryTypes.StrategyParams[] memory strategyParams,
        uint32 lookAheadPeriod
    ) external virtual onlyOwner {
        require(operatorSetsEnabled, OperatorSetsNotEnabled());
        _createQuorum(
            operatorSetParams,
            minimumStake,
            strategyParams,
            IStakeRegistryTypes.StakeType.TOTAL_SLASHABLE,
            lookAheadPeriod
        );
    }

    function registerOperator(
        address operator,
        uint32[] memory operatorSetIds,
        bytes calldata data
    ) external override onlyAllocationManager onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) {
        require(operatorSetsEnabled, OperatorSetsNotEnabled());
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

        // If the operator wasn't registered for any quorums, update their status
        // and register them with this AVS in EigenLayer core (DelegationManager)
        if (_operatorInfo[operator].status != OperatorStatus.REGISTERED) {
            _operatorInfo[operator] = OperatorInfo(operatorId, OperatorStatus.REGISTERED);
            emit OperatorRegistered(operator, operatorId);
        }
    }

    function deregisterOperator(
        address operator,
        uint32[] memory operatorSetIds
    ) external override onlyAllocationManager onlyWhenNotPaused(PAUSED_DEREGISTER_OPERATOR) {
        require(operatorSetsEnabled, OperatorSetsNotEnabled());
        bytes memory quorumNumbers = _getQuorumNumbers(operatorSetIds);
        _deregisterOperator(operator, quorumNumbers);
    }

    /**
     * @notice Updates the StakeRegistry's view of one or more operators' stakes. If any operator
     * is found to be below the minimum stake for the quorum, they are deregistered.
     * @dev stakes are queried from the Eigenlayer core DelegationManager contract
     * @param operators a list of operator addresses to update
     */
    function updateOperators(
        address[] memory operators
    ) external onlyWhenNotPaused(PAUSED_UPDATE_OPERATOR) {
        for (uint256 i = 0; i < operators.length; i++) {
            address operator = operators[i];
            OperatorInfo memory operatorInfo = _operatorInfo[operator];
            bytes32 operatorId = operatorInfo.operatorId;

            // Update the operator's stake for their active quorums
            uint192 currentBitmap = _currentOperatorBitmap(operatorId);
            bytes memory quorumsToUpdate = BitmapUtils.bitmapToBytesArray(currentBitmap);
            _updateOperator(operator, operatorInfo, quorumsToUpdate);
        }
    }

    /**
     * @notice For each quorum in `quorumNumbers`, updates the StakeRegistry's view of ALL its registered operators' stakes.
     * Each quorum's `quorumUpdateBlockNumber` is also updated, which tracks the most recent block number when ALL registered
     * operators were updated.
     * @dev stakes are queried from the Eigenlayer core DelegationManager contract
     * @param operatorsPerQuorum for each quorum in `quorumNumbers`, this has a corresponding list of operators to update.
     * @dev Each list of operator addresses MUST be sorted in ascending order
     * @dev Each list of operator addresses MUST represent the entire list of registered operators for the corresponding quorum
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being updated
     * @dev invariant: Each list of `operatorsPerQuorum` MUST be a sorted version of `IndexRegistry.getOperatorListAtBlockNumber`
     * for the corresponding quorum.
     * @dev note on race condition: if an operator registers/deregisters for any quorum in `quorumNumbers` after a txn to
     * this method is broadcast (but before it is executed), the method will fail
     */
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

            address prevOperatorAddress = address(0);
            // For each operator:
            // - check that they are registered for this quorum
            // - check that their address is strictly greater than the last operator
            // ... then, update their stakes
            for (uint256 j = 0; j < currQuorumOperators.length; ++j) {
                address operator = currQuorumOperators[j];

                OperatorInfo memory operatorInfo = _operatorInfo[operator];
                bytes32 operatorId = operatorInfo.operatorId;

                {
                    uint192 currentBitmap = _currentOperatorBitmap(operatorId);
                    // Check that the operator is registered
                    require(
                        BitmapUtils.isSet(currentBitmap, quorumNumber), NotRegisteredForQuorum()
                    );
                    // Prevent duplicate operators
                    require(operator > prevOperatorAddress, NotSorted());
                }

                // Update the operator
                _updateOperator(operator, operatorInfo, quorumNumbers[i:i + 1]);
                prevOperatorAddress = operator;
            }

            // Update timestamp that all operators in quorum have been updated all at once
            quorumUpdateBlockNumber[quorumNumber] = block.number;
            emit QuorumBlockNumberUpdated(quorumNumber, block.number);
        }
    }

    /**
     * @notice Updates the socket of the msg.sender given they are a registered operator
     * @param socket is the new socket of the operator
     */
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

    /**
     * @notice Forcibly deregisters an operator from one or more quorums
     * @param operator the operator to eject
     * @param quorumNumbers the quorum numbers to eject the operator from
     * @dev possible race condition if prior to being ejected for a set of quorums the operator self deregisters from a subset
     */
    function ejectOperator(address operator, bytes memory quorumNumbers) external onlyEjector {
        lastEjectionTimestamp[operator] = block.timestamp;

        OperatorInfo storage operatorInfo = _operatorInfo[operator];
        bytes32 operatorId = operatorInfo.operatorId;
        uint192 quorumsToRemove =
            uint192(BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers, quorumCount));
        uint192 currentBitmap = _currentOperatorBitmap(operatorId);
        if (
            operatorInfo.status == OperatorStatus.REGISTERED && !quorumsToRemove.isEmpty()
                && quorumsToRemove.isSubsetOf(currentBitmap)
        ) {
            _deregisterOperator({operator: operator, quorumNumbers: quorumNumbers});

            if (operatorSetsEnabled) {
                _forceDeregisterOperator(operator, quorumNumbers);
            }
        }
    }

    /**
     *
     *                         EXTERNAL FUNCTIONS - OWNER
     *
     */

    /**
     * @notice Updates an existing quorum's configuration with a new max operator count
     * and operator churn parameters
     * @param quorumNumber the quorum number to update
     * @param operatorSetParams the new config
     * @dev only callable by the owner
     */
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

    /**
     * @notice Sets the ejector, which can force-deregister operators from quorums
     * @param _ejector the new ejector
     * @dev only callable by the owner
     */
    function setEjector(
        address _ejector
    ) external onlyOwner {
        _setEjector(_ejector);
    }

    /**
     * @notice Sets the account identifier for this AVS (used for UAM integration in EigenLayer)
     * @param _accountIdentifier the new account identifier
     * @dev only callable by the owner
     */
    function setAccountIdentifier(
        address _accountIdentifier
    ) external onlyOwner {
        _setAccountIdentifier(_accountIdentifier);
    }

    /**
     * @notice Sets the ejection cooldown, which is the time an operator must wait in
     * seconds afer ejection before registering for any quorum
     * @param _ejectionCooldown the new ejection cooldown in seconds
     * @dev only callable by the owner
     */
    function setEjectionCooldown(
        uint256 _ejectionCooldown
    ) external onlyOwner {
        ejectionCooldown = _ejectionCooldown;
    }

    /**
     *
     *                         INTERNAL FUNCTIONS
     *
     */

    /**
     * @notice Register the operator for one or more quorums. This method updates the
     * operator's quorum bitmap, socket, and status, then registers them with each registry.
     */
    function _registerOperator(
        address operator,
        bytes32 operatorId,
        bytes memory quorumNumbers,
        string memory socket
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

        emit OperatorSocketUpdate(operatorId, socket);

        // Register the operator with the BLSApkRegistry, StakeRegistry, and IndexRegistry
        blsApkRegistry.registerOperator(operator, quorumNumbers);
        (results.operatorStakes, results.totalStakes) =
            stakeRegistry.registerOperator(operator, operatorId, quorumNumbers);
        results.numOperatorsPerQuorum = indexRegistry.registerOperator(operatorId, quorumNumbers);

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
        RegisterResults memory results =
            _registerOperator(operator, operatorId, quorumNumbers, socket);

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
                _deregisterOperator(operatorKickParams[i].operator, singleQuorumNumber);

                if (operatorSetsEnabled) {
                    _forceDeregisterOperator(operatorKickParams[i].operator, singleQuorumNumber);
                }
            }
        }
    }

    /**
     * @dev Deregister the operator from one or more quorums
     * This method updates the operator's quorum bitmap and status, then deregisters
     * the operator with the BLSApkRegistry, IndexRegistry, and StakeRegistry
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
     * when an operator is force-deregistered from a set of quorums. For any of the quorums that are
     * OperatorSets quorums, we need to deregister the operator in the AllocationManager.
     * @param operator The operator to deregister
     * @param quorumNumbers The quorum numbers the operator is force-deregistered from
     */
    function _forceDeregisterOperator(address operator, bytes memory quorumNumbers) internal {
        uint32[] memory operatorSetIds = new uint32[](quorumNumbers.length);
        uint256 numOperatorSetQuorums;

        // Check each quorum's stake type
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            if (_isM2Quorum(quorumNumber)) {
                operatorSetIds[numOperatorSetQuorums++] = quorumNumber;
            }
        }

        // If any OperatorSet quorums found, deregister from AVS in the AllocationManager
        if (numOperatorSetQuorums > 0) {
            // Resize array to exact size needed
            assembly {
                mstore(operatorSetIds, numOperatorSetQuorums)
            }
            allocationManager.deregisterFromOperatorSets(
                IAllocationManagerTypes.DeregisterParams({
                    operator: operator,
                    avs: accountIdentifier,
                    operatorSetIds: operatorSetIds
                })
            );
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
        operatorId = blsApkRegistry.getOperatorId(operator);
        if (operatorId == 0) {
            operatorId = blsApkRegistry.registerBLSPublicKey(
                operator, params, pubkeyRegistrationMessageHash(operator)
            );
        }
        return operatorId;
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
     * @notice Updates the StakeRegistry's view of the operator's stake in one or more quorums.
     * For any quorums where the StakeRegistry finds the operator is under the configured minimum
     * stake, `quorumsToRemove` is returned and used to deregister the operator from those quorums
     * @dev does nothing if operator is not registered for any quorums.
     */
    function _updateOperator(
        address operator,
        OperatorInfo memory operatorInfo,
        bytes memory quorumsToUpdate
    ) internal {
        if (operatorInfo.status != OperatorStatus.REGISTERED) {
            return;
        }
        bytes32 operatorId = operatorInfo.operatorId;
        uint192 quorumsToRemove =
            stakeRegistry.updateOperatorStake(operator, operatorId, quorumsToUpdate);

        if (!quorumsToRemove.isEmpty()) {
            _deregisterOperator({
                operator: operator,
                quorumNumbers: BitmapUtils.bitmapToBytesArray(quorumsToRemove)
            });
        }
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
        // Increment the total quorum count. Fails if we're already at the max
        uint8 prevQuorumCount = quorumCount;
        require(prevQuorumCount < MAX_QUORUM_COUNT, MaxQuorumsReached());
        quorumCount = prevQuorumCount + 1;

        // The previous count is the new quorum's number
        uint8 quorumNumber = prevQuorumCount;

        // Initialize the quorum here and in each registry
        _setOperatorSetParams(quorumNumber, operatorSetParams);

        /// Update the AllocationManager if operatorSetQuorum
        if (operatorSetsEnabled && !_isM2Quorum(quorumNumber)) {
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
            allocationManager.createOperatorSets({avs: accountIdentifier, params: createSetParams});
        }
        // Initialize stake registry based on stake type
        if (stakeType == IStakeRegistryTypes.StakeType.TOTAL_DELEGATED) {
            stakeRegistry.initializeDelegatedStakeQuorum(quorumNumber, minimumStake, strategyParams);
        } else if (stakeType == IStakeRegistryTypes.StakeType.TOTAL_SLASHABLE) {
            stakeRegistry.initializeSlashableStakeQuorum(
                quorumNumber, minimumStake, lookAheadPeriod, strategyParams
            );
        }

        indexRegistry.initializeQuorum(quorumNumber);
        blsApkRegistry.initializeQuorum(quorumNumber);
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

    /// @notice Returns true if the quorum number is an M2 quorum
    /// @dev We use bitwise and to check if the quorum number is an M2 quorum
    function _isM2Quorum(
        uint8 quorumNumber
    ) internal view returns (bool) {
        return M2quorumBitmap.isSet(quorumNumber);
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

    function _setAccountIdentifier(
        address _accountIdentifier
    ) internal {
        accountIdentifier = _accountIdentifier;
    }

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

    /// @notice Returns true if the quorum number is an M2 quorum
    function isM2Quorum(
        uint8 quorumNumber
    ) external view returns (bool) {
        return _isM2Quorum(quorumNumber);
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

    /// @notice Returns the number of registries
    function numRegistries() external view returns (uint256) {
        return registries.length;
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
        return BN254.hashToG1(
            _hashTypedDataV4(keccak256(abi.encode(PUBKEY_REGISTRATION_TYPEHASH, operator)))
        );
    }

    /// @dev need to override function here since its defined in both these contracts
    function owner()
        public
        view
        virtual
        override(OwnableUpgradeable, ISlashingRegistryCoordinator)
        returns (address)
    {
        return OwnableUpgradeable.owner();
    }
}
