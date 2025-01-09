// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {RegistrarStorage} from "./RegistrarStorage.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

import {BitmapUtils} from "./libraries/BitmapUtils.sol";
import {BN254} from "./libraries/BN254.sol";
import {SignatureCheckerLib} from "./libraries/SignatureCheckerLib.sol";
import {QuorumBitmapHistoryLib} from "./libraries/QuorumBitmapHistoryLib.sol";

import {IRegistrar} from "./interfaces/IRegistrar.sol";
import {
    IAllocationManager,
    OperatorSet,
    IAllocationManagerTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {Pausable} from "eigenlayer-contracts/src/contracts/permissions/Pausable.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";
import {IBLSApkRegistry} from "./interfaces/IBLSApkRegistry.sol";
import {IIndexRegistry} from "./interfaces/IIndexRegistry.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy } from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISocketUpdater} from "./interfaces/ISocketUpdater.sol";
import {IStakeRegistry, StakeType} from "./interfaces/IStakeRegistry.sol";


/**
 * @title A `Registrar` contract that keeps track of three registries:
 *      1) a `StakeRegistry` that keeps track of operators' stakes
 *      2) a `BLSApkRegistry` that keeps track of operators' BLS public keys and aggregate BLS public keys for each quorum
 *      3) an `IndexRegistry` that keeps track of an ordered list of operators for each quorum
 *
 * @author Layr Labs, Inc.
 */
contract Registrar is
    EIP712,
    Initializable,
    Pausable,
    OwnableUpgradeable,
    RegistrarStorage,
    ISocketUpdater,
    ISignatureUtils
{
    using BitmapUtils for *;
    using BN254 for BN254.G1Point;

    /// @dev Checks that `quorumNumber` corresponds to a quorum that has been created
    modifier quorumExists(uint8 quorumNumber) {
        require(
            quorumNumber < quorumCount,
            QuorumDoesNotExist()
        );
        _;
    }

    modifier onlyAllocationManager() {
        require(msg.sender == allocationManager, OnlyAllocationManager());
        _;
    }

    modifier onlyEjector() {
        require(msg.sender == ejector, OnlyEjector());
        _;
    }

    constructor(
        IStakeRegistry _stakeRegistry,
        IBLSApkRegistry _blsApkRegistry,
        IIndexRegistry _indexRegistry,
        IRegistryCoordinator _registryCoordinator,
        IAllocationManager _allocationManager,
        IPauserRegistry _pauserRegistry
    )
        RegistrarStorage(_stakeRegistry, _blsApkRegistry, _indexRegistry, _registryCoordinator, _allocationManager)
        EIP712("AVSRegistrar", "v0.0.1")
        Pausable(_pauserRegistry)
    {
        _disableInitializers();
    }

    /**
     * @param _initialOwner will hold the owner role
     * @param _churnApprover will hold the churnApprover role, which authorizes registering with churn
     * @param _ejector will hold the ejector role, which can force-eject operators from quorums
     * @param _initialPausedStatus pause status after calling initialize
     * Config for initial quorums (see `createQuorum`):
     * @param _operatorSetParams max operator count and operator churn parameters
     * @param _minimumStakes minimum stake weight to allow an operator to register
     * @param _strategyParams which Strategies/multipliers a quorum considers when calculating stake weight
     */
    function initialize(
        address _initialOwner,
        address _churnApprover,
        address _ejector,
        uint256 _initialPausedStatus,
        OperatorSetParam[] memory _operatorSetParams,
        uint96[] memory _minimumStakes,
        IStakeRegistry.StrategyParams[][] memory _strategyParams
    ) external initializer {
        require(
            _operatorSetParams.length == _minimumStakes.length
                && _minimumStakes.length == _strategyParams.length,
            InputLengthMismatch()
        );

        // Initialize roles
        _transferOwnership(_initialOwner);
        _setChurnApprover(_churnApprover);
        _setPausedStatus(_initialPausedStatus);
        _setEjector(_ejector);

        // Add registry contracts to the registries array
        registries.push(address(stakeRegistry));
        registries.push(address(blsApkRegistry));
        registries.push(address(indexRegistry));

        // Initialize RegistryCoordinator
        quorumCount = registryCoordinator.quorumCount();

        // TODO: cutover on registry coordinator
    }



    /**
     *
     *                         EXTERNAL FUNCTIONS
     *
     */


    /// @inheritdoc IRegistrar
    function registerOperator(
        address operator,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) external virtual onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) onlyAllocationManager {
        // Handle churn or normal registration based on first byte in `data`
        if (_isChurnRegistration(data)) {
            _registerOperatorWithChurn(operator, operatorSetIds, data);
        } else {
            _registerOperatorWithoutChurn(operator, operatorSetIds, data);
        }
        // Decode registration data from `data`
        (
            string memory socket,
            IBLSApkRegistry.PubkeyRegistrationParams memory params
        ) = abi.decode(data, (string, IBLSApkRegistry.PubkeyRegistrationParams));

        // Get operator ID from BLS registry
        bytes32 operatorId = _getOrCreateOperatorId(operator, params);

        // Convert `operatorSetIds` to `quorumNumbers`
        bytes memory quorumNumbers = _getQuorumNumbers(operatorSetIds);

        // Register operator with decoded parameters
        uint32[] memory numOperatorsPerQuorum = _registerOperator({
            operator: operator,
            operatorId: operatorId,
            quorumNumbers: quorumNumbers,
            socket: socket
        }).numOperatorsPerQuorum;

        // For each quorum, validate that the new operator count does not exceed the maximum
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            require(
                numOperatorsPerQuorum[i] <= _quorumParams[quorumNumber].maxOperatorCount,
                MaxQuorumsReached()
            );
        }
    }

    /// @inheritdoc IRegistrar
    function deregisterOperator(
        address operator,
        uint32[] calldata operatorSetIds
    ) external virtual onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) onlyAllocationManager {
        bytes memory quorumNumbers = _getQuorumNumbers(operatorSetIds);

        _deregisterOperator(operator, quorumNumbers);
    }

    /// @inheritdoc IRegistrar
    function ejectOperator(
        address operator,
        bytes memory quorumNumbers
    ) external onlyEjector {
        // Store the last ejection timestamp for cooldown
        lastEjectionTimestamp[operator] = block.timestamp;

        // Get the 
        OperatorInfo storage operatorInfo = _operatorInfo[operator];
        bytes32 operatorId = operatorInfo.operatorId;
        uint192 quorumsToRemove =
            uint192(BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers, quorumCount));
        uint192 currentBitmap = _currentOperatorBitmap(operatorId);

        // Deregister operator if they are registered
        if (
            operatorInfo.status == OperatorStatus.REGISTERED && !quorumsToRemove.isEmpty()
                && quorumsToRemove.isSubsetOf(currentBitmap)
        ) {
            _deregisterOperator({operator: operator, quorumNumbers: quorumNumbers});
        }

        // Call back into the AllocationManager to deregister
        allocationManager.deregisterFromOperatorSets(
            operator,
            quorumNumbers
        );
    }

    function _registerOperatorWithourChurn(

    ) external virtual {
        
    }

    /**
     * @notice Registers msg.sender as an operator for one or more quorums. If any quorum reaches its maximum operator
     * capacity, `operatorKickParams` is used to replace an old operator with the new one.
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @param operatorKickParams used to determine which operator is removed to maintain quorum capacity as the
     * operator registers for quorums
     * @param churnApproverSignature is the signature of the churnApprover over the `operatorKickParams`
     * @dev `params` is ignored if the caller has previously registered a public key
     */
    function _registerOperatorWithChurn(
        bytes calldata quorumNumbers,
        string memory socket,
        IBLSApkRegistry.PubkeyRegistrationParams memory params,
        OperatorKickParam[] memory operatorKickParams,
        SignatureWithSaltAndExpiry memory churnApproverSignature
    ) external virtual {
        require(
            operatorKickParams.length == quorumNumbers.length,
            InputLengthMismatch()
        );

        /**
         * If the operator has NEVER registered a pubkey before, use `params` to register
         * their pubkey in blsApkRegistry
         *
         * If the operator HAS registered a pubkey, `params` is ignored and the pubkey hash
         * (operatorId) is fetched instead
         */
        bytes32 operatorId = _getOrCreateOperatorId(msg.sender, params);

        // Verify the churn approver's signature for the registering operator and kick params
        _verifyChurnApproverSignature({
            registeringOperator: msg.sender,
            registeringOperatorId: operatorId,
            operatorKickParams: operatorKickParams,
            churnApproverSignature: churnApproverSignature
        });

        // Register the operator in each of the registry contracts and update the operator's
        // quorum bitmap and registration status
        RegisterResults memory results = _registerOperator({
            operator: msg.sender,
            operatorId: operatorId,
            quorumNumbers: quorumNumbers,
            socket: socket,
            operatorSignature: operatorSignature
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
                    newOperator: msg.sender,
                    newOperatorStake: results.operatorStakes[i],
                    kickParams: operatorKickParams[i],
                    setParams: operatorSetParams
                });

                _deregisterOperator(operatorKickParams[i].operator, quorumNumbers[i:i + 1]);
            }
        }
    }

    /**
     *
     *                         INTERNAL FUNCTIONS
     *
     */

    /**
     * @notice Helper data structure returned by `_registerOperator`
     * @param numOperatorsPerQuorum the number of operators registered for each quorum
     * @param operatorStakes the operator's stake in each quorum
     * @param totalStakes the total stake in each quorum
     */
    struct RegisterResults {
        uint32[] numOperatorsPerQuorum;
        uint96[] operatorStakes;
        uint96[] totalStakes;
    }

    /**
     * @notice Register the operator for one or more quorums. This method updates the
     * operator's quorum bitmap, socket, and status, then registers them with each registry
     * @param operator the operator to register
     * @param operatorId the operator's ID
     * @param quorumNumbers the quorums to register the operator for
     * @param socket the operator's socket
     */
    function _registerOperator(
        address operator,
        bytes32 operatorId,
        bytes memory quorumNumbers,
        string memory socket
    ) internal virtual returns (RegisterResults memory results) {
        /**
         * Get bitmap of quorums to register for an operator's current bitmap. Validate that:
         * - we're trying to register for at least 1 quorum
         * - the quorums we're registering for exist (checked against `quorumCount` in orderedBytesArrayToBitmap)
         * - the operator is not currently registered for any quorums we're registering for
         * Then, calculate the operator's new bitmap after registration
         */
        uint192 quorumsToAdd =
            uint192(BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers, quorumCount));
        uint192 currentBitmap = _currentOperatorBitmap(operatorId);
        require(
            !quorumsToAdd.isEmpty(), BitmapEmpty()
        );
        require(
            quorumsToAdd.noBitsInCommon(currentBitmap),
            AlreadyRegisteredForQuorums()
        );
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

        // Update the operator's registrations status if it isn't registered
        if (_operatorInfo[operator].status != OperatorStatus.REGISTERED) {
            _operatorInfo[operator] = OperatorInfo(operatorId, OperatorStatus.REGISTERED);
            emit OperatorRegistered(operator, operatorId);
        }

        // Register the operator with the BLSApkRegistry, StakeRegistry, and IndexRegistry
        blsApkRegistry.registerOperator(operator, quorumNumbers);
        (results.operatorStakes, results.totalStakes) =
            stakeRegistry.registerOperator(operator, operatorId, quorumNumbers);
        results.numOperatorsPerQuorum = indexRegistry.registerOperator(operatorId, quorumNumbers);

        return results;
    }

    /**
     * @dev Deregister the operator from one or more quorums
     * This method updates the operator's quorum bitmap and status, then deregisters
     * the operator with the BLSApkRegistry, IndexRegistry, and StakeRegistry
     * @param operator the operator to deregister
     * @param quorumNumbers the quorums to deregister the operator from
     */
    function _deregisterOperator(address operator, bytes memory quorumNumbers) internal virtual {
        // Fetch the operator's info and ensure they are registered
        OperatorInfo storage operatorInfo = _operatorInfo[operator];
        bytes32 operatorId = operatorInfo.operatorId;
        require(
            operatorInfo.status == OperatorStatus.REGISTERED,
            NotRegistered()
        );

        /**
         * Get bitmap of quorums to deregister from and operator's current bitmap. Validate that:
         * - we're trying to deregister from at least 1 quorum
         * - the quorums we're deregistering from exist (checked against `quorumCount` in orderedBytesArrayToBitmap)
         * - the operator is currently registered for any quorums we're trying to deregister from
         * Then, calculate the operator's new bitmap after deregistration
         */
        uint192 quorumsToRemove =
            uint192(BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers, quorumCount));
        uint192 currentBitmap = _currentOperatorBitmap(operatorId);
        require(
            !quorumsToRemove.isEmpty(),
            BitmapEmpty()
        );
        require(
            quorumsToRemove.isSubsetOf(currentBitmap),
            NotRegisteredForQuorum()
        );
        uint192 newBitmap = uint192(currentBitmap.minus(quorumsToRemove));

        // Update operator's bitmap and status
        _updateOperatorBitmap({operatorId: operatorId, newBitmap: newBitmap});

        // If the operator is no longer registered for any quorums, update their status and deregister
        // them from the AVS via the EigenLayer core contracts
        if (newBitmap.isEmpty()) {
            operatorInfo.status = OperatorStatus.DEREGISTERED;
            emit OperatorDeregistered(operator, operatorId);
        }

        // Deregister operator with each of the registry contracts
        blsApkRegistry.deregisterOperator(operator, quorumNumbers);
        stakeRegistry.deregisterOperator(operatorId, quorumNumbers);
        indexRegistry.deregisterOperator(operatorId, quorumNumbers);
    }



    /**
     * @notice Record an update to an operator's quorum bitmap.
     * @param newBitmap is the most up-to-date set of bitmaps the operator is registered for
     */
    function _updateOperatorBitmap(bytes32 operatorId, uint192 newBitmap) internal {
        QuorumBitmapHistoryLib.updateOperatorBitmap(_operatorBitmapHistory, operatorId, newBitmap);
    }

    /**
     * @notice Get the most recent bitmap for the operator, returning an empty bitmap if
     *         the operator is not registered.
     * @param operatorId the operatorId to get a bitmap for
     */
    function _currentOperatorBitmap(bytes32 operatorId) internal view returns (uint192) {
        return QuorumBitmapHistoryLib.currentOperatorBitmap(_operatorBitmapHistory, operatorId);
    }

    /**
     * @notice Sets a churn approver address
     * @param newChurnApprover the new churn approver
     */
    function _setChurnApprover(address newChurnApprover) internal {
        emit ChurnApproverUpdated(churnApprover, newChurnApprover);
        churnApprover = newChurnApprover;
    }

    /**
     * @notice Sets an ejector address
     * @param newEjector the new ejector
     */
    function _setEjector(address newEjector) internal {
        emit EjectorUpdated(ejector, newEjector);
        ejector = newEjector;
    }

    /**
     * @notice Converts an array of operator set IDs to a bytes array of quorum numbers
     */
    function _getQuorumNumbers(uint32[] memory operatorSetIds) internal returns (bytes memory) {
        bytes memory quorumNumbers = new bytes(operatorSetIds.length);
        for (uint256 i = 0; i < operatorSetIds.length; i++) {
            quorumNumbers[i] = bytes1(uint8(operatorSetIds[i]));
        }
        return quorumNumbers;
    }

    function _getOperatorSetIds(bytes memory quorumNumbers) internal returns (uint32[] memory) {
        uint32[] memory operatorSetIds = new uint32[](quorumNumbers.length);
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            operatorSetIds[i] = uint32(uint8(quorumNumbers[i]));
        }
        return operatorSetIds;
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
        IBLSApkRegistry.PubkeyRegistrationParams memory params
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
     *
     *                         VIEW FUNCTIONS
     *
     */
    
    /// @inheritdoc IRegistrar
    function pubkeyRegistrationMessageHash(address operator)
        public
        view
        returns (BN254.G1Point memory)
    {
        return BN254.hashToG1(
            _hashTypedDataV4(keccak256(abi.encode(PUBKEY_REGISTRATION_TYPEHASH, operator)))
        );
    }

    function createSlashableStakeQuorum(
        OperatorSetParam memory operatorSetParams,
        uint96 minimumStake,
        IStakeRegistry.StrategyParams[] memory strategyParams,
        uint32 lookAheadPeriod
    ) external virtual onlyOwner {
        _createQuorum(
            operatorSetParams,
            minimumStake,
            strategyParams,
            StakeType.TOTAL_SLASHABLE,
            lookAheadPeriod
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
        IStakeRegistry.StrategyParams[] memory strategyParams,
        StakeType stakeType,
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
        if (isOperatorSetAVS && !isM2Quorum[quorumNumber]) {
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
            serviceManager.createOperatorSets(createSetParams);
        }
        // Initialize stake registry based on stake type
        if (stakeType == StakeType.TOTAL_DELEGATED) {
            stakeRegistry.initializeDelegatedStakeQuorum(quorumNumber, minimumStake, strategyParams);
        } else if (stakeType == StakeType.TOTAL_SLASHABLE) {
            stakeRegistry.initializeSlashableStakeQuorum(
                quorumNumber, minimumStake, lookAheadPeriod, strategyParams
            );
        }

        indexRegistry.initializeQuorum(quorumNumber);
        blsApkRegistry.initializeQuorum(quorumNumber);
    }
}
