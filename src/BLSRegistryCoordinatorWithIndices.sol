// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

import "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import "eigenlayer-contracts/src/contracts/interfaces/ISlasher.sol";
import "src/contracts/libraries/BN254.sol";
import "eigenlayer-contracts/src/contracts/libraries/EIP1271SignatureUtils.sol";
import "src/libraries/BitmapUtils.sol";
import "eigenlayer-contracts/src/contracts/permissions/Pausable.sol";

import "src/interfaces/IBLSRegistryCoordinatorWithIndices.sol";
import "src/interfaces/ISocketUpdater.sol";
import "src/interfaces/IServiceManager.sol";
import "src/interfaces/IBLSPubkeyRegistry.sol";
import "src/interfaces/IStakeRegistry.sol";
import "src/interfaces/IIndexRegistry.sol";
import "src/interfaces/IRegistryCoordinator.sol";

/**
 * @title A `RegistryCoordinator` that has three registries:
 *      1) a `StakeRegistry` that keeps track of operators' stakes
 *      2) a `BLSPubkeyRegistry` that keeps track of operators' BLS public keys and aggregate BLS public keys for each quorum
 *      3) an `IndexRegistry` that keeps track of an ordered list of operators for each quorum
 * 
 * @author Layr Labs, Inc.
 */
contract BLSRegistryCoordinatorWithIndices is EIP712, Initializable, IBLSRegistryCoordinatorWithIndices, ISocketUpdater, Pausable {
    using BN254 for BN254.G1Point;

    /// @notice The EIP-712 typehash for the `DelegationApproval` struct used by the contract
    bytes32 public constant OPERATOR_CHURN_APPROVAL_TYPEHASH =
        keccak256("OperatorChurnApproval(bytes32 registeringOperatorId,OperatorKickParam[] operatorKickParams)OperatorKickParam(address operator,BN254.G1Point pubkey,bytes32[] operatorIdsToSwap)BN254.G1Point(uint256 x,uint256 y)");
    /// @notice The maximum value of a quorum bitmap
    uint256 internal constant MAX_QUORUM_BITMAP = type(uint192).max;
    /// @notice The basis point denominator
    uint16 internal constant BIPS_DENOMINATOR = 10000;
    /// @notice Index for flag that pauses operator registration
    uint8 internal constant PAUSED_REGISTER_OPERATOR = 0;
    /// @notice Index for flag that pauses operator deregistration
    uint8 internal constant PAUSED_DEREGISTER_OPERATOR = 1;
    /// @notice The maximum number of quorums this contract supports
    uint8 internal constant MAX_QUORUM_COUNT = 192;

    /// @notice the EigenLayer Slasher
    ISlasher public immutable slasher;
    /// @notice the Service Manager for the service that this contract is coordinating
    IServiceManager public immutable serviceManager;
    /// @notice the BLS Pubkey Registry contract that will keep track of operators' BLS public keys
    IBLSPubkeyRegistry public immutable blsPubkeyRegistry;
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
    mapping(address => Operator) internal _operatorInfo;
    /// @notice whether the salt has been used for an operator churn approval
    mapping(bytes32 => bool) public isChurnApproverSaltUsed;

    /// @notice the dynamic-length array of the registries this coordinator is coordinating
    address[] public registries;
    /// @notice the address of the entity allowed to sign off on operators getting kicked out of the AVS during registration
    address public churnApprover;
    /// @notice the address of the entity allowed to eject operators from the AVS
    address public ejector;

    modifier onlyServiceManagerOwner {
        require(msg.sender == serviceManager.owner(), "BLSRegistryCoordinatorWithIndices.onlyServiceManagerOwner: caller is not the service manager owner");
        _;
    }

    modifier onlyEjector {
        require(msg.sender == ejector, "BLSRegistryCoordinatorWithIndices.onlyEjector: caller is not the ejector");
        _;
    }

    modifier quorumExists(uint8 quorumNumber) {
        require(
            quorumNumber < quorumCount, 
            "BLSRegistryCoordinatorWithIndices.quorumExists: quorum does not exist"
        );
        _;
    }

    constructor(
        ISlasher _slasher,
        IServiceManager _serviceManager,
        IStakeRegistry _stakeRegistry,
        IBLSPubkeyRegistry _blsPubkeyRegistry,
        IIndexRegistry _indexRegistry
    ) EIP712("AVSRegistryCoordinator", "v0.0.1") {
        slasher = _slasher;
        serviceManager = _serviceManager;
        stakeRegistry = _stakeRegistry;
        blsPubkeyRegistry = _blsPubkeyRegistry;
        indexRegistry = _indexRegistry;
    }

    function initialize(
        address _churnApprover,
        address _ejector,
        IPauserRegistry _pauserRegistry,
        uint256 _initialPausedStatus,
        OperatorSetParam[] memory _operatorSetParams,
        uint96[] memory _minimumStakes,
        IStakeRegistry.StrategyAndWeightingMultiplier[][] memory _strategyParams
    ) external initializer {
        require(
            _operatorSetParams.length == _minimumStakes.length && _minimumStakes.length == _strategyParams.length,
            "BLSRegistryCoordinatorWithIndices.initialize: input length mismatch"
        );
        
        // Initialize roles
        _initializePauser(_pauserRegistry, _initialPausedStatus);
        _setChurnApprover(_churnApprover);
        _setEjector(_ejector);

        // Add registry contracts to the registries array
        registries.push(address(stakeRegistry));
        registries.push(address(blsPubkeyRegistry));
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
     * @notice Registers msg.sender as an operator with the middleware
     * @param quorumNumbers are the bytes representing the quorum numbers that the operator is registering for
     * @param pubkey is the BLS public key of the operator
     * @param socket is the socket of the operator
     */
    function registerOperator(
        bytes calldata quorumNumbers,
        BN254.G1Point memory pubkey,
        string calldata socket
    ) external onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) {
        uint32[] memory numOperatorsPerQuorum = _registerOperator({
            operator: msg.sender, 
            quorumNumbers: quorumNumbers, 
            pubkey: pubkey, 
            socket: socket
        });

        for (uint256 i = 0; i < numOperatorsPerQuorum.length; i++) {
            require(
                numOperatorsPerQuorum[i] <= _quorumParams[uint8(quorumNumbers[i])].maxOperatorCount,
                "BLSRegistryCoordinatorWithIndices.registerOperator: quorum is overfilled"
            );
        }
    }

    /**
     * @notice Registers msg.sender as an operator with the middleware when the quorum operator limit is full. To register 
     * while maintaining the limit, the operator chooses another registered operator with lower stake to kick.
     * @param quorumNumbers are the bytes representing the quorum numbers that the operator is registering for
     * @param pubkey is the BLS public key of the operator
     * @param operatorKickParams are the parameters for the deregistration of the operator that is being kicked from each 
     * quorum that will be filled after the operator registers. These parameters should include an operator, their pubkey, 
     * and ids of the operators to swap with the kicked operator. 
     * @param churnApproverSignature is the signature of the churnApprover on the operator kick params
     */
    function registerOperatorWithChurn(
        bytes calldata quorumNumbers, 
        BN254.G1Point memory pubkey,
        string calldata socket,
        OperatorKickParam[] calldata operatorKickParams,
        SignatureWithSaltAndExpiry memory churnApproverSignature
    ) external onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) {
        // register the operator
        uint32[] memory numOperatorsPerQuorum = _registerOperator({
            operator: msg.sender,
            quorumNumbers: quorumNumbers,
            pubkey: pubkey,
            socket: socket
        });

        // get the registering operator's operatorId and set the operatorIdsToSwap to it because the registering operator is the one with the greatest index
        bytes32[] memory operatorIdsToSwap = new bytes32[](1);
        operatorIdsToSwap[0] = pubkey.hashG1Point();

        // verify the churnApprover's signature
        _verifyChurnApproverSignature({
            registeringOperatorId: operatorIdsToSwap[0],
            operatorKickParams: operatorKickParams,
            churnApproverSignature: churnApproverSignature
        });

        uint256 operatorToKickParamsIndex = 0;
        // kick the operators
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            // check that the quorum has reached the max operator count
            {
                uint8 quorumNumber = uint8(quorumNumbers[i]);
                OperatorSetParam memory operatorSetParam = _quorumParams[quorumNumber];
                // if the number of operators for the quorum is less than or equal to the max operator count, 
                // then the quorum has not reached the max operator count
                if(numOperatorsPerQuorum[i] <= operatorSetParam.maxOperatorCount) {
                    continue;
                }

                require(
                    operatorKickParams[operatorToKickParamsIndex].quorumNumber == quorumNumber, 
                    "BLSRegistryCoordinatorWithIndices.registerOperatorWithChurn: quorumNumber not the same as signed"
                );

                // get the total stake for the quorum
                uint96 totalStakeForQuorum = stakeRegistry.getCurrentTotalStakeForQuorum(quorumNumber);
                bytes32 operatorToKickId = _operatorInfo[operatorKickParams[i].operator].operatorId;
                uint96 operatorToKickStake = stakeRegistry.getCurrentOperatorStakeForQuorum(operatorToKickId, quorumNumber);
                uint96 registeringOperatorStake = stakeRegistry.getCurrentOperatorStakeForQuorum(operatorIdsToSwap[0], quorumNumber);

                // check the registering operator has more than the kick BIPs of the operator to kick's stake
                require(
                    registeringOperatorStake > operatorToKickStake * operatorSetParam.kickBIPsOfOperatorStake / BIPS_DENOMINATOR,
                    "BLSRegistryCoordinatorWithIndices.registerOperatorWithChurn: registering operator has less than kickBIPsOfOperatorStake"
                );
                
                // check the that the operator to kick has less than the kick BIPs of the total stake
                require(
                    operatorToKickStake < totalStakeForQuorum * operatorSetParam.kickBIPsOfTotalStake / BIPS_DENOMINATOR,
                    "BLSRegistryCoordinatorWithIndices.registerOperatorWithChurn: operator to kick has more than kickBIPSOfTotalStake"
                );

                // increment the operatorToKickParamsIndex
                operatorToKickParamsIndex++;
            }
            
            // kick the operator
            _deregisterOperator({
                operator: operatorKickParams[i].operator,
                quorumNumbers: quorumNumbers[i:i+1],
                pubkey: operatorKickParams[i].pubkey 
            });
        }
    }

    /**
     * @notice Deregisters the msg.sender as an operator from the middleware
     * @param quorumNumbers are the bytes representing the quorum numbers that the operator is registered for
     * @param pubkey is the BLS public key of the operator
     */
    function deregisterOperator(
        bytes calldata quorumNumbers,
        BN254.G1Point memory pubkey
    ) external onlyWhenNotPaused(PAUSED_DEREGISTER_OPERATOR) {
        _deregisterOperator({
            operator: msg.sender, 
            quorumNumbers: quorumNumbers, 
            pubkey: pubkey
        });
    }

    /**
     * @notice Updates the socket of the msg.sender given they are a registered operator
     * @param socket is the new socket of the operator
     */
    function updateSocket(string memory socket) external {
        require(_operatorInfo[msg.sender].status == OperatorStatus.REGISTERED, "BLSRegistryCoordinatorWithIndices.updateSocket: operator is not registered");
        emit OperatorSocketUpdate(_operatorInfo[msg.sender].operatorId, socket);
    }

    /*******************************************************************************
                            EXTERNAL FUNCTIONS - EJECTOR
    *******************************************************************************/

    /**
     * @notice Ejects the provided operator from the provided quorums from the AVS
     * @param operator is the operator to eject
     * @param quorumNumbers are the quorum numbers to eject the operator from
     * @param pubkey is the BLS public key of the operator
     */
    function ejectOperator(
        address operator, 
        bytes calldata quorumNumbers, 
        BN254.G1Point memory pubkey
    ) external onlyEjector {
        _deregisterOperator({
            operator: operator, 
            quorumNumbers: quorumNumbers, 
            pubkey: pubkey
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
        IStakeRegistry.StrategyAndWeightingMultiplier[] memory strategyParams
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

    /// @return numOperatorsPerQuorum is the list of number of operators per quorum in quorumNumberss
    function _registerOperator(
        address operator, 
        bytes calldata quorumNumbers, 
        BN254.G1Point memory pubkey, 
        string memory socket
    ) internal virtual returns(uint32[] memory) {        
        // Create and validate bitmap from quorumNumbers
        uint256 quorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers);
        require(quorumBitmap <= MAX_QUORUM_BITMAP, "BLSRegistryCoordinatorWithIndices._registerOperator: bitmap exceeds max bitmap size");
        require(quorumBitmap != 0, "BLSRegistryCoordinatorWithIndices._registerOperator: bitmap cannot be 0");
        
        /**
         * Register the operator with the BLSPubkeyRegistry, StakeRegistry, and IndexRegistry. Retrieves:
         * - operatorId: hash of the operator's pubkey, unique to the operator
         * - numOperatorsPerQuorum: list of # operators for each quorum in `quorumNumbers`
         */
        bytes32 operatorId = blsPubkeyRegistry.registerOperator(operator, quorumNumbers, pubkey);
        stakeRegistry.registerOperator(operator, operatorId, quorumNumbers);
        uint32[] memory numOperatorsPerQuorum = indexRegistry.registerOperator(operatorId, quorumNumbers);

        /**
         * If the operator has an existing bitmap history, combine the last entry with `quorumBitmap`
         * and set its `nextUpdateBlockNumber` to the current block.
         * Skip this step if the `nextUpdateBlockNumber` is already set for the last entry in the operator's bitmap history,
         * as this indicates that the operator previously completely deregistered, and thus is no longer registered for any quorums.
         */
        uint256 historyLength = _operatorBitmapHistory[operatorId].length;
        if (historyLength != 0 && _operatorBitmapHistory[operatorId][historyLength - 1].nextUpdateBlockNumber == 0) {
            uint256 prevQuorumBitmap = _operatorBitmapHistory[operatorId][historyLength - 1].quorumBitmap;
            require(prevQuorumBitmap & quorumBitmap == 0, "BLSRegistryCoordinatorWithIndices._registerOperator: operator already registered for some quorums being registered for");
            // new stored quorumBitmap is the previous quorumBitmap or'd with the new quorumBitmap to register for
            quorumBitmap |= prevQuorumBitmap;

            _operatorBitmapHistory[operatorId][historyLength - 1].nextUpdateBlockNumber = uint32(block.number);
        }

        // set the operatorId to quorum bitmap history
        _operatorBitmapHistory[operatorId].push(QuorumBitmapUpdate({
            updateBlockNumber: uint32(block.number),
            nextUpdateBlockNumber: 0,
            quorumBitmap: uint192(quorumBitmap)
        }));

        // if the operator is not already registered, then they are registering for the first time
        if (_operatorInfo[operator].status != OperatorStatus.REGISTERED) {
            _operatorInfo[operator] = Operator({
                operatorId: operatorId,
                status: OperatorStatus.REGISTERED
            });

            emit OperatorRegistered(operator, operatorId);
        }

        // record a stake update not bonding the operator at all (unbonded at 0), because they haven't served anything yet
        // serviceManager.recordFirstStakeUpdate(operator, 0);

        emit OperatorSocketUpdate(operatorId, socket);

        return numOperatorsPerQuorum;
    }

    function _deregisterOperator(
        address operator, 
        bytes calldata quorumNumbers, 
        BN254.G1Point memory pubkey
    ) internal virtual {
        /**
         * Fetch the operator's id and status. Check that:
         * - the operator is currently registered
         * - the operatorId matches the provided pubkey hash
         */
        Operator storage operatorInfo = _operatorInfo[operator];
        bytes32 operatorId = operatorInfo.operatorId;
        require(operatorInfo.status == OperatorStatus.REGISTERED, "BLSRegistryCoordinatorWithIndices._deregisterOperator: operator is not registered");
        require(operatorId == pubkey.hashG1Point(), "BLSRegistryCoordinatorWithIndices._deregisterOperator: operatorId does not match pubkey hash");
        
        // Create and validate bitmap of quorums to remove
        uint256 quorumsToRemoveBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers);
        require(quorumsToRemoveBitmap <= MAX_QUORUM_BITMAP, "BLSRegistryCoordinatorWithIndices._deregisterOperator: bitmap exceeds max bitmap size");
        require(quorumsToRemoveBitmap != 0, "BLSRegistryCoordinatorWithIndices._deregisterOperator: bitmap cannot be 0");

        // Get the operator's last quorum bitmap and update its "next" pointer to the current block
        // TODO - change to use new history update pattern
        QuorumBitmapUpdate storage lastUpdate = _latestBitmapUpdate(operatorId);
        lastUpdate.nextUpdateBlockNumber = uint32(block.number);
        uint192 previousBitmap = lastUpdate.quorumBitmap;

        // Remove quorums the operator isn't registered for and check that the result isn't empty
        quorumsToRemoveBitmap = previousBitmap & quorumsToRemoveBitmap;
        bytes memory quorumNumbersToRemove = BitmapUtils.bitmapToBytesArray(quorumsToRemoveBitmap);
        require(quorumNumbersToRemove.length != 0, "BLSRegistryCoordinatorWithIndices._deregisterOperator: operator is not registered for any of the provided quorums");

        // Check if the operator is completely deregistering
        bool completeDeregistration = previousBitmap == quorumsToRemoveBitmap;

        // Deregister operator with each of the registry contracts:
        blsPubkeyRegistry.deregisterOperator(operator, quorumNumbersToRemove, pubkey);
        stakeRegistry.deregisterOperator(operatorId, quorumNumbersToRemove);
        indexRegistry.deregisterOperator(operatorId, quorumNumbersToRemove);
        
        // If the operator still has active quorums, push a bitmap update.
        // Otherwise, set them to deregistered
        // TODO - change this to update history regardless
        if (!completeDeregistration) {
            _operatorBitmapHistory[operatorId].push(QuorumBitmapUpdate({
                updateBlockNumber: uint32(block.number),
                nextUpdateBlockNumber: 0,
                quorumBitmap: previousBitmap & ~uint192(quorumsToRemoveBitmap) // this removes the quorumsToRemoveBitmap from the quorumBitmapBeforeUpdate
            }));
        } else {
            operatorInfo.status = OperatorStatus.DEREGISTERED;
            emit OperatorDeregistered(operator, operatorId);
        }
    }

    /// @notice verifies churnApprover's signature on operator churn approval and increments the churnApprover nonce
    function _verifyChurnApproverSignature(
        bytes32 registeringOperatorId, 
        OperatorKickParam[] memory operatorKickParams, 
        SignatureWithSaltAndExpiry memory churnApproverSignature
    ) internal {
        // make sure the salt hasn't been used already
        require(!isChurnApproverSaltUsed[churnApproverSignature.salt], "BLSRegistryCoordinatorWithIndices._verifyChurnApproverSignature: churnApprover salt already used");
        require(churnApproverSignature.expiry >= block.timestamp, "BLSRegistryCoordinatorWithIndices._verifyChurnApproverSignature: churnApprover signature expired");   

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
        IStakeRegistry.StrategyAndWeightingMultiplier[] memory strategyParams
    ) internal {
        // Increment the total quorum count. Fails if we're already at the max
        uint8 prevQuorumCount = quorumCount;
        require(prevQuorumCount < MAX_QUORUM_COUNT, "BLSRegistryCoordinatorWithIndices.createQuorum: max quorums reached");
        quorumCount = prevQuorumCount + 1;
        
        // The previous count is the new quorum's number
        uint8 quorumNumber = prevQuorumCount;

        // Initialize the quorum here and in each registry
        _setOperatorSetParams(quorumNumber, operatorSetParams);
        stakeRegistry.initializeQuorum(quorumNumber, minimumStake, strategyParams);
        indexRegistry.initializeQuorum(quorumNumber);
        blsPubkeyRegistry.initializeQuorum(quorumNumber);
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

    /**
     * @notice Fetch the most recent bitmap update for an operatorId
     * @dev This method reverts (underflow) if the operator does not have any bitmap updates
     */
    function _latestBitmapUpdate(bytes32 operatorId) internal view returns (QuorumBitmapUpdate storage) {
        uint256 historyLength = _operatorBitmapHistory[operatorId].length;
        return _operatorBitmapHistory[operatorId][historyLength - 1];
    }

    /*******************************************************************************
                            VIEW FUNCTIONS
    *******************************************************************************/

    /// @notice Returns the operator set params for the given `quorumNumber`
    function getOperatorSetParams(uint8 quorumNumber) external view returns (OperatorSetParam memory) {
        return _quorumParams[quorumNumber];
    }

    /// @notice Returns the operator struct for the given `operator`
    function getOperator(address operator) external view returns (Operator memory) {
        return _operatorInfo[operator];
    }

    /// @notice Returns the operatorId for the given `operator`
    function getOperatorId(address operator) external view returns (bytes32) {
        return _operatorInfo[operator].operatorId;
    }

    /// @notice Returns the operator address for the given `operatorId`
    function getOperatorFromId(bytes32 operatorId) external view returns (address) {
        return blsPubkeyRegistry.getOperatorFromPubkeyHash(operatorId);
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
                        "BLSRegistryCoordinatorWithIndices.getQuorumBitmapIndicesAtBlockNumber: operatorId has no quorumBitmaps at blockNumber"
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
            "BLSRegistryCoordinatorWithIndices.getQuorumBitmapAtBlockNumberByIndex: quorumBitmapUpdate is from after blockNumber"
        );
        // if the next update is at or before the block number, then the quorum provided index is too early
        // if the nex update  block number is 0, then this is the latest update
        require(
            quorumBitmapUpdate.nextUpdateBlockNumber > blockNumber || quorumBitmapUpdate.nextUpdateBlockNumber == 0, 
            "BLSRegistryCoordinatorWithIndices.getQuorumBitmapAtBlockNumberByIndex: quorumBitmapUpdate is from before blockNumber"
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
