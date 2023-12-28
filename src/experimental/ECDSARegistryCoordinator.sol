// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

import {EIP1271SignatureUtils} from "eigenlayer-contracts/src/contracts/libraries/EIP1271SignatureUtils.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {Pausable} from "eigenlayer-contracts/src/contracts/permissions/Pausable.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";

import {ECDSAStakeRegistry} from "./ECDSAStakeRegistry.sol";
import {IServiceManager} from "../interfaces/IServiceManager.sol";
import {BitmapUtils} from "../libraries/BitmapUtils.sol";

/**
 * @title A `RegistryCoordinator` that:
 *      1) keeps track of operators' ECDSA public keys
 *      2) keeps track of an ordered list of operators for each quorum
 *      3) uses an independent `ECDSAStakeRegistry` that keeps track of operators' stakes
 *
 * @author Layr Labs, Inc.
 */
contract ECDSARegistryCoordinator is
    EIP712,
    Initializable,
    Pausable,
    OwnableUpgradeable,
    ISignatureUtils
{
    using BitmapUtils for *;

    // EVENTS

    /// Emits when an operator is registered
    event OperatorRegistered(
        address indexed operator,
        address indexed operatorId
    );

    /// Emits when an operator is deregistered
    event OperatorDeregistered(
        address indexed operator,
        address indexed operatorId
    );

    event EjectorUpdated(address prevEjector, address newEjector);

    /// @notice emitted when all the operators for a quorum are updated at once
    event QuorumBlockNumberUpdated(
        uint8 indexed quorumNumber,
        uint256 blocknumber
    );

    // DATA STRUCTURES
    enum OperatorStatus {
        // default is NEVER_REGISTERED
        NEVER_REGISTERED,
        REGISTERED,
        DEREGISTERED
    }

    // STRUCTS

    /**
     * @notice Data structure for storing info on operators
     */
    struct OperatorInfo {
        // the id of the operator, which is the address associated with the ECDSA private key the operator uses to sign msgs
        // note that the address is the lower 20 bytes of the keccak256 hash of the operator's ECDSA public key
        address operatorId;
        // indicates whether the operator is actively registered for serving the middleware or not
        OperatorStatus status;
    }

    // TODO: document
    struct ECDSAPubkeyRegistrationParams {
        address signingAddress;
        SignatureWithSaltAndExpiry signatureAndExpiry;
    }

    /// @notice The EIP-712 typehash used for registering ECDSA public keys
    bytes32 public constant PUBKEY_REGISTRATION_TYPEHASH =
        keccak256("ECDSAPubkeyRegistration(address operator)");
    /// @notice The maximum value of a quorum bitmap
    uint256 internal constant MAX_QUORUM_BITMAP = type(uint256).max;
    /// @notice Index for flag that pauses operator registration
    uint8 internal constant PAUSED_REGISTER_OPERATOR = 0;
    /// @notice Index for flag that pauses operator deregistration
    uint8 internal constant PAUSED_DEREGISTER_OPERATOR = 1;
    /// @notice Index for flag pausing operator stake updates
    uint8 internal constant PAUSED_UPDATE_OPERATOR = 2;
    /// @notice The maximum number of quorums this contract supports
    uint8 internal constant MAX_QUORUM_COUNT = 192;

    /// @notice the ServiceManager for this AVS, which forwards calls onto EigenLayer's core contracts
    IServiceManager public immutable serviceManager;
    /// @notice the Stake Registry contract that will keep track of operators' stakes
    ECDSAStakeRegistry public immutable stakeRegistry;

    /// @notice the current number of quorums supported by the registry coordinator
    uint8 public quorumCount;
    /// @notice maps operator id => current quorums they are registered for
    mapping(address => uint256) public operatorBitmap;
    /// @notice maps operator address => operator id and status
    mapping(address => OperatorInfo) internal _operatorInfo;
    /// @notice mapping from quorum number to the latest block that all quorums were updated all at once
    mapping(uint8 => uint256) public quorumUpdateBlockNumber;

    // TODO: document
    mapping(address => address) operatorIdToOperator;
    mapping(uint8 => uint32) public totalOperatorsForQuorum;

    /// @notice the address of the entity allowed to eject operators from the AVS
    address public ejector;

    modifier onlyEjector() {
        require(
            msg.sender == ejector,
            "RegistryCoordinator.onlyEjector: caller is not the ejector"
        );
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
        IServiceManager _serviceManager,
        ECDSAStakeRegistry _stakeRegistry
    ) EIP712("AVSRegistryCoordinator", "v0.0.1") {
        serviceManager = _serviceManager;
        stakeRegistry = _stakeRegistry;

        _disableInitializers();
    }

    function initialize(
        address _initialOwner,
        address _ejector,
        IPauserRegistry _pauserRegistry,
        uint256 _initialPausedStatus,
        uint96[] memory _minimumStakes,
        ECDSAStakeRegistry.StrategyParams[][] memory _strategyParams
    ) external initializer {
        require(
            _minimumStakes.length == _strategyParams.length,
            "RegistryCoordinator.initialize: input length mismatch"
        );

        // Initialize roles
        _transferOwnership(_initialOwner);
        _initializePauser(_pauserRegistry, _initialPausedStatus);
        _setEjector(_ejector);

        // Create quorums
        for (uint256 i = 0; i < _minimumStakes.length; i++) {
            _createQuorum(_minimumStakes[i], _strategyParams[i]);
        }
    }

    /*******************************************************************************
                            EXTERNAL FUNCTIONS 
    *******************************************************************************/

    /**
     * @notice Registers msg.sender as an operator for one or more quorums. If any quorum reaches its maximum
     * operator capacity, this method will fail.
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for
     * @param params TODO: document
     * @dev the `params` input param is ignored if the caller has previously registered a public key
     * @param operatorSignature is the signature of the operator used by the AVS to register the operator in the delegation manager
     */
    function registerOperator(
        bytes calldata quorumNumbers,
        ECDSAPubkeyRegistrationParams memory params,
        SignatureWithSaltAndExpiry memory operatorSignature
    ) external onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) {
        /**
         * IF the operator has never registered a pubkey before, THEN register their pubkey
         * OTHERWISE, simply ignore the provided `params` input
         */
        address operatorId = _getOrCreateOperatorId(msg.sender, params);

        // Register the operator in each of the registry contracts
        uint32[] memory numOperatorsPerQuorum = _registerOperator({
            operator: msg.sender,
            operatorId: operatorId,
            quorumNumbers: quorumNumbers,
            operatorSignature: operatorSignature
        }).numOperatorsPerQuorum;
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
    function updateOperators(
        address[] calldata operators
    ) external onlyWhenNotPaused(PAUSED_UPDATE_OPERATOR) {
        for (uint256 i = 0; i < operators.length; i++) {
            address operator = operators[i];
            OperatorInfo memory operatorInfo = _operatorInfo[operator];
            address operatorId = operatorInfo.operatorId;

            // Update the operator's stake for their active quorums
            uint256 currentBitmap = _currentOperatorBitmap(operatorId);
            bytes memory quorumsToUpdate = BitmapUtils.bitmapToBytesArray(
                currentBitmap
            );
            _updateOperator(operator, operatorInfo, quorumsToUpdate);
        }
    }

    /**
     * @notice Updates the stakes of all operators for each of the specified quorums in the StakeRegistry. Each quorum also
     * has their quorumUpdateBlockNumber updated. which is meant to keep track of when operators were last all updated at once.
     * @param operatorsPerQuorum is an array of arrays of operators to update for each quorum. Note that each nested array
     * of operators must be sorted in ascending address order to ensure that all operators in the quorum are updated
     * @param quorumNumbers is an array of quorum numbers to update
     * @dev This method is used to update the stakes of all operators in a quorum at once, rather than individually. Performs
     * sanitization checks on the input array lengths, quorumNumbers existing, and that quorumNumbers are ordered. Function must
     * also not be paused by the PAUSED_UPDATE_OPERATOR flag.
     */
    function updateOperatorsForQuorum(
        address[][] calldata operatorsPerQuorum,
        bytes calldata quorumNumbers
    ) external onlyWhenNotPaused(PAUSED_UPDATE_OPERATOR) {
        uint256 quorumBitmap = uint256(
            BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers, quorumCount)
        );
        require(
            _quorumsAllExist(quorumBitmap),
            "RegistryCoordinator.updateOperatorsForQuorum: some quorums do not exist"
        );
        require(
            operatorsPerQuorum.length == quorumNumbers.length,
            "RegistryCoordinator.updateOperatorsForQuorum: input length mismatch"
        );

        for (uint256 i = 0; i < quorumNumbers.length; ++i) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            address[] calldata currQuorumOperators = operatorsPerQuorum[i];
            require(
                currQuorumOperators.length ==
                    totalOperatorsForQuorum[quorumNumber],
                "RegistryCoordinator.updateOperatorsForQuorum: number of updated operators does not match quorum total"
            );
            address prevOperatorAddress = address(0);
            // Update stakes for each operator in this quorum
            for (uint256 j = 0; j < currQuorumOperators.length; ++j) {
                address operator = currQuorumOperators[j];
                OperatorInfo memory operatorInfo = _operatorInfo[operator];
                address operatorId = operatorInfo.operatorId;
                {
                    uint256 currentBitmap = _currentOperatorBitmap(operatorId);
                    require(
                        BitmapUtils.isSet(currentBitmap, quorumNumber),
                        "RegistryCoordinator.updateOperatorsForQuorum: operator not in quorum"
                    );
                    // Require check is to prevent duplicate operators and that all quorum operators are updated
                    require(
                        operator > prevOperatorAddress,
                        "RegistryCoordinator.updateOperatorsForQuorum: operators array must be sorted in ascending address order"
                    );
                }
                _updateOperator(operator, operatorInfo, quorumNumbers[i:i + 1]);
                prevOperatorAddress = operator;
            }

            // Update timestamp that all operators in quorum have been updated all at once
            quorumUpdateBlockNumber[quorumNumber] = block.number;
            emit QuorumBlockNumberUpdated(quorumNumber, block.number);
        }
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
        _deregisterOperator({operator: operator, quorumNumbers: quorumNumbers});
    }

    /*******************************************************************************
                            EXTERNAL FUNCTIONS - OWNER
    *******************************************************************************/

    /**
     * @notice Creates a quorum and initializes it in each registry contract
     */
    function createQuorum(
        uint96 minimumStake,
        ECDSAStakeRegistry.StrategyParams[] memory strategyParams
    ) external virtual onlyOwner {
        _createQuorum(minimumStake, strategyParams);
    }

    /**
     * @notice Sets the ejector
     * @param _ejector is the address of the ejector
     * @dev only callable by the owner
     */
    function setEjector(address _ejector) external onlyOwner {
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
     * operator's quorum bitmap, and status, then registers them with each registry.
     */
    function _registerOperator(
        address operator,
        address operatorId,
        bytes calldata quorumNumbers,
        SignatureWithSaltAndExpiry memory operatorSignature
    ) internal virtual returns (RegisterResults memory results) {
        /**
         * Get bitmap of quorums to register for and operator's current bitmap. Validate that:
         * - we're trying to register for at least 1 quorum
         * - the operator is not currently registered for any quorums we're registering for
         * Then, calculate the operator's new bitmap after registration
         */
        uint256 quorumsToAdd = uint256(
            BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers, quorumCount)
        );
        uint256 currentBitmap = _currentOperatorBitmap(operatorId);
        require(
            !quorumsToAdd.isEmpty(),
            "RegistryCoordinator._registerOperator: bitmap cannot be 0"
        );
        require(
            _quorumsAllExist(quorumsToAdd),
            "RegistryCoordinator._registerOperator: some quorums do not exist"
        );
        require(
            quorumsToAdd.noBitsInCommon(currentBitmap),
            "RegistryCoordinator._registerOperator: operator already registered for some quorums being registered for"
        );
        uint256 newBitmap = uint256(currentBitmap.plus(quorumsToAdd));

        /**
         * Update operator's bitmap and status. Only update operatorInfo if needed:
         * if we're `REGISTERED`, the operatorId and status are already correct.
         */
        _updateOperatorBitmap({operatorId: operatorId, newBitmap: newBitmap});

        if (_operatorInfo[operator].status != OperatorStatus.REGISTERED) {
            _operatorInfo[operator] = OperatorInfo({
                operatorId: operatorId,
                status: OperatorStatus.REGISTERED
            });

            // Register the operator with the EigenLayer via this AVS's ServiceManager
            serviceManager.registerOperatorToAVS(operator, operatorSignature);

            emit OperatorRegistered(operator, operatorId);
        }

        /**
         * Register the operator with the ECDSAStakeRegistry
         */
        (results.operatorStakes, results.totalStakes) = stakeRegistry
            .registerOperator(operator, operatorId, quorumNumbers);
        results.numOperatorsPerQuorum = new uint32[](quorumNumbers.length);
        for (uint256 i = 0; i < quorumNumbers.length; ++i) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            uint32 newTotalOperatorsForQuorum = totalOperatorsForQuorum[
                quorumNumber
            ] + 1;
            totalOperatorsForQuorum[quorumNumber] = newTotalOperatorsForQuorum;
            results.numOperatorsPerQuorum[i] = newTotalOperatorsForQuorum;
        }

        return results;
    }

    function _getOrCreateOperatorId(
        address operator,
        ECDSAPubkeyRegistrationParams memory params
    ) internal returns (address operatorId) {
        operatorId = _operatorInfo[operator].operatorId;
        if (operatorId == address(0)) {
            operatorId = _registerECDSAPublicKey(
                operator,
                params,
                pubkeyRegistrationMessageHash(operator)
            );
        }
        return operatorId;
    }

    function _registerECDSAPublicKey(
        address operator,
        ECDSAPubkeyRegistrationParams memory params,
        bytes32 _pubkeyRegistrationMessageHash
    ) internal returns (address operatorId) {
        require(
            params.signingAddress != address(0),
            "ECDSARegistryCoordinator._registerECDSAPublicKey: cannot register zero pubkey"
        );
        require(
            _operatorInfo[operator].operatorId == address(0),
            "ECDSARegistryCoordinator._registerECDSAPublicKey: operator already registered pubkey"
        );

        operatorId = params.signingAddress;
        require(
            operatorIdToOperator[operatorId] == address(0),
            "ECDSARegistryCoordinator._registerECDSAPublicKey: public key already registered"
        );

        // check the signature expiry
        require(
            params.signatureAndExpiry.expiry >= block.timestamp,
            "ECDSARegistryCoordinator._registerECDSAPublicKey: signature expired"
        );

        // actually check that the signature is valid
        EIP1271SignatureUtils.checkSignature_EIP1271(
            params.signingAddress,
            _pubkeyRegistrationMessageHash,
            params.signatureAndExpiry.signature
        );

        operatorIdToOperator[operatorId] = operator;

        // TODO: event
        // emit NewPubkeyRegistration(operator, params.pubkeyG1, params.pubkeyG2);
        return operatorId;
    }

    /**
     * @dev Deregister the operator from one or more quorums
     * This method updates the operator's quorum bitmap and status, then deregisters
     * the operator with the ECDSAStakeRegistry
     */
    function _deregisterOperator(
        address operator,
        bytes memory quorumNumbers
    ) internal virtual {
        // Fetch the operator's info and ensure they are registered
        OperatorInfo storage operatorInfo = _operatorInfo[operator];
        address operatorId = operatorInfo.operatorId;
        require(
            operatorInfo.status == OperatorStatus.REGISTERED,
            "RegistryCoordinator._deregisterOperator: operator is not registered"
        );

        /**
         * Get bitmap of quorums to deregister from and operator's current bitmap. Validate that:
         * - we're trying to deregister from at least 1 quorum
         * - the operator is currently registered for any quorums we're trying to deregister from
         * Then, calculate the opreator's new bitmap after deregistration
         */
        uint256 quorumsToRemove = uint256(
            BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers, quorumCount)
        );
        uint256 currentBitmap = _currentOperatorBitmap(operatorId);
        require(
            !quorumsToRemove.isEmpty(),
            "RegistryCoordinator._deregisterOperator: bitmap cannot be 0"
        );
        require(
            _quorumsAllExist(quorumsToRemove),
            "RegistryCoordinator._deregisterOperator: some quorums do not exist"
        );
        require(
            quorumsToRemove.isSubsetOf(currentBitmap),
            "RegistryCoordinator._deregisterOperator: operator is not registered for specified quorums"
        );
        uint256 newBitmap = uint256(currentBitmap.minus(quorumsToRemove));

        /**
         * Update operator's bitmap and status:
         */
        _updateOperatorBitmap({operatorId: operatorId, newBitmap: newBitmap});

        // If the operator is no longer registered for any quorums, update their status and deregister from EigenLayer via this AVS's ServiceManager
        if (newBitmap.isEmpty()) {
            operatorInfo.status = OperatorStatus.DEREGISTERED;
            serviceManager.deregisterOperatorFromAVS(operator);
            emit OperatorDeregistered(operator, operatorId);
        }

        // Deregister operator with each of the registry contracts:
        stakeRegistry.deregisterOperator(operatorId, quorumNumbers);
        for (uint256 i = 0; i < quorumNumbers.length; ++i) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            --totalOperatorsForQuorum[quorumNumber];
        }
    }

    /**
     * @notice update operator stake for specified quorumsToUpdate, and deregister if necessary
     * does nothing if operator is not registered for any quorums.
     */
    function _updateOperator(
        address operator,
        OperatorInfo memory operatorInfo,
        bytes memory quorumsToUpdate
    ) internal {
        if (operatorInfo.status != OperatorStatus.REGISTERED) {
            return;
        }
        address operatorId = operatorInfo.operatorId;
        uint256 quorumsToRemove = stakeRegistry.updateOperatorStake(
            operator,
            operatorId,
            quorumsToUpdate
        );

        if (!quorumsToRemove.isEmpty()) {
            _deregisterOperator({
                operator: operator,
                quorumNumbers: BitmapUtils.bitmapToBytesArray(quorumsToRemove)
            });
        }
    }

    /**
     * @notice Creates and initializes a quorum in each registry contract
     */
    function _createQuorum(
        uint96 minimumStake,
        ECDSAStakeRegistry.StrategyParams[] memory strategyParams
    ) internal {
        // Increment the total quorum count. Fails if we're already at the max
        uint8 prevQuorumCount = quorumCount;
        require(
            prevQuorumCount < MAX_QUORUM_COUNT,
            "RegistryCoordinator.createQuorum: max quorums reached"
        );
        quorumCount = prevQuorumCount + 1;

        // The previous count is the new quorum's number
        uint8 quorumNumber = prevQuorumCount;

        // Initialize the quorum here and in each registry
        stakeRegistry.initializeQuorum(
            quorumNumber,
            minimumStake,
            strategyParams
        );
    }

    /**
     * @notice Record an update to an operator's quorum bitmap.
     * @param newBitmap is the most up-to-date set of bitmaps the operator is registered for
     */
    function _updateOperatorBitmap(
        address operatorId,
        uint256 newBitmap
    ) internal {
        operatorBitmap[operatorId] = newBitmap;
    }

    /**
     * @notice Returns true iff all of the bits in `quorumBitmap` belong to initialized quorums
     */
    function _quorumsAllExist(
        uint256 quorumBitmap
    ) internal view returns (bool) {
        uint256 initializedQuorumBitmap = uint256((1 << quorumCount) - 1);
        return quorumBitmap.isSubsetOf(initializedQuorumBitmap);
    }

    /// @notice Get the most recent bitmap for the operator, returning an empty bitmap if
    /// the operator is not registered.
    function _currentOperatorBitmap(
        address operatorId
    ) internal view returns (uint256) {
        return operatorBitmap[operatorId];
    }

    function _setEjector(address newEjector) internal {
        emit EjectorUpdated(ejector, newEjector);
        ejector = newEjector;
    }

    /*******************************************************************************
                            VIEW FUNCTIONS
    *******************************************************************************/

    /// @notice Returns the operator struct for the given `operator`
    function getOperator(
        address operator
    ) external view returns (OperatorInfo memory) {
        return _operatorInfo[operator];
    }

    /// @notice Returns the operatorId for the given `operator`
    function getOperatorId(address operator) external view returns (address) {
        return _operatorInfo[operator].operatorId;
    }

    /// @notice Returns the operator address for the given `operatorId`
    function getOperatorFromId(
        address operatorId
    ) external view returns (address) {
        return operatorIdToOperator[operatorId];
    }

    /// @notice Returns the status for the given `operator`
    function getOperatorStatus(
        address operator
    ) external view returns (OperatorStatus) {
        return _operatorInfo[operator].status;
    }

    /// @notice Returns the current quorum bitmap for the given `operatorId` or 0 if the operator is not registered for any quorum
    function getCurrentQuorumBitmap(
        address operatorId
    ) external view returns (uint256) {
        return _currentOperatorBitmap(operatorId);
    }

    /**
     * @notice Returns the message hash that an operator must sign to register their ECDSA public key.
     * @param operator is the address of the operator registering their ECDSA public key
     */
    function pubkeyRegistrationMessageHash(
        address operator
    ) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(abi.encode(PUBKEY_REGISTRATION_TYPEHASH, operator))
            );
    }

    /// @dev need to override function here since its defined in both these contracts
    function owner()
        public
        view
        override(OwnableUpgradeable)
        returns (address)
    {
        return OwnableUpgradeable.owner();
    }
}
