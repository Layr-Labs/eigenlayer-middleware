// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IRewardsCoordinator} from
    "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";

import {IOperatorSetManager, IStrategy} from "./interfaces/IOperatorSetManager.sol"; // should be later changed to be import from core
import {ServiceManagerBaseStorage} from "./ServiceManagerBaseStorage.sol";
import {IServiceManager} from "./interfaces/IServiceManager.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {BitmapUtils} from "./libraries/BitmapUtils.sol";

/**
 * @title Minimal implementation of a ServiceManager-type contract.
 * This contract can be inherited from or simply used as a point-of-reference.
 * @author Layr Labs, Inc.
 */
abstract contract ServiceManagerBase is OwnableUpgradeable, ServiceManagerBaseStorage {
    using BitmapUtils for *;

    /// @notice when applied to a function, only allows the RegistryCoordinator to call it
    modifier onlyRegistryCoordinator() {
        require(
            msg.sender == address(_registryCoordinator),
            "ServiceManagerBase.onlyRegistryCoordinator: caller is not the registry coordinator"
        );
        _;
    }

    /// @notice when applied to a function, only allows the StakeRegistry to call it
    modifier onlyStakeRegistry() {
        require(
            msg.sender == address(_stakeRegistry),
            "ServiceManagerBase.onlyStakeRegistry: caller is not the stake registry"
        );
        _;
    }

    /// @notice only rewardsInitiator can call createAVSRewardsSubmission
    modifier onlyRewardsInitiator() {
        require(
            msg.sender == rewardsInitiator,
            "ServiceManagerBase.onlyRewardsInitiator: caller is not the rewards initiator"
        );
        _;
    }

    /// @notice Sets the (immutable) `_registryCoordinator` address
    constructor(
        IOperatorSetManager __operatorSetManager,
        IRewardsCoordinator __rewardsCoordinator,
        IRegistryCoordinator __registryCoordinator,
        IStakeRegistry __stakeRegistry
    )
        ServiceManagerBaseStorage(
            __operatorSetManager,
            __rewardsCoordinator,
            __registryCoordinator,
            __stakeRegistry
        )
    {
        _disableInitializers();
    }

    function __ServiceManagerBase_init(
        address initialOwner,
        address _rewardsInitiator
    ) internal virtual onlyInitializing {
        _transferOwnership(initialOwner);
        _setRewardsInitiator(_rewardsInitiator);
        isStrategiesMigrated = true;
    }

    /// TODO: natspec
    function addStrategiesToOperatorSet(
        uint32 operatorSetID,
        IStrategy[] calldata strategies
    ) external onlyStakeRegistry {
        _operatorSetManager.addStrategiesToOperatorSet(operatorSetID, strategies);
    }

    /// TODO: natspec
    function removeStrategiesFromOperatorSet(
        uint32 operatorSetID,
        IStrategy[] calldata strategies
    ) external onlyStakeRegistry {
        _operatorSetManager.removeStrategiesFromOperatorSet(operatorSetID, strategies);
    }

    /// @notice migrates all existing operators and strategies to operator sets
    function migrateStrategiesToOperatorSets() external {
        require(
            !isStrategiesMigrated,
            "ServiceManagerBase.migrateStrategiesToOperatorSets: already migrated"
        );
        uint8 quorumCount = _registryCoordinator.quorumCount();
        for (uint8 i = 0; i < quorumCount; ++i) {
            uint256 numStrategies = _stakeRegistry.strategyParamsLength(i);
            IStrategy[] memory strategies = new IStrategy[](numStrategies);
            // get the strategies for the quorum/operator set
            for (uint256 j = 0; j < numStrategies; ++j) {
                IStrategy strategy = _stakeRegistry.strategyParamsByIndex(i, j).strategy;
                strategies[j] = strategy;
            }

            _operatorSetManager.addStrategiesToOperatorSet(uint32(i), strategies);
            emit OperatorSetStrategiesMigrated(uint32(i), strategies);
        }
        isStrategiesMigrated = true;
    }

    /**
     * @notice the operator needs to provide a signature over the operatorSetIds they will be registering
     * for. This can be called externally by getOperatorSetIds
     */
    function migrateOperatorToOperatorSets(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory signature
    ) external {
        require(
            !isOperatorMigrated[operator],
            "ServiceManagerBase.migrateOperatorToOperatorSets: already migrated"
        );
        uint32[] memory operatorSetIds = getOperatorSetIds(operator);

        _operatorSetManager.registerOperatorToOperatorSets(operator, operatorSetIds, signature);
        emit OperatorMigratedToOperatorSets(operator, operatorSetIds);
    }

    /**
     * @notice Once strategies have been migrated and operators have been migrated to operator sets.
     * The ServiceManager owner can eject any operators that have yet to completely migrate fully to operator sets.
     * This final step of the migration process will ensure the full migration of all operators to operator sets.
     * @param operators The list of operators to eject for the given OperatorSet
     * @param operatorSet The OperatorSet to eject the operators from
     * @dev The RegistryCoordinator MUST set this ServiceManager contract to be the ejector address for this call to succeed
     */
    function ejectNonmigratedOperators(
        address[] calldata operators,
        IOperatorSetManager.OperatorSet calldata operatorSet
    ) external onlyOwner {
        require(
            operatorSet.avs == address(this),
            "ServiceManagerBase.ejectNonmigratedOperators: operatorSet is not for this AVS"
        );
        require(
            operatorSet.id < _registryCoordinator.quorumCount(),
            "ServiceManagerBase.ejectNonmigratedOperators: operatorSet does not exist"
        );
        for (uint256 i = 0; i < operators.length; ++i) {
            require(
                !_operatorSetManager.isOperatorInOperatorSet(operators[i], operatorSet),
                "ServiceManagerBase.removeNonmigratedOperators: operator already registered to operator set"
            );
            bytes32 operatorId = _registryCoordinator.getOperatorId(operators[i]);
            uint192 quorumBitmap = _registryCoordinator.getCurrentQuorumBitmap(operatorId);
            bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);
            _registryCoordinator.ejectOperator(operators[i], quorumNumbers);
        }
    }

    /**
     * @notice Updates the metadata URI for the AVS
     * @param _metadataURI is the metadata URI for the AVS
     * @dev only callable by the owner
     */
    function updateAVSMetadataURI(string memory _metadataURI) public virtual onlyOwner {
        _operatorSetManager.updateAVSMetadataURI(_metadataURI);
    }

    /**
     * @notice Creates a new rewards submission to the EigenLayer RewardsCoordinator contract, to be split amongst the
     * set of stakers delegated to operators who are registered to this `avs`
     * @param rewardsSubmissions The rewards submissions being created
     * @dev Only callabe by the permissioned rewardsInitiator address
     * @dev The duration of the `rewardsSubmission` cannot exceed `MAX_REWARDS_DURATION`
     * @dev The tokens are sent to the `RewardsCoordinator` contract
     * @dev Strategies must be in ascending order of addresses to check for duplicates
     * @dev This function will revert if the `rewardsSubmission` is malformed,
     * e.g. if the `strategies` and `weights` arrays are of non-equal lengths
     */
    function createAVSRewardsSubmission(
        IRewardsCoordinator.RewardsSubmission[] calldata rewardsSubmissions
    ) public virtual onlyRewardsInitiator {
        for (uint256 i = 0; i < rewardsSubmissions.length; ++i) {
            // transfer token to ServiceManager and approve RewardsCoordinator to transfer again
            // in createAVSRewardsSubmission() call
            rewardsSubmissions[i].token.transferFrom(
                msg.sender, address(this), rewardsSubmissions[i].amount
            );
            uint256 allowance =
                rewardsSubmissions[i].token.allowance(address(this), address(_rewardsCoordinator));
            rewardsSubmissions[i].token.approve(
                address(_rewardsCoordinator), rewardsSubmissions[i].amount + allowance
            );
        }

        _rewardsCoordinator.createAVSRewardsSubmission(rewardsSubmissions);
    }

    /**
     * @notice Forwards a call to EigenLayer's AVSDirectory contract to confirm operator registration with the AVS
     * @param operator The address of the operator to register.
     * @param operatorSignature The signature, salt, and expiry of the operator's signature.
     */
    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) public virtual onlyRegistryCoordinator {
        _operatorSetManager.registerOperatorToAVS(operator, operatorSignature);
    }

    /**
     * @notice Called by this AVS's RegistryCoordinator to register an operator for its registering operatorSets
     *
     * @param operator the address of the operator to be added to the operator set
     * @param quorumNumbers quorums/operatorSetIds to add the operator to
     * @param signature the signature of the operator on their intent to register
     * @dev msg.sender is used as the AVS
     * @dev operator must not have a pending a deregistration from the operator set
     * @dev if this is the first operator set in the AVS that the operator is
     * registering for, a OperatorAVSRegistrationStatusUpdated event is emitted with
     * a REGISTERED status
     */
    function registerOperatorToOperatorSets(
        address operator,
        bytes calldata quorumNumbers,
        ISignatureUtils.SignatureWithSaltAndExpiry memory signature
    ) external onlyRegistryCoordinator {
        uint32[] memory operatorSetIds = quorumsToOperatorSetIds(quorumNumbers);
        _operatorSetManager.registerOperatorToOperatorSets(operator, operatorSetIds, signature);
    }

    /**
     * @notice Called by this AVS's RegistryCoordinator to deregister an operator for its operatorSets
     *
     * @param operator the address of the operator to be removed from the
     * operator set
     * @param quorumNumbers the quorumNumbers/operatorSetIds to deregister the operator for
     *
     * @dev msg.sender is used as the AVS
     * @dev operator must be registered for msg.sender AVS and the given
     * operator set
     * @dev if this removes operator from all operator sets for the msg.sender AVS
     * then an OperatorAVSRegistrationStatusUpdated event is emitted with a DEREGISTERED
     * status
     */
    function deregisterOperatorFromOperatorSets(
        address operator,
        bytes calldata quorumNumbers
    ) external onlyRegistryCoordinator {
        uint32[] memory operatorSetIds = quorumsToOperatorSetIds(quorumNumbers);
        _operatorSetManager.deregisterOperatorFromOperatorSets(operator, operatorSetIds);
    }

    /**
     * @notice Sets the rewards initiator address
     * @param newRewardsInitiator The new rewards initiator address
     * @dev only callable by the owner
     */
    function setRewardsInitiator(address newRewardsInitiator) external onlyOwner {
        _setRewardsInitiator(newRewardsInitiator);
    }

    function _setRewardsInitiator(address newRewardsInitiator) internal {
        emit RewardsInitiatorUpdated(rewardsInitiator, newRewardsInitiator);
        rewardsInitiator = newRewardsInitiator;
    }

    /**
     * @notice Returns the list of strategies that the AVS supports for restaking
     * @dev This function is intended to be called off-chain
     * @dev No guarantee is made on uniqueness of each element in the returned array.
     *      The off-chain service should do that validation separately
     */
    function getRestakeableStrategies() external view returns (address[] memory) {
        uint256 quorumCount = _registryCoordinator.quorumCount();

        if (quorumCount == 0) {
            return new address[](0);
        }

        uint256 strategyCount;
        for (uint256 i = 0; i < quorumCount; i++) {
            strategyCount += _stakeRegistry.strategyParamsLength(uint8(i));
        }

        address[] memory restakedStrategies = new address[](strategyCount);
        uint256 index = 0;
        for (uint256 i = 0; i < _registryCoordinator.quorumCount(); i++) {
            uint256 strategyParamsLength = _stakeRegistry.strategyParamsLength(uint8(i));
            for (uint256 j = 0; j < strategyParamsLength; j++) {
                restakedStrategies[index] =
                    address(_stakeRegistry.strategyParamsByIndex(uint8(i), j).strategy);
                index++;
            }
        }
        return restakedStrategies;
    }

    /**
     * @notice Returns the list of strategies that the operator has potentially restaked on the AVS
     * @param operator The address of the operator to get restaked strategies for
     * @dev This function is intended to be called off-chain
     * @dev No guarantee is made on whether the operator has shares for a strategy in a quorum or uniqueness
     *      of each element in the returned array. The off-chain service should do that validation separately
     */
    function getOperatorRestakedStrategies(address operator)
        external
        view
        returns (address[] memory)
    {
        bytes32 operatorId = _registryCoordinator.getOperatorId(operator);
        uint192 operatorBitmap = _registryCoordinator.getCurrentQuorumBitmap(operatorId);

        if (operatorBitmap == 0 || _registryCoordinator.quorumCount() == 0) {
            return new address[](0);
        }

        // Get number of strategies for each quorum in operator bitmap
        bytes memory operatorRestakedQuorums = BitmapUtils.bitmapToBytesArray(operatorBitmap);
        uint256 strategyCount;
        for (uint256 i = 0; i < operatorRestakedQuorums.length; i++) {
            strategyCount += _stakeRegistry.strategyParamsLength(uint8(operatorRestakedQuorums[i]));
        }

        // Get strategies for each quorum in operator bitmap
        address[] memory restakedStrategies = new address[](strategyCount);
        uint256 index = 0;
        for (uint256 i = 0; i < operatorRestakedQuorums.length; i++) {
            uint8 quorum = uint8(operatorRestakedQuorums[i]);
            uint256 strategyParamsLength = _stakeRegistry.strategyParamsLength(quorum);
            for (uint256 j = 0; j < strategyParamsLength; j++) {
                restakedStrategies[index] =
                    address(_stakeRegistry.strategyParamsByIndex(quorum, j).strategy);
                index++;
            }
        }
        return restakedStrategies;
    }

    /// @notice converts the quorumNumbers array to operatorSetIds array
    function quorumsToOperatorSetIds(bytes memory quorumNumbers)
        internal
        pure
        returns (uint32[] memory)
    {
        uint256 quorumCount = quorumNumbers.length;
        uint32[] memory operatorSetIds = new uint32[](quorumCount);
        for (uint256 i = 0; i < quorumCount; i++) {
            operatorSetIds[i] = uint32(uint8(quorumNumbers[i]));
        }
        return operatorSetIds;
    }

    /// @notice Returns the operator set IDs for the given operator address by querying the RegistryCoordinator
    function getOperatorSetIds(address operator) public view returns (uint32[] memory) {
        bytes32 operatorId = _registryCoordinator.getOperatorId(operator);
        uint192 operatorBitmap = _registryCoordinator.getCurrentQuorumBitmap(operatorId);
        bytes memory operatorQuorums = BitmapUtils.bitmapToBytesArray(operatorBitmap);
        return quorumsToOperatorSetIds(operatorQuorums);
    }

    /// @notice Returns the EigenLayer OperatorSetManager contract.
    function operatorSetManager() external view override returns (address) {
        return address(_operatorSetManager);
    }
}
