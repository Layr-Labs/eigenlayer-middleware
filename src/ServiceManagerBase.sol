// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from
    "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

import {ServiceManagerBaseStorage} from "./ServiceManagerBaseStorage.sol";
import {IServiceManager} from "./interfaces/IServiceManager.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";

import {BitmapUtils} from "./libraries/BitmapUtils.sol";
import {LibMergeSort} from "./libraries/LibMergeSort.sol";

/**
 * @title Minimal implementation of a ServiceManager-type contract.
 * This contract can be inherited from or simply used as a point-of-reference.
 * @author Layr Labs, Inc.
 */
abstract contract ServiceManagerBase is ServiceManagerBaseStorage {
    using BitmapUtils for *;

    uint256 public constant SLASHER_PROPOSAL_DELAY = 7 days;

    /// @notice when applied to a function, only allows the RegistryCoordinator to call it
    modifier onlyRegistryCoordinator() {
        require(msg.sender == address(_registryCoordinator), OnlyRegistryCoordinator());
        _;
    }

    /// @notice only rewardsInitiator can call createAVSRewardsSubmission
    modifier onlyRewardsInitiator() {
        _checkRewardsInitiator();
        _;
    }

    /// @notice only slasher can call functions with this modifier
    modifier onlySlasher() {
        _checkSlasher();
        _;
    }

    /// @notice only StakeRegistry can call functions with this modifier
    modifier onlyStakeRegistry() {
        _checkStakeRegistry();
        _;
    }

    /// @notice Sets the (immutable) `_registryCoordinator` address
    constructor(
        IAVSDirectory __avsDirectory,
        IRewardsCoordinator __rewardsCoordinator,
        IRegistryCoordinator __registryCoordinator,
        IStakeRegistry __stakeRegistry,
        IAllocationManager __allocationManager
    )
        ServiceManagerBaseStorage(
            __avsDirectory,
            __rewardsCoordinator,
            __registryCoordinator,
            __stakeRegistry,
            __allocationManager
        )
    {
        _disableInitializers();
    }

    function __ServiceManagerBase_init(
        address initialOwner,
        address _rewardsInitiator,
        address _slasher
    ) internal virtual onlyInitializing {
        _transferOwnership(initialOwner);
        _setRewardsInitiator(_rewardsInitiator);
        _setSlasher(_slasher);
    }

    /**
     * @notice Updates the metadata URI for the AVS
     * @param _metadataURI is the metadata URI for the AVS
     * @dev only callable by the owner
     */
    function updateAVSMetadataURI(string memory _metadataURI) public virtual onlyOwner {
        _avsDirectory.updateAVSMetadataURI(_metadataURI);
    }

    function slashOperator(IAllocationManager.SlashingParams memory params) external onlySlasher {
        _allocationManager.slashOperator(address(this), params);
    }

    /**
     * @notice Creates a new rewards submission to the EigenLayer RewardsCoordinator contract, to be split amongst the
     * set of stakers delegated to operators who are registered to this `avs`
     * @param rewardsSubmissions The rewards submissions being created
     * @dev Only callable by the permissioned rewardsInitiator address
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

    function createOperatorSets(IAllocationManager.CreateSetParams[] memory params) external onlyRegistryCoordinator {
        _allocationManager.createOperatorSets(address(this), params);
    }

    function addStrategyToOperatorSet(uint32 operatorSetId, IStrategy[] memory strategies) external onlyStakeRegistry {
        _allocationManager.addStrategiesToOperatorSet(address(this), operatorSetId, strategies);
    }

    function removeStrategiesFromOperatorSet(uint32 operatorSetId, IStrategy[] memory strategies) external onlyStakeRegistry {
        _allocationManager.removeStrategiesFromOperatorSet(address(this), operatorSetId, strategies);
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
        _avsDirectory.registerOperatorToAVS(operator, operatorSignature);
    }

    /**
     * @notice Forwards a call to EigenLayer's AVSDirectory contract to confirm operator deregistration from the AVS
     * @param operator The address of the operator to deregister.
     */
    function deregisterOperatorFromAVS(address operator) public virtual onlyRegistryCoordinator {
        _avsDirectory.deregisterOperatorFromAVS(operator);
    }

    /**
     * @notice Forwards a call to EigenLayer's AVSDirectory contract to deregister an operator from operator sets
     * @param operator The address of the operator to deregister.
     * @param operatorSetIds The IDs of the operator sets.
     */
    function deregisterOperatorFromOperatorSets(
        address operator,
        uint32[] calldata operatorSetIds
    ) public virtual onlyRegistryCoordinator {
        _allocationManager.deregisterFromOperatorSets(IAllocationManagerTypes.DeregisterParams({
            operator: operator,
            avs: address(this),
            operatorSetIds: operatorSetIds
        }));
    }

    /**
     * @notice Sets the rewards initiator address
     * @param newRewardsInitiator The new rewards initiator address
     * @dev only callable by the owner
     */
    function setRewardsInitiator(address newRewardsInitiator) external onlyOwner {
        _setRewardsInitiator(newRewardsInitiator);
    }

    /**
     * @notice Sets the AVS registrar address in the AllocationManager
     * @param registrar The new AVS registrar address
     * @dev Only callable by the registry coordinator
     */
    function setAVSRegistrar(IAVSRegistrar registrar) external onlyRegistryCoordinator {
        _allocationManager.setAVSRegistrar(address(this), registrar);
    }

    /**
     * @notice Proposes a new slasher address
     * @param newSlasher The new slasher address
     * @dev only callable by the owner
     */
    function proposeNewSlasher(address newSlasher) external onlyOwner {
        _proposeNewSlasher(newSlasher);
    }

    /**
     * @notice Accepts the proposed slasher address after the delay period
     * @dev only callable by the owner
     */
    function acceptProposedSlasher() external onlyOwner {
        require(
            block.timestamp >= slasherProposalTimestamp + SLASHER_PROPOSAL_DELAY,
            DelayPeriodNotPassed()
        );
        _setSlasher(proposedSlasher);
        delete proposedSlasher;
    }

    function _setRewardsInitiator(address newRewardsInitiator) internal {
        emit RewardsInitiatorUpdated(rewardsInitiator, newRewardsInitiator);
        rewardsInitiator = newRewardsInitiator;
    }

    function _proposeNewSlasher(address newSlasher) internal {
        proposedSlasher = newSlasher;
        slasherProposalTimestamp = block.timestamp;
        emit SlasherProposed(newSlasher, slasherProposalTimestamp);
    }

    function _setSlasher(address newSlasher) internal {
        emit SlasherUpdated(slasher, newSlasher);
        slasher = newSlasher;
    }

    /**
     * @notice Returns the list of strategies that the AVS supports for restaking
     * @dev This function is intended to be called off-chain
     * @dev No guarantee is made on uniqueness of each element in the returned array.
     *      The off-chain service should do that validation separately
     */
    function getRestakeableStrategies() external virtual view returns (address[] memory) {
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
        virtual
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

    /// @notice Returns the EigenLayer AVSDirectory contract.
    function avsDirectory() external view override returns (address) {
        return address(_avsDirectory);
    }

    function allocationManager() external view override returns (address) {
        return address(_allocationManager);
    }

    function _checkRewardsInitiator() internal view {
        require(msg.sender == rewardsInitiator, OnlyRewardsInitiator());
    }

    function _checkStakeRegistry() internal view {
        require(msg.sender == address(_stakeRegistry), OnlyStakeRegistry());
    }

    function _checkSlasher() internal view {
        require(msg.sender == slasher, OnlySlasher());
    }
}
