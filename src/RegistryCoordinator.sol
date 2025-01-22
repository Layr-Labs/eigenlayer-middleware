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
import {ISocketUpdater} from "./interfaces/ISocketUpdater.sol";
import {IBLSApkRegistry} from "./interfaces/IBLSApkRegistry.sol";
import {IStakeRegistry, StakeType} from "./interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "./interfaces/IIndexRegistry.sol";
import {IServiceManager} from "./interfaces/IServiceManager.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";

import {BitmapUtils} from "./libraries/BitmapUtils.sol";
import {BN254} from "./libraries/BN254.sol";
import {SignatureCheckerLib} from "./libraries/SignatureCheckerLib.sol";
import {QuorumBitmapHistoryLib} from "./libraries/QuorumBitmapHistoryLib.sol";
import {AVSRegistrar} from "./AVSRegistrar.sol";

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

import {Pausable} from "eigenlayer-contracts/src/contracts/permissions/Pausable.sol";
import {RegistryCoordinatorStorage} from "./RegistryCoordinatorStorage.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";

/**
 * @title A `RegistryCoordinator` that has three registries:
 *      1) a `StakeRegistry` that keeps track of operators' stakes
 *      2) a `BLSApkRegistry` that keeps track of operators' BLS public keys and aggregate BLS public keys for each quorum
 *      3) an `IndexRegistry` that keeps track of an ordered list of operators for each quorum
 *
 * @author Layr Labs, Inc.
 */
contract RegistryCoordinator is
    EIP712,
    Initializable,
    Pausable,
    OwnableUpgradeable,
    RegistryCoordinatorStorage,
    AVSRegistrar,
    ISocketUpdater,
    ISignatureUtils
{
    using BitmapUtils for *;
    using BN254 for BN254.G1Point;

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
        IServiceManager _serviceManager,
        IStakeRegistry _stakeRegistry,
        IBLSApkRegistry _blsApkRegistry,
        IIndexRegistry _indexRegistry,
        IAllocationManager _allocationManager,
        IPauserRegistry _pauserRegistry
    )
        RegistryCoordinatorStorage(
            _serviceManager,
            _stakeRegistry,
            _blsApkRegistry,
            _indexRegistry,
            _allocationManager
        )
        EIP712("AVSRegistryCoordinator", "v0.0.1")
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
        IStakeRegistry.StrategyParams[][] memory _strategyParams,
        StakeType[] memory _stakeTypes,
        uint32[] memory _lookAheadPeriods
    ) external initializer {
        require(
            _operatorSetParams.length == _minimumStakes.length
                && _minimumStakes.length == _strategyParams.length
                && _strategyParams.length == _stakeTypes.length
                && _stakeTypes.length == _lookAheadPeriods.length,
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

        // Create quorums
        for (uint256 i = 0; i < _operatorSetParams.length; i++) {
            _createQuorum(
                _operatorSetParams[i],
                _minimumStakes[i],
                _strategyParams[i],
                _stakeTypes[i],
                _lookAheadPeriods[i]
            );
        }
    }

    /**
     *
     *                         EXTERNAL FUNCTIONS
     *
     */

    /**
     * @notice Registers msg.sender as an operator for one or more quorums. If any quorum exceeds its maximum
     * operator capacity after the operator is registered, this method will fail.
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for
     * @param socket is the socket of the operator (typically an IP address)
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @param operatorSignature is the signature of the operator used by the AVS to register the operator in the delegation manager
     * @dev `params` is ignored if the caller has previously registered a public key
     * @dev `operatorSignature` is ignored if the operator's status is already REGISTERED
     */
    function registerOperator(
        bytes memory quorumNumbers,
        string memory socket,
        IBLSApkRegistry.PubkeyRegistrationParams memory params,
        SignatureWithSaltAndExpiry memory operatorSignature
    ) external onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) {
        require(!isUsingOperatorSets(), OperatorSetsEnabled());
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
            socket: socket,
            operatorSignature: operatorSignature
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
    }

    /**
     * @notice Registers msg.sender as an operator for one or more quorums. If any quorum reaches its maximum operator
     * capacity, `operatorKickParams` is used to replace an old operator with the new one.
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @param operatorKickParams used to determine which operator is removed to maintain quorum capacity as the
     * operator registers for quorums
     * @param churnApproverSignature is the signature of the churnApprover over the `operatorKickParams`
     * @param operatorSignature is the signature of the operator used by the AVS to register the operator in the delegation manager
     * @dev `params` is ignored if the caller has previously registered a public key
     * @dev `operatorSignature` is ignored if the operator's status is already REGISTERED
     */
    function registerOperatorWithChurn(
        bytes calldata quorumNumbers,
        string memory socket,
        IBLSApkRegistry.PubkeyRegistrationParams memory params,
        OperatorKickParam[] memory operatorKickParams,
        SignatureWithSaltAndExpiry memory churnApproverSignature,
        SignatureWithSaltAndExpiry memory operatorSignature
    ) external onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) {
        require(!isUsingOperatorSets(), OperatorSetsEnabled());
        require(operatorKickParams.length == quorumNumbers.length, InputLengthMismatch());

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
     * @notice Deregisters the caller from one or more quorums
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being deregistered from
     */
    function deregisterOperator(
        bytes memory quorumNumbers
    ) external onlyWhenNotPaused(PAUSED_DEREGISTER_OPERATOR) {
        // Check that either:
        // 1. The AVS hasn't migrated to operator sets yet (!isOperatorSetAVS), or
        // 2. The AVS has migrated but this is an M2 quorum
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            require(!isOperatorSetAVS || isM2Quorum[quorumNumber], OperatorSetsEnabled());
        }
        _deregisterOperator({operator: msg.sender, quorumNumbers: quorumNumbers});
    }

    function isUsingOperatorSets() public view returns (bool) {
        return isOperatorSetAVS;
    }

    function enableOperatorSets() external onlyOwner {
        require(!isOperatorSetAVS, OperatorSetsEnabled());

        // Set all existing quorums as m2 quorums
        for (uint8 i = 0; i < quorumCount; i++) {
            isM2Quorum[i] = true;
        }

        // Enable operator sets mode
        isOperatorSetAVS = true;
    }
    enum RegistrationType {
        NORMAL,
        CHURN
    }

    error InvalidRegistrationType();

    function registerOperator(
        address operator,
        uint32[] memory operatorSetIds,
        bytes calldata data
    ) external override onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) {
        require(isUsingOperatorSets(), OperatorSetsNotEnabled());
        for (uint256 i = 0; i < operatorSetIds.length; i++) {
            require(!isM2Quorum[uint8(operatorSetIds[i])], OperatorSetsNotSupported());
        }
        _checkAllocationManager();
        bytes memory quorumNumbers = new bytes(operatorSetIds.length);
        for (uint256 i = 0; i < operatorSetIds.length; i++) {
            quorumNumbers[i] = bytes1(uint8(operatorSetIds[i]));
        }

        // Handle churn or normal registration based on first byte in `data`
        RegistrationType registrationType = RegistrationType(uint8(bytes1(data[0:1])));
        if (registrationType == RegistrationType.NORMAL) {
            (, string memory socket, IBLSApkRegistry.PubkeyRegistrationParams memory params) = abi.decode(data, (RegistrationType, string, IBLSApkRegistry.PubkeyRegistrationParams));
            bytes32 operatorId = _getOrCreateOperatorId(operator, params);
            _registerOperatorToOperatorSet(operator, operatorId, quorumNumbers, socket);
        } else if (registrationType == RegistrationType.CHURN) {
            // Decode registration data from bytes
            (
                ,
                string memory socket,
                IBLSApkRegistry.PubkeyRegistrationParams memory params,
                OperatorKickParam[] memory operatorKickParams,
                SignatureWithSaltAndExpiry memory churnApproverSignature
            ) = abi.decode(
                data,
                (
                    RegistrationType,
                    string,
                    IBLSApkRegistry.PubkeyRegistrationParams,
                    OperatorKickParam[],
                    SignatureWithSaltAndExpiry
                )
            );

            _registerOperatorWithChurn(operator, quorumNumbers, socket, params, operatorKickParams, churnApproverSignature);
        } else {
            revert InvalidRegistrationType();
        }
    }

    function _registerOperatorWithChurn(
        address operator,
        bytes memory quorumNumbers,
        string memory socket,
        IBLSApkRegistry.PubkeyRegistrationParams memory params,
        OperatorKickParam[] memory operatorKickParams,
        SignatureWithSaltAndExpiry memory churnApproverSignature
    ) internal virtual {
        require(operatorKickParams.length == quorumNumbers.length, InputLengthMismatch());

        /**
         * If the operator has NEVER registered a pubkey before, use `params` to register
         * their pubkey in blsApkRegistry
         *
         * If the operator HAS registered a pubkey, `params` is ignored and the pubkey hash
         * (operatorId) is fetched instead
         */
        bytes32 operatorId = _getOrCreateOperatorId(operator, params);

        // Verify the churn approver's signature for the registering operator and kick params
        _verifyChurnApproverSignature({
            registeringOperator: operator,
            registeringOperatorId: operatorId,
            operatorKickParams: operatorKickParams,
            churnApproverSignature: churnApproverSignature
        });

        // Register the operator in each of the registry contracts and update the operator's
        // quorum bitmap and registration status
        RegisterResults memory results = _registerOperatorToOperatorSet(operator, operatorId, quorumNumbers, socket);

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
                if (isUsingOperatorSets()) {
                    _handleOperatorSetDeregistration(operatorKickParams[i].operator, singleQuorumNumber);
                }
            }
        }
    }

    function deregisterOperator(
        address operator,
        uint32[] memory operatorSetIds
    ) external override onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) {
        require(isUsingOperatorSets(), OperatorSetsNotEnabled());
        for (uint256 i = 0; i < operatorSetIds.length; i++) {
            require(!isM2Quorum[uint8(operatorSetIds[i])], OperatorSetsNotSupported());
        }
        _checkAllocationManager();
        bytes memory quorumNumbers = new bytes(operatorSetIds.length);
        for (uint256 i = 0; i < operatorSetIds.length; i++) {
            quorumNumbers[i] = bytes1(uint8(operatorSetIds[i]));
        }

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
        emit OperatorSocketUpdate(_operatorInfo[msg.sender].operatorId, socket);
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
            // If using operator sets, check for non-M2 quorums
            if (isUsingOperatorSets()) {
                _handleOperatorSetDeregistration(operator, quorumNumbers);
            }

            _deregisterOperator({operator: operator, quorumNumbers: quorumNumbers});
        }
    }

    /**
     * @notice Helper function to handle operator set deregistration for non-M2 quorums
     * @param operator The operator to deregister
     * @param quorumNumbers The quorum numbers to check
     */
    function _handleOperatorSetDeregistration(address operator, bytes memory quorumNumbers) internal {
        uint32[] memory nonM2OperatorSetIds = new uint32[](quorumNumbers.length);
        uint256 numNonM2Quorums;

        // Check each quorum's stake type
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            if (isM2Quorum[quorumNumber]) {
                nonM2OperatorSetIds[numNonM2Quorums++] = quorumNumber;
            }
        }

        // If any non-M2 quorums found, deregister from AVS
        if (numNonM2Quorums > 0) {
            // Resize array to exact size needed
            assembly {
                mstore(nonM2OperatorSetIds, numNonM2Quorums)
            }
            serviceManager.deregisterOperatorFromOperatorSets(operator, nonM2OperatorSetIds);
        }
    }

    /**
     *
     *                         EXTERNAL FUNCTIONS - OWNER
     *
     */

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
        IStakeRegistry.StrategyParams[] memory strategyParams
    ) external virtual onlyOwner {
        _createQuorum(operatorSetParams, minimumStake, strategyParams, StakeType.TOTAL_DELEGATED, 0);
    }

    function createSlashableStakeQuorum(
        OperatorSetParam memory operatorSetParams,
        uint96 minimumStake,
        IStakeRegistry.StrategyParams[] memory strategyParams,
        uint32 lookAheadPeriod
    ) external virtual onlyOwner {
        require(isUsingOperatorSets(), OperatorSetsNotEnabled());
        _createQuorum(
            operatorSetParams,
            minimumStake,
            strategyParams,
            StakeType.TOTAL_SLASHABLE,
            lookAheadPeriod
        );
    }

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
     * @notice Sets the ejection cooldown, which is the time an operator must wait in
     * seconds afer ejection before registering for any quorum
     * @param _ejectionCooldown the new ejection cooldown in seconds
     * @dev only callable by the owner
    */
    function setEjectionCooldown(uint256 _ejectionCooldown) external onlyOwner {
        ejectionCooldown = _ejectionCooldown;
    }

    /**
     *
     *                         INTERNAL FUNCTIONS
     *
     */
    struct RegisterResults {
        uint32[] numOperatorsPerQuorum;
        uint96[] operatorStakes;
        uint96[] totalStakes;
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
        SignatureWithSaltAndExpiry memory operatorSignature
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

        // If the operator wasn't registered for any quorums, update their status
        // and register them with this AVS in EigenLayer core (DelegationManager)
        if (_operatorInfo[operator].status != OperatorStatus.REGISTERED) {
            _operatorInfo[operator] =
                OperatorInfo({operatorId: operatorId, status: OperatorStatus.REGISTERED});

            serviceManager.registerOperatorToAVS(operator, operatorSignature);
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
     * @notice Register the operator for one or more quorums. This method updates the
     * operator's quorum bitmap, socket, and status, then registers them with each registry.
     */
    function _registerOperatorToOperatorSet(
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

        // If the operator wasn't registered for any quorums, update their status
        // and register them with this AVS in EigenLayer core (DelegationManager)
        if (_operatorInfo[operator].status != OperatorStatus.REGISTERED) {
            _operatorInfo[operator] = OperatorInfo(operatorId, OperatorStatus.REGISTERED);
        }

        // Register the operator with the BLSApkRegistry, StakeRegistry, and IndexRegistry
        blsApkRegistry.registerOperator(operator, quorumNumbers);
        (results.operatorStakes, results.totalStakes) =
            stakeRegistry.registerOperator(operator, operatorId, quorumNumbers);
        results.numOperatorsPerQuorum = indexRegistry.registerOperator(operatorId, quorumNumbers);

        return results;
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
     * @dev Deregister the operator from one or more quorums
     * This method updates the operator's quorum bitmap and status, then deregisters
     * the operator with the BLSApkRegistry, IndexRegistry, and StakeRegistry
     */
    function _deregisterOperator(address operator, bytes memory quorumNumbers) internal virtual {
        // Fetch the operator's info and ensure they are registered
        OperatorInfo storage operatorInfo = _operatorInfo[operator];
        bytes32 operatorId = operatorInfo.operatorId;
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
        uint192 currentBitmap = _currentOperatorBitmap(operatorId);
        require(!quorumsToRemove.isEmpty(), BitmapCannotBeZero());
        require(quorumsToRemove.isSubsetOf(currentBitmap), NotRegisteredForQuorum());
        uint192 newBitmap = uint192(currentBitmap.minus(quorumsToRemove));

        // Update operator's bitmap and status
        _updateOperatorBitmap({operatorId: operatorId, newBitmap: newBitmap});

        // If the operator is no longer registered for any quorums, update their status and deregister
        // them from the AVS via the EigenLayer core contracts
        if (newBitmap.isEmpty()) {
            operatorInfo.status = OperatorStatus.DEREGISTERED;
            serviceManager.deregisterOperatorFromAVS(operator);
            emit OperatorDeregistered(operator, operatorId);
        }

        // Deregister operator with each of the registry contracts
        blsApkRegistry.deregisterOperator(operator, quorumNumbers);
        stakeRegistry.deregisterOperator(operatorId, quorumNumbers);
        indexRegistry.deregisterOperator(operatorId, quorumNumbers);
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
            allocationManager.createOperatorSets({
                avs: address(serviceManager),
                params: createSetParams
            });
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
    ) external view returns (IRegistryCoordinator.OperatorStatus) {
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
        override(OwnableUpgradeable, IRegistryCoordinator)
        returns (address)
    {
        return OwnableUpgradeable.owner();
    }
}
