// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IStakeRootCompendium} from "eigenlayer-contracts/src/contracts/interfaces/IStakeRootCompendium.sol";
import {ISocketUpdater} from "./interfaces/ISocketUpdater.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {IBLSApkRegistry} from "./interfaces/IBLSApkRegistry.sol";
import {IServiceManager} from "./interfaces/IServiceManager.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";

import {BitmapUtils} from "./libraries/BitmapUtils.sol";
import {BN254} from "./libraries/BN254.sol";
import {SignatureCheckerLib} from "./libraries/SignatureCheckerLib.sol";
import {QuorumBitmapHistoryLib} from "./libraries/QuorumBitmapHistoryLib.sol";

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

import {Pausable} from "eigenlayer-contracts/src/contracts/permissions/Pausable.sol";
import {RegistryCoordinatorStorage} from "./RegistryCoordinatorStorage.sol";

/**
 * @title A `RegistryCoordinator` 
 *
 * @author Layr Labs, Inc.
 */
contract RegistryCoordinator is
    EIP712,
    Initializable,
    Pausable,
    OwnableUpgradeable,
    RegistryCoordinatorStorage,
    ISocketUpdater,
    ISignatureUtils
{
    using BitmapUtils for *;
    using BN254 for BN254.G1Point;

    modifier onlyEjector() {
        _checkEjector();
        _;
    }

    constructor(
        IServiceManager _serviceManager,
        IStakeRootCompendium _stakeRootCompendium,
        IBLSApkRegistry _blsApkRegistry,
        IAVSDirectory _avsDirectory
    )
        RegistryCoordinatorStorage(_serviceManager,_stakeRootCompendium, _blsApkRegistry, _avsDirectory)
        EIP712("AVSRegistryCoordinator", "v0.0.1")
    {
        _disableInitializers();
    }

    /**
     * @param _initialOwner will hold the owner role
     * @param _churnApprover will hold the churnApprover role, which authorizes registering with churn
     * @param _ejector will hold the ejector role, which can force-eject operators from quorums
     * @param _pauserRegistry a registry of addresses that can pause the contract
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
        IPauserRegistry _pauserRegistry,
        uint256 _initialPausedStatus,
        OperatorSetParam[] memory _operatorSetParams,
        uint96[] memory _minimumStakes,
        IStakeRegistry.StrategyParams[][] memory _strategyParams
    ) external initializer {
        require(
            _operatorSetParams.length == _minimumStakes.length
                && _minimumStakes.length == _strategyParams.length,
            "RegistryCoordinator.initialize: input length mismatch"
        );

        // Initialize roles
        _transferOwnership(_initialOwner);
        _initializePauser(_pauserRegistry, _initialPausedStatus);
        _setChurnApprover(_churnApprover);
        _setEjector(_ejector);

        // Create quorums
        for (uint256 i = 0; i < _operatorSetParams.length; i++) {
            // _createQuorum(_operatorSetParams[i], _minimumStakes[i], _strategyParams[i]);
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
     * @param quorumNumber is the quorum number being registered for
     * @param socket is the socket of the operator (typically an IP address)
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @param operatorSignature is the signature of the operator used by the AVS to register the operator in the delegation manager
     * @dev `params` is ignored if the caller has previously registered a public key
     * @dev `operatorSignature` is ignored if the operator's status is already REGISTERED
     */
    function registerOperator(
        uint8 quorumNumber,
        string calldata socket,
        IBLSApkRegistry.PubkeyRegistrationParams calldata params,
        SignatureWithSaltAndExpiry memory operatorSignature
    ) external onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) {
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
        _registerOperator({
            operator: msg.sender,
            operatorId: operatorId,
            quorumNumber: quorumNumber,
            socket: socket,
            operatorSignature: operatorSignature
        });

        // Validate that the new operator count does not exceed the maximum
        // (If it does, an operator needs to be replaced -- see `registerOperatorWithChurn`)
        require(
            avsDirectory.operatorSetMemberCount(address(serviceManager), uint32(quorumNumber)) <= _quorumParams[quorumNumber].maxOperatorCount,
            "RegistryCoordinator.registerOperator: operator exceeds max"
        );
    }

    /**
     * @notice Registers msg.sender as an operator for one or more quorums. If any quorum reaches its maximum operator
     * capacity, `operatorKickParams` is used to replace an old operator with the new one.
     * @param quorumNumber is the quorum number being registered for
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @param operatorKickParams used to determine which operator is removed to maintain quorum capacity as the
     * operator registers for quorums
     * @param churnApproverSignature is the signature of the churnApprover over the `operatorKickParams`
     * @param operatorSignature is the signature of the operator used by the AVS to register the operator in the delegation manager
     * @dev `params` is ignored if the caller has previously registered a public key
     * @dev `operatorSignature` is ignored if the operator's status is already REGISTERED
     */
    function registerOperatorWithChurn(
        uint8 quorumNumber,
        string calldata socket,
        IBLSApkRegistry.PubkeyRegistrationParams calldata params,
        OperatorKickParam calldata operatorKickParams,
        SignatureWithSaltAndExpiry memory churnApproverSignature,
        SignatureWithSaltAndExpiry memory operatorSignature
    ) external onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) {
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
        _registerOperator({
            operator: msg.sender,
            operatorId: operatorId,
            quorumNumber: quorumNumber,
            socket: socket,
            operatorSignature: operatorSignature
        });

        // Check that the quorum's operator count is below the configured maximum. If the max
        // is exceeded, use `operatorKickParams` to deregister an existing operator to make space
        OperatorSetParam memory operatorSetParams = _quorumParams[quorumNumber];

        /**
         * If the new operator count for any quorum exceeds the maximum, validate
         * that churn can be performed, then deregister the specified operator
         */
        if (avsDirectory.operatorSetMemberCount(address(serviceManager), uint32(quorumNumber)) > operatorSetParams.maxOperatorCount) {
            _validateChurn({
                quorumNumber: quorumNumber,
                newOperator: msg.sender,
                kickParams: operatorKickParams,
                setParams: operatorSetParams
            });

            _deregisterOperator(operatorKickParams.operator, quorumNumber);
        }
    }

    /**
     * @notice Deregisters the caller from one or more quorums
     * @param quorumNumber is the quorum number to deregister from
     */
    function deregisterOperator(uint8 quorumNumber)
        external
        onlyWhenNotPaused(PAUSED_DEREGISTER_OPERATOR)
    {
        _deregisterOperator({operator: msg.sender, quorumNumber: quorumNumber});
    }

    /**
     * @notice Updates the socket of the msg.sender given they are a registered operator
     * @param socket is the new socket of the operator
     */
    function updateSocket(string memory socket) external {
        require(
            _operatorInfo[msg.sender].status == OperatorStatus.REGISTERED,
            "RegistryCoordinator.updateSocket: not registered"
        );
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
    function ejectOperator(address operator, uint8[] calldata quorumNumbers) external onlyEjector {
        lastEjectionTimestamp[operator] = block.timestamp;

        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            _deregisterOperator({operator: operator, quorumNumber: quorumNumbers[i]});
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
     * @param amountToFund the amount of ETH to fund the operatorSet with in the StakeRootCompendium
     * @param strategiesAndMultipliers a list of strategies and multipliers used by the StakeRootCompendium to
     * calculate an operator's stake weight for the quorum
     */
    function createQuorum(
        OperatorSetParam memory operatorSetParams,
        uint256 amountToFund,
        IStakeRootCompendium.StrategyAndMultiplier[] memory strategiesAndMultipliers
    ) external virtual onlyOwner {
        _createQuorum(operatorSetParams, amountToFund, strategiesAndMultipliers);
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
    ) external onlyOwner {
        _setOperatorSetParams(quorumNumber, operatorSetParams);
    }

    /**
     * @notice Sets the churnApprover, which approves operator registration with churn
     * (see `registerOperatorWithChurn`)
     * @param _churnApprover the new churn approver
     * @dev only callable by the owner
     */
    function setChurnApprover(address _churnApprover) external onlyOwner {
        _setChurnApprover(_churnApprover);
    }

    /**
     * @notice Sets the ejector, which can force-deregister operators from quorums
     * @param _ejector the new ejector
     * @dev only callable by the owner
     */
    function setEjector(address _ejector) external onlyOwner {
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

    /**
     * @notice Register the operator for one quorum. This method updates the
     * operator's quorum bitmap, socket, and status, then registers them with each registry.
     */
    function _registerOperator(
        address operator,
        bytes32 operatorId,
        uint8 quorumNumber,
        string memory socket,
        SignatureWithSaltAndExpiry memory operatorSignature
    ) internal virtual {
        require(serviceManager.migrationFinalized(), "RegistryCoordinator._registerOperator: migration not finalized");
        /**
         * Get bitmap of quorums to register for and operator's current bitmap. Validate that:
         * - we're trying to register for at least 1 quorum
         * - the quorums we're registering for exist (checked against `quorumCount` in orderedBytesArrayToBitmap)
         * - the operator is not currently registered for any quorums we're registering for
         * Then, calculate the operator's new bitmap after registration
         */
        require(quorumNumber < quorumCount, "RegistryCoordinator._registerOperator: quorum does not exist");
        uint192 quorumsToAdd = uint192(BitmapUtils.setBit(0, quorumNumber));
        uint192 currentBitmap = _currentOperatorBitmap(operatorId);
        require(
            !quorumsToAdd.isEmpty(), "RegistryCoordinator._registerOperator: bitmap empty"
        );
        require(
            quorumsToAdd.noBitsInCommon(currentBitmap),
            "RegistryCoordinator._registerOperator: operator already registered for some quorums being registered for"
        );
        uint192 newBitmap = uint192(currentBitmap.plus(quorumsToAdd));

        // Check that the operator can reregister if ejected
        require(
            lastEjectionTimestamp[operator] + ejectionCooldown < block.timestamp,
            "RegistryCoordinator._registerOperator: operator cannot reregister yet"
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
        }

        // Register the operator with the EigenLayer core contracts via this AVS's ServiceManager
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = quorumNumber;
        serviceManager.registerOperatorToOperatorSets(operator, operatorSetIds, operatorSignature);

        // Register the operator with the BLSApkRegistry, and IndexRegistrys
        blsApkRegistry.registerOperator(operator, quorumNumber);
        serviceManager.setOperatorExtraData(operatorSetIds[0], operator, operatorId);
    }

    /**
     * @notice Checks if the caller is the ejector
     * @dev Reverts if the caller is not the ejector
     */
    function _checkEjector() internal view {
        require(msg.sender == ejector, "RegistryCoordinator.onlyEjector: not ejector");
    }

    /**
     * @notice Checks if a quorum exists
     * @param quorumNumber The quorum number to check
     * @dev Reverts if the quorum does not exist
     */
    function _checkQuorumExists(uint8 quorumNumber) internal view {
        require(
            quorumNumber < quorumCount, "RegistryCoordinator.quorumExists: quorum does not exist"
        );
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
        IBLSApkRegistry.PubkeyRegistrationParams calldata params
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
     * @param quorumNumber `newOperator` is trying to replace an operator in this quorum
     * @param newOperator the incoming operator
     * @param kickParams the quorum number and existing operator to replace
     * @dev the existing operator's registration to this quorum isn't checked here, but
     * if we attempt to deregister them, this will be checked in `_deregisterOperator`
     * @param setParams config for this quorum containing `kickBIPsX` stake proportions
     * mentioned above
     */
    function _validateChurn(
        uint8 quorumNumber,
        address newOperator,
        OperatorKickParam memory kickParams,
        OperatorSetParam memory setParams
    ) internal view {
        address operatorToKick = kickParams.operator;
        require(
            newOperator != operatorToKick, "RegistryCoordinator._validateChurn: cannot churn self"
        );
        require(
            kickParams.quorumNumber == quorumNumber,
            "RegistryCoordinator._validateChurn: quorumNumber not the same as signed"
        );
        IAVSDirectory.OperatorSet memory operatorSet =
            IAVSDirectory.OperatorSet({avs: address(serviceManager), operatorSetId: quorumNumber});

        // Get the registering operator's stake and check that it is above the kick thresholds
        (uint256 rnewOperatorDelegatedStake, uint256 newOperatorSlashableStake) = stakeRootCompendium.getStakes(operatorSet, newOperator);

        // Get the target operator's stake and check that it is below the kick thresholds
        (uint256 operatorToKickDelegatedStake, uint256 operatorToKickSlashableStake) = stakeRootCompendium.getStakes(operatorSet, operatorToKick);

        require(
            newOperatorSlashableStake > _individualKickThreshold(operatorToKickSlashableStake, setParams),
            "RegistryCoordinator._validateChurn: incoming operator has insufficient stake for churn"
        );
    }

    /**
     * @dev Deregister the operator from one or more quorums
     * This method updates the operator's quorum bitmap and status, then deregisters
     * the operator with the BLSApkRegistry, IndexRegistry
     */
    function _deregisterOperator(address operator, uint8 quorumNumber) internal virtual {
        // Fetch the operator's info and ensure they are registered
        OperatorInfo storage operatorInfo = _operatorInfo[operator];
        bytes32 operatorId = operatorInfo.operatorId;
        require(
            operatorInfo.status == OperatorStatus.REGISTERED,
            "RegistryCoordinator._deregisterOperator: not registered"
        );

        /**
         * Get bitmap of quorums to deregister from and operator's current bitmap. Validate that:
         * - we're trying to deregister from at least 1 quorum
         * - the quorums we're deregistering from exist (checked against `quorumCount` in orderedBytesArrayToBitmap)
         * - the operator is currently registered for any quorums we're trying to deregister from
         * Then, calculate the operator's new bitmap after deregistration
         */
        require(quorumNumber < quorumCount, "RegistryCoordinator._deregisterOperator: quorum does not exist");
        uint192 quorumsToRemove = uint192(BitmapUtils.setBit(0, quorumNumber));
        uint192 currentBitmap = _currentOperatorBitmap(operatorId);
        require(
            !quorumsToRemove.isEmpty(),
            "RegistryCoordinator._deregisterOperator: bitmap cannot be 0"
        );
        require(
            quorumsToRemove.isSubsetOf(currentBitmap),
            "RegistryCoordinator._deregisterOperator: not registered for quorum"
        );
        uint192 newBitmap = uint192(currentBitmap.minus(quorumsToRemove));

        // Update operator's bitmap and status
        _updateOperatorBitmap({operatorId: operatorId, newBitmap: newBitmap});


        bool operatorSetAVS = IAVSDirectory(serviceManager.avsDirectory()).isOperatorSetAVS(address(serviceManager));
        if (operatorSetAVS){
            bytes memory quorumBytes = BitmapUtils.bitmapToBytesArray(quorumsToRemove);
            uint32[] memory operatorSetIds = new uint32[](quorumBytes.length);
            uint256 forceDeregistrationCount;
            for (uint256 i = 0; i < quorumBytes.length; i++) {
                /// We need to track forceDeregistrations so we don't pass an id that was already deregistered on the AVSDirectory
                /// but hasnt yet been recorded in the middleware contracts
                if (!avsDirectory.isMember(operator, IAVSDirectory.OperatorSet(address(serviceManager), uint8(quorumBytes[i])))){
                    forceDeregistrationCount++;
                }
                operatorSetIds[i] = uint8(quorumBytes[i]);
            }

            /// Filter out forceDeregistration operator set Ids
            if (forceDeregistrationCount > 0 ){
                uint32[] memory filteredOperatorSetIds = new uint32[](operatorSetIds.length - forceDeregistrationCount);
                uint256 offset;
                for (uint256 i; i < operatorSetIds.length; i++){
                    if (avsDirectory.isMember(operator, IAVSDirectory.OperatorSet(address(serviceManager), operatorSetIds[i]))){
                        filteredOperatorSetIds[i] = operatorSetIds[i+offset];
                    } else {
                        offset++;
                    }
                }
                serviceManager.deregisterOperatorFromOperatorSets(operator, filteredOperatorSetIds);
            } else {
                serviceManager.deregisterOperatorFromOperatorSets(operator, operatorSetIds);

            }


        } else {
            // If the operator is no longer registered for any quorums, update their status and deregister
            // them from the AVS via the EigenLayer core contracts
            if (newBitmap.isEmpty()) {
                operatorInfo.status = OperatorStatus.DEREGISTERED;
                serviceManager.deregisterOperatorFromAVS(operator);
                emit OperatorDeregistered(operator, operatorId);
            }
        }

        // Deregister operator with each of the registry contracts
        blsApkRegistry.deregisterOperator(operator, quorumNumber);
    }

    /**
     * @notice Returns the stake threshold required for an incoming operator to replace an existing operator
     * The incoming operator must have more stake than the return value.
     */
    function _individualKickThreshold(
        uint256 operatorStake,
        OperatorSetParam memory setParams
    ) internal pure returns (uint256) {
        return operatorStake * setParams.kickBIPsOfOperatorStake / BIPS_DENOMINATOR;
    }

    /**
     * @notice Returns the total stake threshold required for an operator to remain in a quorum.
     * The operator must have at least the returned stake amount to keep their position.
     */
    function _totalKickThreshold(
        uint256 totalStake,
        OperatorSetParam memory setParams
    ) internal pure returns (uint256) {
        return totalStake * setParams.kickBIPsOfTotalStake / BIPS_DENOMINATOR;
    }

    /// @notice verifies churnApprover's signature on operator churn approval and increments the churnApprover nonce
    function _verifyChurnApproverSignature(
        address registeringOperator,
        bytes32 registeringOperatorId,
        OperatorKickParam memory operatorKickParams,
        SignatureWithSaltAndExpiry memory churnApproverSignature
    ) internal {
        // make sure the salt hasn't been used already
        require(
            !isChurnApproverSaltUsed[churnApproverSignature.salt],
            "RegistryCoordinator._verifyChurnApproverSignature: salt spent"
        );
        require(
            churnApproverSignature.expiry >= block.timestamp,
            "RegistryCoordinator._verifyChurnApproverSignature: signature expired"
        );

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

    function _createQuorum(
        OperatorSetParam memory operatorSetParams,
        uint256 amountToFund,
        IStakeRootCompendium.StrategyAndMultiplier[] memory strategiesAndMultipliers
    ) internal {
        // Increment the total quorum count. Fails if we're already at the max
        uint8 prevQuorumCount = quorumCount;
        require(
            prevQuorumCount < MAX_QUORUM_COUNT,
            "RegistryCoordinator.createQuorum: max quorums reached"
        );
        require(serviceManager.migrationFinalized(), "RegistryCoordinator.createQuorum: migration not finalized");
        quorumCount = prevQuorumCount + 1;

        // The previous count is the new quorum's number
        uint8 quorumNumber = prevQuorumCount;

        // Initialize the quorum here and in each registry
        _setOperatorSetParams(quorumNumber, operatorSetParams);
        blsApkRegistry.initializeQuorum(quorumNumber);

        // Create an operator set for the new quorum
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = uint32(quorumNumber);
        uint256[] memory amountsToFund = new uint256[](1);
        amountsToFund[0] = amountToFund;
        IStakeRootCompendium.StrategyAndMultiplier[][] memory strategiesAndMultipliers2D =
            new IStakeRootCompendium.StrategyAndMultiplier[][](1);
        strategiesAndMultipliers2D[0] = strategiesAndMultipliers;
        serviceManager.createOperatorSets(operatorSetIds, amountsToFund, strategiesAndMultipliers2D);
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
    function _currentOperatorBitmap(bytes32 operatorId) internal view returns (uint192) {
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
        return QuorumBitmapHistoryLib.getQuorumBitmapIndexAtBlockNumber(_operatorBitmapHistory,blockNumber, operatorId);
    }

    function _setOperatorSetParams(
        uint8 quorumNumber,
        OperatorSetParam memory operatorSetParams
    ) internal {
        require(quorumNumber < quorumCount, "RegistryCoordinator._setOperatorSetParams: quorum does not exist");
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
     *
     *                         VIEW FUNCTIONS
     *
     */

    /// @notice Returns the operator set params for the given `quorumNumber`
    function getOperatorSetParams(uint8 quorumNumber)
        external
        view
        returns (OperatorSetParam memory)
    {
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
    function getOperatorStatus(address operator)
        external
        view
        returns (IRegistryCoordinator.OperatorStatus)
    {
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
        return QuorumBitmapHistoryLib.getQuorumBitmapIndicesAtBlockNumber(_operatorBitmapHistory, blockNumber, operatorIds);
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
        return QuorumBitmapHistoryLib.getQuorumBitmapAtBlockNumberByIndex(_operatorBitmapHistory, operatorId, blockNumber, index);
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
        return _currentOperatorBitmap(operatorId);
    }

    /// @notice Returns the length of the quorum bitmap history for the given `operatorId`
    function getQuorumBitmapHistoryLength(bytes32 operatorId) external view returns (uint256) {
        return _operatorBitmapHistory[operatorId].length;
    }

    /**
     * @notice Public function for the the churnApprover signature hash calculation when operators are being kicked from quorums
     * @param registeringOperatorId The id of the registering operator
     * @param operatorKickParams The parameters needed to kick the operator from the quorum that jas reached its caps
     * @param salt The salt to use for the churnApprover's signature
     * @param expiry The desired expiry time of the churnApprover's signature
     */
    function calculateOperatorChurnApprovalDigestHash(
        address registeringOperator,
        bytes32 registeringOperatorId,
        OperatorKickParam memory operatorKickParams,
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
    function pubkeyRegistrationMessageHash(address operator)
        public
        view
        returns (BN254.G1Point memory)
    {
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
