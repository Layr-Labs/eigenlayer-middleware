// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

import {EIP1271SignatureUtils} from "eigenlayer-contracts/src/contracts/libraries/EIP1271SignatureUtils.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {Pausable} from "eigenlayer-contracts/src/contracts/permissions/Pausable.sol";
import {ISlasher} from "eigenlayer-contracts/src/contracts/interfaces/ISlasher.sol";

import {IRegistryCoordinator} from "src/interfaces/IRegistryCoordinator.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IBLSApkRegistry} from "src/interfaces/IBLSApkRegistry.sol";
import {IServiceManager} from "src/interfaces/IServiceManager.sol";
import {ISocketUpdater} from "src/interfaces/ISocketUpdater.sol";
import {IStakeRegistry} from "src/interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "src/interfaces/IIndexRegistry.sol";

import {BitmapUtils} from "src/libraries/BitmapUtils.sol";
import {BN254} from "src/libraries/BN254.sol";

/**
 * @title A `RegistryCoordinator` that has three registries:
 *      1) a `StakeRegistry` that keeps track of operators' stakes
 *      2) a `BLSApkRegistry` that keeps track of operators' BLS public keys and aggregate BLS public keys for each quorum
 *      3) an `IndexRegistry` that keeps track of an ordered list of operators for each quorum
 * 
 * @author Layr Labs, Inc.
 */
contract RegistryCoordinator is EIP712, Initializable, IRegistryCoordinator, ISocketUpdater, ISignatureUtils, Pausable {
    using BitmapUtils for *;
    using BN254 for BN254.G1Point;

    /// @notice The EIP-712 typehash for the `DelegationApproval` struct used by the contract
    bytes32 public constant OPERATOR_CHURN_APPROVAL_TYPEHASH =
        keccak256("OperatorChurnApproval(bytes32 registeringOperatorId,OperatorKickParam[] operatorKickParams)OperatorKickParam(address operator,bytes32[] operatorIdsToSwap)");
    /// @notice The maximum value of a quorum bitmap
    uint256 internal constant MAX_QUORUM_BITMAP = type(uint192).max;
    /// @notice The basis point denominator
    uint16 internal constant BIPS_DENOMINATOR = 10000;
    /// @notice Index for flag that pauses operator registration
    uint8 internal constant PAUSED_REGISTER_OPERATOR = 0;
    /// @notice Index for flag that pauses operator deregistration
    uint8 internal constant PAUSED_DEREGISTER_OPERATOR = 1;
    /// @notice Index for flag pausing operator stake updates
    uint8 internal constant PAUSED_UPDATE_OPERATOR = 2;
    /// @notice The maximum number of quorums this contract supports
    uint8 internal constant MAX_QUORUM_COUNT = 192;

    /// @notice the EigenLayer Slasher
    ISlasher public immutable slasher;
    /// @notice the Service Manager for the service that this contract is coordinating
    IServiceManager public immutable serviceManager;
    /// @notice the BLS Aggregate Pubkey Registry contract that will keep track of operators' aggregate BLS public keys per quorum
    IBLSApkRegistry public immutable blsApkRegistry;
    /// @notice the Stake Registry contract that will keep track of operators' stakes
    IStakeRegistry public immutable stakeRegistry;
    /// @notice the Index Registry contract that will keep track of operators' indexes
    IIndexRegistry public immutable indexRegistry;

    /// @notice the current number of quorums supported by the registry coordinator
    uint8 public quorumCount;
    /// @notice maps quorum number => operator cap and kick params
    mapping(uint8 => OperatorSetParam) internal _quorumParams;
    /// @notice maps operator id => historical quorums they registered for
    mapping(bytes32 => QuorumBitmapUpdate[]) internal _operatorBitmapHistory;
    /// @notice maps operator address => operator id and status
    mapping(address => OperatorInfo) internal _operatorInfo;
    /// @notice whether the salt has been used for an operator churn approval
    mapping(bytes32 => bool) public isChurnApproverSaltUsed;

    /// @notice the dynamic-length array of the registries this coordinator is coordinating
    address[] public registries;
    /// @notice the address of the entity allowed to sign off on operators getting kicked out of the AVS during registration
    address public churnApprover;
    /// @notice the address of the entity allowed to eject operators from the AVS
    address public ejector;

    modifier onlyServiceManagerOwner {
        require(msg.sender == serviceManager.owner(), "RegistryCoordinator.onlyServiceManagerOwner: caller is not the service manager owner");
        _;
    }

    modifier onlyEjector {
        require(msg.sender == ejector, "RegistryCoordinator.onlyEjector: caller is not the ejector");
        _;
    }

    modifier quorumExists(uint8 quorumNumber) {
        require(
            quorumNumber < quorumCount, 
            "RegistryCoordinator.quorumExists: quorum does not exist"
        );
        _;
    }

    constructor(
        ISlasher _slasher,
        IServiceManager _serviceManager,
        IStakeRegistry _stakeRegistry,
        IBLSApkRegistry _blsApkRegistry,
        IIndexRegistry _indexRegistry
    ) EIP712("AVSRegistryCoordinator", "v0.0.1") {
        slasher = _slasher;
        serviceManager = _serviceManager;
        stakeRegistry = _stakeRegistry;
        blsApkRegistry = _blsApkRegistry;
        indexRegistry = _indexRegistry;
    }

    function initialize(
        address _churnApprover,
        address _ejector,
        IPauserRegistry _pauserRegistry,
        uint256 _initialPausedStatus,
        OperatorSetParam[] memory _operatorSetParams,
        uint96[] memory _minimumStakes,
        IStakeRegistry.StrategyParams[][] memory _strategyParams
    ) external initializer {
        require(
            _operatorSetParams.length == _minimumStakes.length && _minimumStakes.length == _strategyParams.length,
            "RegistryCoordinator.initialize: input length mismatch"
        );
        
        // Initialize roles
        _initializePauser(_pauserRegistry, _initialPausedStatus);
        _setChurnApprover(_churnApprover);
        _setEjector(_ejector);

        // Add registry contracts to the registries array
        registries.push(address(stakeRegistry));
        registries.push(address(blsApkRegistry));
        registries.push(address(indexRegistry));

        // Create quorums
        for (uint256 i = 0; i < _operatorSetParams.length; i++) {
            _createQuorum(_operatorSetParams[i], _minimumStakes[i], _strategyParams[i]);
        }
    }

    /*******************************************************************************
                            EXTERNAL FUNCTIONS 
    *******************************************************************************/

    /**
     * @notice Registers msg.sender as an operator for one or more quorums. If any quorum reaches its maximum
     * operator capacity, this method will fail.
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @dev the `params` input param is ignored if the caller has previously registered a public key
     */
    function registerOperator(
        bytes calldata quorumNumbers,
        string calldata socket,
        IBLSApkRegistry.PubkeyRegistrationParams calldata params
    ) external onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) {
        /**
         * IF the operator has never registered a pubkey before, THEN register their pubkey
         * OTHERWISE, simply ignore the provided `params`
         */
        bytes32 operatorId = blsApkRegistry.getOperatorId(msg.sender);
        if (operatorId == 0) {
            operatorId = blsApkRegistry.registerBLSPublicKey(msg.sender, params);
        }

        // Register the operator in each of the registry contracts
        RegisterResults memory results = _registerOperator({
            operator: msg.sender, 
            operatorId: operatorId,
            quorumNumbers: quorumNumbers, 
            socket: socket
        });

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            
            OperatorSetParam memory operatorSetParams = _quorumParams[quorumNumber];
            
            /**
             * The new operator count for each quorum may not exceed the configured maximum
             * If it does, use `registerOperatorWithChurn` instead.
             */
            require(
                results.numOperatorsPerQuorum[i] <= operatorSetParams.maxOperatorCount,
                "RegistryCoordinator.registerOperator: operator count exceeds maximum"
            );
        }
    }

    /**
     * @notice Registers msg.sender as an operator for one or more quorums. If any quorum reaches its maximum operator
     * capacity, `operatorKickParams` is used to replace an old operator with the new one.
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @param operatorKickParams are used to determine which operator is removed to maintain quorum capacity as the
     * operator registers for quorums.
     * @param churnApproverSignature is the signature of the churnApprover on the operator kick params
     * @dev the `params` input param is ignored if the caller has previously registered a public key
     */
    function registerOperatorWithChurn(
        bytes calldata quorumNumbers, 
        string calldata socket,
        IBLSApkRegistry.PubkeyRegistrationParams calldata params,
        OperatorKickParam[] calldata operatorKickParams,
        SignatureWithSaltAndExpiry memory churnApproverSignature
    ) external onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) {
        require(operatorKickParams.length == quorumNumbers.length, "RegistryCoordinator.registerOperatorWithChurn: input length mismatch");

        /**
         * IF the operator has never registered a pubkey before, THEN register their pubkey
         * OTHERWISE, simply ignore the `pubkeyRegistrationSignature`, `pubkeyG1`, and `pubkeyG2` inputs
         */
        bytes32 operatorId = blsApkRegistry.getOperatorId(msg.sender);
        if (operatorId == 0) {
            operatorId = blsApkRegistry.registerBLSPublicKey(msg.sender, params);
        }

        // Verify the churn approver's signature for the registering operator and kick params
        _verifyChurnApproverSignature({
            registeringOperatorId: operatorId,
            operatorKickParams: operatorKickParams,
            churnApproverSignature: churnApproverSignature
        });

        // Register the operator in each of the registry contracts
        RegisterResults memory results = _registerOperator({
            operator: msg.sender,
            operatorId: operatorId,
            quorumNumbers: quorumNumbers,
            socket: socket
        });

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            OperatorSetParam memory operatorSetParams = _quorumParams[quorumNumber];
            
            /**
             * If the new operator count for any quorum exceeds the maximum, validate
             * that churn can be performed, then deregister the specified operator
             */
            if (results.numOperatorsPerQuorum[i] > operatorSetParams.maxOperatorCount) {
                _validateChurn({
                    quorumNumber: quorumNumber,
                    totalQuorumStake: results.totalStakes[i],
                    newOperator: msg.sender,
                    newOperatorStake: results.operatorStakes[i],
                    kickParams: operatorKickParams[i],
                    setParams: operatorSetParams
                });

                _deregisterOperator(operatorKickParams[i].operator, quorumNumbers[i:i+1]);
            }
        }
    }

    /**
     * @notice Deregisters the caller from one or more quorums
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being deregistered from
     */
    function deregisterOperator(
        bytes calldata quorumNumbers
    ) external onlyWhenNotPaused(PAUSED_DEREGISTER_OPERATOR) {
        _deregisterOperator({
            operator: msg.sender, 
            quorumNumbers: quorumNumbers
        });
    }

    /**
     * @notice Updates the stakes of one or more operators in the StakeRegistry, for each quorum
     * the operator is registered for.
     * 
     * If any operator no longer meets the minimum stake required to remain in the quorum,
     * they are deregistered.
     */
    function updateOperators(address[] calldata operators) external onlyWhenNotPaused(PAUSED_UPDATE_OPERATOR) {
        for (uint256 i = 0; i < operators.length; i++) {

            address operator = operators[i];
            OperatorInfo storage operatorInfo = _operatorInfo[operator];
            bytes32 operatorId = operatorInfo.operatorId;

            // Only update operators currently registered for at least one quorum
            if (operatorInfo.status != OperatorStatus.REGISTERED) {
                continue;
            }

            uint192 currentBitmap = _currentOperatorBitmap(operatorId);
            bytes memory currentQuorums = BitmapUtils.bitmapToBytesArray(currentBitmap);

            /**
             * Update the operator's stake for their active quorums. The stakeRegistry returns a bitmap
             * of quorums where the operator no longer meets the minimum stake, and should be deregistered.
             */
            uint192 quorumsToRemove = stakeRegistry.updateOperatorStake(operator, operatorId, currentQuorums);

            if (!quorumsToRemove.isEmpty()) {
                _deregisterOperator({
                    operator: operator,
                    quorumNumbers: BitmapUtils.bitmapToBytesArray(quorumsToRemove)
                });    
            }
        }
    }

    /**
     * @notice Updates the socket of the msg.sender given they are a registered operator
     * @param socket is the new socket of the operator
     */
    function updateSocket(string memory socket) external {
        require(_operatorInfo[msg.sender].status == OperatorStatus.REGISTERED, "RegistryCoordinator.updateSocket: operator is not registered");
        emit OperatorSocketUpdate(_operatorInfo[msg.sender].operatorId, socket);
    }

    /*******************************************************************************
                            EXTERNAL FUNCTIONS - EJECTOR
    *******************************************************************************/

    /**
     * @notice Ejects the provided operator from the provided quorums from the AVS
     * @param operator is the operator to eject
     * @param quorumNumbers are the quorum numbers to eject the operator from
     */
    function ejectOperator(
        address operator, 
        bytes calldata quorumNumbers
    ) external onlyEjector {
        _deregisterOperator({
            operator: operator, 
            quorumNumbers: quorumNumbers
        });
    }

    /*******************************************************************************
                    EXTERNAL FUNCTIONS - SERVICE MANAGER OWNER
    *******************************************************************************/

    /**
     * @notice Creates a quorum and initializes it in each registry contract
     */
    function createQuorum(
        OperatorSetParam memory operatorSetParams,
        uint96 minimumStake,
        IStakeRegistry.StrategyParams[] memory strategyParams
    ) external virtual onlyServiceManagerOwner {
        _createQuorum(operatorSetParams, minimumStake, strategyParams);
    }

    /**
     * @notice Updates a quorum's OperatorSetParams
     * @param quorumNumber is the quorum number to set the maximum number of operators for
     * @param operatorSetParams is the parameters of the operator set for the `quorumNumber`
     * @dev only callable by the service manager owner
     */
    function setOperatorSetParams(
        uint8 quorumNumber, 
        OperatorSetParam memory operatorSetParams
    ) external onlyServiceManagerOwner quorumExists(quorumNumber) {
        _setOperatorSetParams(quorumNumber, operatorSetParams);
    }

    /**
     * @notice Sets the churnApprover
     * @param _churnApprover is the address of the churnApprover
     * @dev only callable by the service manager owner
     */
    function setChurnApprover(address _churnApprover) external onlyServiceManagerOwner {
        _setChurnApprover(_churnApprover);
    }

    /**
     * @notice Sets the ejector
     * @param _ejector is the address of the ejector
     * @dev only callable by the service manager owner
     */
    function setEjector(address _ejector) external onlyServiceManagerOwner {
        _setEjector(_ejector);
    }

    /*******************************************************************************
                            INTERNAL FUNCTIONS
    *******************************************************************************/

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
        bytes calldata quorumNumbers,
        string memory socket
    ) internal virtual returns (RegisterResults memory) {
        /**
         * Get bitmap of quorums to register for and operator's current bitmap. Validate that:
         * - we're trying to register for at least 1 quorum
         * - the operator is not currently registered for any quorums we're registering for
         * Then, calculate the operator's new bitmap after registration
         */
        uint192 quorumsToAdd = uint192(BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers, quorumCount));
        uint192 currentBitmap = _currentOperatorBitmap(operatorId);
        require(!quorumsToAdd.isEmpty(), "RegistryCoordinator._registerOperator: bitmap cannot be 0");
        require(quorumsToAdd.noBitsInCommon(currentBitmap), "RegistryCoordinator._registerOperator: operator already registered for some quorums being registered for");
        uint192 newBitmap = uint192(currentBitmap.plus(quorumsToAdd));

        /**
         * Update operator's bitmap, socket, and status. Only update operatorInfo if needed:
         * if we're `REGISTERED`, the operatorId and status are already correct.
         */
        _updateOperatorBitmap({
            operatorId: operatorId,
            newBitmap: newBitmap
        });

        emit OperatorSocketUpdate(operatorId, socket);

        if (_operatorInfo[operator].status != OperatorStatus.REGISTERED) {
            _operatorInfo[operator] = OperatorInfo({
                operatorId: operatorId,
                status: OperatorStatus.REGISTERED
            });

            emit OperatorRegistered(operator, operatorId);
        }

        /**
         * Register the operator with the BLSApkRegistry, StakeRegistry, and IndexRegistry
         */
        bytes32 registeredId = blsApkRegistry.registerOperator(operator, quorumNumbers);
        require(registeredId == operatorId, "RegistryCoordinator._registerOperator: operatorId mismatch");
        (uint96[] memory operatorStakes, uint96[] memory totalStakes) = 
            stakeRegistry.registerOperator(operator, operatorId, quorumNumbers);
        uint32[] memory numOperatorsPerQuorum = indexRegistry.registerOperator(operatorId, quorumNumbers);

        return RegisterResults({
            numOperatorsPerQuorum: numOperatorsPerQuorum,
            operatorStakes: operatorStakes,
            totalStakes: totalStakes
        });
    }

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
        require(newOperator != operatorToKick, "RegistryCoordinator._validateChurn: cannot churn self");
        require(kickParams.quorumNumber == quorumNumber, "RegistryCoordinator._validateChurn: quorumNumber not the same as signed");

        // Get the target operator's stake and check that it is below the kick thresholds
        uint96 operatorToKickStake = stakeRegistry.getCurrentStake(idToKick, quorumNumber);
        require(
            newOperatorStake > _individualKickThreshold(operatorToKickStake, setParams),
            "RegistryCoordinator._validateChurn: incoming operator has insufficient stake for churn"
        );
        require(
            operatorToKickStake < _totalKickThreshold(totalQuorumStake, setParams),
            "RegistryCoordinator._validateChurn: cannot kick operator with more than kickBIPsOfTotalStake"
        );
    }

    /**
     * @dev Deregister the operator from one or more quorums
     * This method updates the operator's quorum bitmap and status, then deregisters
     * the operator with the BLSApkRegistry, IndexRegistry, and StakeRegistry
     */
    function _deregisterOperator(
        address operator, 
        bytes memory quorumNumbers
    ) internal virtual {
        // Fetch the operator's info and ensure they are registered
        OperatorInfo storage operatorInfo = _operatorInfo[operator];
        bytes32 operatorId = operatorInfo.operatorId;
        require(operatorInfo.status == OperatorStatus.REGISTERED, "RegistryCoordinator._deregisterOperator: operator is not registered");
        
        /**
         * Get bitmap of quorums to deregister from and operator's current bitmap. Validate that:
         * - we're trying to deregister from at least 1 quorum
         * - the operator is currently registered for any quorums we're trying to deregister from
         * Then, calculate the opreator's new bitmap after deregistration
         */
        uint192 quorumsToRemove = uint192(BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers, quorumCount));
        uint192 currentBitmap = _currentOperatorBitmap(operatorId);
        require(!quorumsToRemove.isEmpty(), "RegistryCoordinator._deregisterOperator: bitmap cannot be 0");
        require(quorumsToRemove.isSubsetOf(currentBitmap), "RegistryCoordinator._deregisterOperator: operator is not registered for specified quorums");
        uint192 newBitmap = uint192(currentBitmap.minus(quorumsToRemove));

        /**
         * Update operator's bitmap and status:
         */
        _updateOperatorBitmap({
            operatorId: operatorId,
            newBitmap: newBitmap
        });

        // If the operator is no longer registered for any quorums, update their status
        if (newBitmap.isEmpty()) {
            operatorInfo.status = OperatorStatus.DEREGISTERED;
            emit OperatorDeregistered(operator, operatorId);
        }

        // Deregister operator with each of the registry contracts:
        blsApkRegistry.deregisterOperator(operator, quorumNumbers);
        stakeRegistry.deregisterOperator(operatorId, quorumNumbers);
        indexRegistry.deregisterOperator(operatorId, quorumNumbers);
    }

    /**
     * @notice Returns the stake threshold required for an incoming operator to replace an existing operator
     * The incoming operator must have more stake than the return value.
     */
    function _individualKickThreshold(uint96 operatorStake, OperatorSetParam memory setParams) internal pure returns (uint96) {
        return operatorStake * setParams.kickBIPsOfOperatorStake / BIPS_DENOMINATOR;
    }

    /**
     * @notice Returns the total stake threshold required for an operator to remain in a quorum.
     * The operator must have at least the returned stake amount to keep their position.
     */
    function _totalKickThreshold(uint96 totalStake, OperatorSetParam memory setParams) internal pure returns (uint96) {
        return totalStake * setParams.kickBIPsOfTotalStake / BIPS_DENOMINATOR;
    }

    /// @notice verifies churnApprover's signature on operator churn approval and increments the churnApprover nonce
    function _verifyChurnApproverSignature(
        bytes32 registeringOperatorId, 
        OperatorKickParam[] memory operatorKickParams, 
        SignatureWithSaltAndExpiry memory churnApproverSignature
    ) internal {
        // make sure the salt hasn't been used already
        require(!isChurnApproverSaltUsed[churnApproverSignature.salt], "RegistryCoordinator._verifyChurnApproverSignature: churnApprover salt already used");
        require(churnApproverSignature.expiry >= block.timestamp, "RegistryCoordinator._verifyChurnApproverSignature: churnApprover signature expired");   

        // set salt used to true
        isChurnApproverSaltUsed[churnApproverSignature.salt] = true;    

        // check the churnApprover's signature 
        EIP1271SignatureUtils.checkSignature_EIP1271(
            churnApprover, 
            calculateOperatorChurnApprovalDigestHash(registeringOperatorId, operatorKickParams, churnApproverSignature.salt, churnApproverSignature.expiry), 
            churnApproverSignature.signature
        );
    }

    /**
     * @notice Creates and initializes a quorum in each registry contract
     */
    function _createQuorum(
        OperatorSetParam memory operatorSetParams,
        uint96 minimumStake,
        IStakeRegistry.StrategyParams[] memory strategyParams
    ) internal {
        // Increment the total quorum count. Fails if we're already at the max
        uint8 prevQuorumCount = quorumCount;
        require(prevQuorumCount < MAX_QUORUM_COUNT, "RegistryCoordinator.createQuorum: max quorums reached");
        quorumCount = prevQuorumCount + 1;
        
        // The previous count is the new quorum's number
        uint8 quorumNumber = prevQuorumCount;

        // Initialize the quorum here and in each registry
        _setOperatorSetParams(quorumNumber, operatorSetParams);
        stakeRegistry.initializeQuorum(quorumNumber, minimumStake, strategyParams);
        indexRegistry.initializeQuorum(quorumNumber);
        blsApkRegistry.initializeQuorum(quorumNumber);
    }

    /**
     * @notice Record an update to an operator's quorum bitmap.
     * @param newBitmap is the most up-to-date set of bitmaps the operator is registered for
     */
    function _updateOperatorBitmap(bytes32 operatorId, uint192 newBitmap) internal {

        uint256 historyLength = _operatorBitmapHistory[operatorId].length;

        if (historyLength == 0) {
            // No prior bitmap history - push our first entry
            _operatorBitmapHistory[operatorId].push(QuorumBitmapUpdate({
                updateBlockNumber: uint32(block.number),
                nextUpdateBlockNumber: 0,
                quorumBitmap: newBitmap
            }));
        } else {
            // We have prior history - fetch our last-recorded update
            QuorumBitmapUpdate storage lastUpdate = _operatorBitmapHistory[operatorId][historyLength - 1];

            /**
             * If the last update was made in the current block, update the entry.
             * Otherwise, push a new entry and update the previous entry's "next" field
             */
            if (lastUpdate.updateBlockNumber == uint32(block.number)) {
                lastUpdate.quorumBitmap = newBitmap;
            } else {
                lastUpdate.nextUpdateBlockNumber = uint32(block.number);
                _operatorBitmapHistory[operatorId].push(QuorumBitmapUpdate({
                    updateBlockNumber: uint32(block.number),
                    nextUpdateBlockNumber: 0,
                    quorumBitmap: newBitmap
                }));
            }
        }
    }

    /// @notice Get the most recent bitmap for the operator, returning an empty bitmap if
    /// the operator is not registered.
    function _currentOperatorBitmap(bytes32 operatorId) internal view returns (uint192) {
        uint256 historyLength = _operatorBitmapHistory[operatorId].length;
        if (historyLength == 0) {
            return 0;
        } else {
            return _operatorBitmapHistory[operatorId][historyLength - 1].quorumBitmap;
        }
    }

    function _setOperatorSetParams(uint8 quorumNumber, OperatorSetParam memory operatorSetParams) internal {
        _quorumParams[quorumNumber] = operatorSetParams;
        emit OperatorSetParamsUpdated(quorumNumber, operatorSetParams);
    }
    
    function _setChurnApprover(address newChurnApprover) internal {
        emit ChurnApproverUpdated(churnApprover, newChurnApprover);
        churnApprover = newChurnApprover;
    }

    function _setEjector(address newEjector) internal {
        emit EjectorUpdated(ejector, newEjector);
        ejector = newEjector;
    }

    /*******************************************************************************
                            VIEW FUNCTIONS
    *******************************************************************************/

    /// @notice Returns the operator set params for the given `quorumNumber`
    function getOperatorSetParams(uint8 quorumNumber) external view returns (OperatorSetParam memory) {
        return _quorumParams[quorumNumber];
    }

    /// @notice Returns the operator struct for the given `operator`
    function getOperator(address operator) external view returns (OperatorInfo memory) {
        return _operatorInfo[operator];
    }

    /// @notice Returns the operatorId for the given `operator`
    function getOperatorId(address operator) external view returns (bytes32) {
        return _operatorInfo[operator].operatorId;
    }

    /// @notice Returns the operator address for the given `operatorId`
    function getOperatorFromId(bytes32 operatorId) external view returns (address) {
        return blsApkRegistry.getOperatorFromPubkeyHash(operatorId);
    }

    /// @notice Returns the status for the given `operator`
    function getOperatorStatus(address operator) external view returns (IRegistryCoordinator.OperatorStatus) {
        return _operatorInfo[operator].status;
    }

    /// @notice Returns the indices of the quorumBitmaps for the provided `operatorIds` at the given `blockNumber`
    function getQuorumBitmapIndicesAtBlockNumber(
        uint32 blockNumber, 
        bytes32[] memory operatorIds
    ) external view returns (uint32[] memory) {
        uint32[] memory indices = new uint32[](operatorIds.length);
        for (uint256 i = 0; i < operatorIds.length; i++) {
            uint256 length = _operatorBitmapHistory[operatorIds[i]].length;
            for (uint256 j = 0; j < length; j++) {
                if (_operatorBitmapHistory[operatorIds[i]][length - j - 1].updateBlockNumber <= blockNumber) {
                    uint32 nextUpdateBlockNumber = 
                        _operatorBitmapHistory[operatorIds[i]][length - j - 1].nextUpdateBlockNumber;
                    require(
                        nextUpdateBlockNumber == 0 || nextUpdateBlockNumber > blockNumber,
                        "RegistryCoordinator.getQuorumBitmapIndicesAtBlockNumber: operatorId has no quorumBitmaps at blockNumber"
                    );
                    indices[i] = uint32(length - j - 1);
                    break;
                }
            }
        }
        return indices;
    }

    /**
     * @notice Returns the quorum bitmap for the given `operatorId` at the given `blockNumber` via the `index`
     * @dev reverts if `index` is incorrect 
     */ 
    function getQuorumBitmapAtBlockNumberByIndex(
        bytes32 operatorId, 
        uint32 blockNumber, 
        uint256 index
    ) external view returns (uint192) {
        QuorumBitmapUpdate memory quorumBitmapUpdate = _operatorBitmapHistory[operatorId][index];
        require(
            quorumBitmapUpdate.updateBlockNumber <= blockNumber, 
            "RegistryCoordinator.getQuorumBitmapAtBlockNumberByIndex: quorumBitmapUpdate is from after blockNumber"
        );
        // if the next update is at or before the block number, then the quorum provided index is too early
        // if the nex update  block number is 0, then this is the latest update
        require(
            quorumBitmapUpdate.nextUpdateBlockNumber > blockNumber || quorumBitmapUpdate.nextUpdateBlockNumber == 0, 
            "RegistryCoordinator.getQuorumBitmapAtBlockNumberByIndex: quorumBitmapUpdate is from before blockNumber"
        );
        return quorumBitmapUpdate.quorumBitmap;
    }

    /// @notice Returns the `index`th entry in the operator with `operatorId`'s bitmap history
    function getQuorumBitmapUpdateByIndex(
        bytes32 operatorId, 
        uint256 index
    ) external view returns (QuorumBitmapUpdate memory) {
        return _operatorBitmapHistory[operatorId][index];
    }

    /// @notice Returns the current quorum bitmap for the given `operatorId` or 0 if the operator is not registered for any quorum
    function getCurrentQuorumBitmap(bytes32 operatorId) external view returns (uint192) {
        uint256 quorumBitmapHistoryLength = _operatorBitmapHistory[operatorId].length;
        // the first part of this if statement is met if the operator has never registered. 
        // the second part is met if the operator has previously registered, but is currently deregistered
        if (quorumBitmapHistoryLength == 0 || _operatorBitmapHistory[operatorId][quorumBitmapHistoryLength - 1].nextUpdateBlockNumber != 0) {
            return 0;
        }
        return _operatorBitmapHistory[operatorId][quorumBitmapHistoryLength - 1].quorumBitmap;
    }

    /// @notice Returns the length of the quorum bitmap history for the given `operatorId`
    function getQuorumBitmapHistoryLength(bytes32 operatorId) external view returns (uint256) {
        return _operatorBitmapHistory[operatorId].length;
    }

    /// @notice Returns the number of registries
    function numRegistries() external view returns (uint256) {
        return registries.length;
    }

    /**
     * @notice Public function for the the churnApprover signature hash calculation when operators are being kicked from quorums
     * @param registeringOperatorId The is of the registering operator 
     * @param operatorKickParams The parameters needed to kick the operator from the quorums that have reached their caps
     * @param salt The salt to use for the churnApprover's signature
     * @param expiry The desired expiry time of the churnApprover's signature
     */
    function calculateOperatorChurnApprovalDigestHash(
        bytes32 registeringOperatorId,
        OperatorKickParam[] memory operatorKickParams,
        bytes32 salt,
        uint256 expiry
    ) public view returns (bytes32) {
        // calculate the digest hash
        return _hashTypedDataV4(keccak256(abi.encode(OPERATOR_CHURN_APPROVAL_TYPEHASH, registeringOperatorId, operatorKickParams, salt, expiry)));
    }
}
