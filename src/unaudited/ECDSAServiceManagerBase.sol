// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IServiceManager} from "../interfaces/IServiceManager.sol";
import {IServiceManagerUI} from "../interfaces/IServiceManagerUI.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IRewardsCoordinator} from
    "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IECDSAStakeRegistryTypes} from "../interfaces/IECDSAStakeRegistry.sol";
import {ECDSAStakeRegistry} from "../unaudited/ECDSAStakeRegistry.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

abstract contract ECDSAServiceManagerBase is IServiceManager, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice Address of the stake registry contract, which manages registration and stake recording.
    address public immutable stakeRegistry;

    /// @notice Address of the AVS directory contract, which manages AVS-related data for registered operators.
    address public immutable avsDirectory;

    /// @notice Address of the AllocationManager contract
    address public immutable allocationManager;

    /// @notice Address of the rewards coordinator contract, which handles rewards distributions.
    address internal immutable rewardsCoordinator;

    /// @notice Address of the delegation manager contract, which manages staker delegations to operators.
    address internal immutable delegationManager;

    /// @notice Address of the rewards initiator, which is allowed to create AVS rewards submissions.
    address public rewardsInitiator;

    /**
     * @dev Ensures that the function is only callable by the `stakeRegistry` contract.
     * This is used to restrict certain registration and deregistration functionality to the `stakeRegistry`
     */
    modifier onlyStakeRegistry() {
        require(msg.sender == stakeRegistry, OnlyStakeRegistry());
        _;
    }

    /**
     * @dev Ensures that the function is only callable by the `rewardsInitiator`.
     */
    modifier onlyRewardsInitiator() {
        _checkRewardsInitiator();
        _;
    }

    function _checkRewardsInitiator() internal view {
        require(msg.sender == rewardsInitiator, OnlyRewardsInitiator());
    }

    /**
     * @dev Constructor for ECDSAServiceManagerBase, initializing immutable contract addresses and disabling initializers.
     * @param _avsDirectory The address of the AVS directory contract, managing AVS-related data for registered operators.
     * @param _stakeRegistry The address of the stake registry contract, managing registration and stake recording.
     * @param _rewardsCoordinator The address of the rewards coordinator contract, handling rewards distributions.
     * @param _delegationManager The address of the delegation manager contract, managing staker delegations to operators.
     */
    constructor(
        address _avsDirectory,
        address _stakeRegistry,
        address _rewardsCoordinator,
        address _delegationManager,
        address _allocationManager
    ) {
        avsDirectory = _avsDirectory;
        stakeRegistry = _stakeRegistry;
        rewardsCoordinator = _rewardsCoordinator;
        delegationManager = _delegationManager;
        allocationManager = _allocationManager;
        _disableInitializers();
    }

    /**
     * @dev Initializes the base service manager by transferring ownership to the initial owner.
     * @param initialOwner The address to which the ownership of the contract will be transferred.
     * @param _rewardsInitiator The address which is allowed to create AVS rewards submissions.
     */
    function __ServiceManagerBase_init(
        address initialOwner,
        address _rewardsInitiator
    ) internal virtual onlyInitializing {
        _transferOwnership(initialOwner);
        _setRewardsInitiator(_rewardsInitiator);
    }

    /// @inheritdoc IServiceManagerUI
    function updateAVSMetadataURI(
        string memory _metadataURI
    ) external virtual onlyOwner {
        _updateAVSMetadataURI(_metadataURI);
    }

    /// @inheritdoc IServiceManager
    function createAVSRewardsSubmission(
        IRewardsCoordinator.RewardsSubmission[] calldata rewardsSubmissions
    ) external virtual onlyRewardsInitiator {
        _createAVSRewardsSubmission(rewardsSubmissions);
    }

    function createOperatorDirectedAVSRewardsSubmission(
        IRewardsCoordinator.OperatorDirectedRewardsSubmission[] calldata
            operatorDirectedRewardsSubmissions
    ) external virtual onlyRewardsInitiator {
        _createOperatorDirectedAVSRewardsSubmission(operatorDirectedRewardsSubmissions);
    }

    function setClaimerFor(
        address claimer
    ) external virtual onlyOwner {
        _setClaimerFor(claimer);
    }

    /// @inheritdoc IServiceManagerUI
    function registerOperatorToAVS(
        address operator,
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature
    ) external virtual onlyStakeRegistry {
        _registerOperatorToAVS(operator, operatorSignature);
    }

    /// @inheritdoc IServiceManagerUI
    function deregisterOperatorFromAVS(
        address operator
    ) external virtual onlyStakeRegistry {
        _deregisterOperatorFromAVS(operator);
    }

    /// @inheritdoc IServiceManagerUI
    function getRestakeableStrategies() external view virtual returns (address[] memory) {
        return _getRestakeableStrategies();
    }

    /// @inheritdoc IServiceManagerUI
    function getOperatorRestakedStrategies(
        address _operator
    ) external view virtual returns (address[] memory) {
        return _getOperatorRestakedStrategies(_operator);
    }

    /**
     * @notice Forwards the call to update AVS metadata URI in the AVSDirectory contract.
     * @dev This internal function is a proxy to the `updateAVSMetadataURI` function of the AVSDirectory contract.
     * @param _metadataURI The new metadata URI to be set.
     */
    function _updateAVSMetadataURI(
        string memory _metadataURI
    ) internal virtual {
        IAVSDirectory(avsDirectory).updateAVSMetadataURI(_metadataURI);
    }

    /**
     * @notice Forwards the call to register an operator in the AVSDirectory contract.
     * @dev This internal function is a proxy to the `registerOperatorToAVS` function of the AVSDirectory contract.
     * @param operator The address of the operator to register.
     * @param operatorSignature The signature, salt, and expiry details of the operator's registration.
     */
    function _registerOperatorToAVS(
        address operator,
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature
    ) internal virtual {
        IAVSDirectory(avsDirectory).registerOperatorToAVS(operator, operatorSignature);
    }

    /**
     * @notice Forwards the call to deregister an operator from the AVSDirectory contract.
     * @dev This internal function is a proxy to the `deregisterOperatorFromAVS` function of the AVSDirectory contract.
     * @param operator The address of the operator to deregister.
     */
    function _deregisterOperatorFromAVS(
        address operator
    ) internal virtual {
        IAVSDirectory(avsDirectory).deregisterOperatorFromAVS(operator);
    }

    /**
     * @notice Processes a batch of rewards submissions by transferring the specified amounts from the sender to this contract and then approving the RewardsCoordinator to use these amounts.
     * @dev This function handles the transfer and approval of tokens necessary for rewards submissions. It then delegates the actual rewards logic to the RewardsCoordinator contract.
     * @param rewardsSubmissions An array of `RewardsSubmission` structs, each representing rewards for a specific range.
     */
    function _createAVSRewardsSubmission(
        IRewardsCoordinator.RewardsSubmission[] calldata rewardsSubmissions
    ) internal virtual {
        for (uint256 i = 0; i < rewardsSubmissions.length; ++i) {
            rewardsSubmissions[i].token.safeTransferFrom(
                msg.sender, address(this), rewardsSubmissions[i].amount
            );
            rewardsSubmissions[i].token.safeIncreaseAllowance(
                rewardsCoordinator, rewardsSubmissions[i].amount
            );
        }

        IRewardsCoordinator(rewardsCoordinator).createAVSRewardsSubmission(rewardsSubmissions);
    }

    /**
     * @notice Creates a new operator-directed rewards submission, to be split amongst the operators and
     * set of stakers delegated to operators who are registered to this `avs`.
     * @param operatorDirectedRewardsSubmissions The operator-directed rewards submissions being created.
     */
    function _createOperatorDirectedAVSRewardsSubmission(
        IRewardsCoordinator.OperatorDirectedRewardsSubmission[] calldata
            operatorDirectedRewardsSubmissions
    ) internal virtual {
        for (uint256 i = 0; i < operatorDirectedRewardsSubmissions.length; ++i) {
            // Calculate total amount of token to transfer
            uint256 totalAmount = 0;
            for (
                uint256 j = 0; j < operatorDirectedRewardsSubmissions[i].operatorRewards.length; ++j
            ) {
                totalAmount += operatorDirectedRewardsSubmissions[i].operatorRewards[j].amount;
            }

            // Transfer token to ServiceManager and approve RewardsCoordinator to transfer again
            // in createOperatorDirectedAVSRewardsSubmission() call
            operatorDirectedRewardsSubmissions[i].token.safeTransferFrom(
                msg.sender, address(this), totalAmount
            );
            operatorDirectedRewardsSubmissions[i].token.safeIncreaseAllowance(
                rewardsCoordinator, totalAmount
            );
        }

        IRewardsCoordinator(rewardsCoordinator).createOperatorDirectedAVSRewardsSubmission(
            address(this), operatorDirectedRewardsSubmissions
        );
    }

    /**
     * @notice Forwards a call to Eigenlayer's RewardsCoordinator contract to set the address of the entity that can call `processClaim` on behalf of this contract.
     * @param claimer The address of the entity that can call `processClaim` on behalf of the earner.
     */
    function _setClaimerFor(
        address claimer
    ) internal virtual {
        IRewardsCoordinator(rewardsCoordinator).setClaimerFor(claimer);
    }

    /**
     * @notice Retrieves the addresses of all strategies that are part of the current quorum.
     * @dev Fetches the quorum configuration from the ECDSAStakeRegistry and extracts the strategy addresses.
     * @return strategies An array of addresses representing the strategies in the current quorum.
     */
    function _getRestakeableStrategies() internal view virtual returns (address[] memory) {
        IECDSAStakeRegistryTypes.Quorum memory quorum = ECDSAStakeRegistry(stakeRegistry).quorum();
        address[] memory strategies = new address[](quorum.strategies.length);
        for (uint256 i = 0; i < quorum.strategies.length; i++) {
            strategies[i] = address(quorum.strategies[i].strategy);
        }
        return strategies;
    }

    /**
     * @notice Sets the AVS registrar address in the AllocationManager
     * @param registrar The new AVS registrar address
     * @dev Only callable by the registry coordinator
     */
    function setAVSRegistrar(
        IAVSRegistrar registrar
    ) external onlyOwner {
        IAllocationManager(allocationManager).setAVSRegistrar(address(this), registrar);
    }

    /**
     * @notice Retrieves the addresses of strategies where the operator has restaked.
     * @dev This function fetches the quorum details from the ECDSAStakeRegistry, retrieves the operator's shares for each strategy,
     * and filters out strategies with non-zero shares indicating active restaking by the operator.
     * @param _operator The address of the operator whose restaked strategies are to be retrieved.
     * @return restakedStrategies An array of addresses of strategies where the operator has active restakes.
     */
    function _getOperatorRestakedStrategies(
        address _operator
    ) internal view virtual returns (address[] memory) {
        IECDSAStakeRegistryTypes.Quorum memory quorum = ECDSAStakeRegistry(stakeRegistry).quorum();
        uint256 count = quorum.strategies.length;
        IStrategy[] memory strategies = new IStrategy[](count);
        for (uint256 i; i < count; i++) {
            strategies[i] = quorum.strategies[i].strategy;
        }
        uint256[] memory shares =
            IDelegationManager(delegationManager).getOperatorShares(_operator, strategies);

        uint256 activeCount;
        for (uint256 i; i < count; i++) {
            if (shares[i] > 0) {
                activeCount++;
            }
        }

        // Resize the array to fit only the active strategies
        address[] memory restakedStrategies = new address[](activeCount);
        uint256 index;
        for (uint256 j = 0; j < count; j++) {
            if (shares[j] > 0) {
                restakedStrategies[index] = address(strategies[j]);
                index++;
            }
        }

        return restakedStrategies;
    }

    /**
     * @notice Sets the rewards initiator address.
     * @param newRewardsInitiator The new rewards initiator address.
     * @dev Only callable by the owner.
     */
    function setRewardsInitiator(
        address newRewardsInitiator
    ) external onlyOwner {
        _setRewardsInitiator(newRewardsInitiator);
    }

    function _setRewardsInitiator(
        address newRewardsInitiator
    ) internal {
        emit RewardsInitiatorUpdated(rewardsInitiator, newRewardsInitiator);
        rewardsInitiator = newRewardsInitiator;
    }

    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[49] private __GAP;
}
