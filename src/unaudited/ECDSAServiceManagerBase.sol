// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";

import {IServiceManager} from "../interfaces/IServiceManager.sol";
import {IServiceManagerUI} from "../interfaces/IServiceManagerUI.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IPaymentCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IPaymentCoordinator.sol";
import {Quorum} from "../interfaces/IECDSAStakeRegistryEventsAndErrors.sol";
import {ECDSAStakeRegistry} from "../unaudited/ECDSAStakeRegistry.sol";

abstract contract ECDSAServiceManagerBase is
    IServiceManager,
    OwnableUpgradeable
{
    address public immutable stakeRegistry;
    address public immutable avsDirectory;
    address internal immutable paymentCoordinator;
    address internal immutable delegationManager;

    /**
     * @dev Ensures that the function is only callable by the `stakeRegistry` contract.
     * This is used to restrict certain registration and deregistration functionality to the `stakeRegistry`
     */
    modifier onlyStakeRegistry() {
        require(
            msg.sender == stakeRegistry,
            "ECDSAServiceManagerBase.onlyStakeRegistry: caller is not the stakeRegistry"
        );
        _;
    }

    constructor(
        address _avsDirectory,
        address _stakeRegistry,
        address _paymentCoordinator,
        address _delegationManager
    ) {
        avsDirectory = _avsDirectory;
        stakeRegistry = _stakeRegistry;
        paymentCoordinator = _paymentCoordinator;
        delegationManager = _delegationManager;
        _disableInitializers();
    }

    /**
     * @dev Initializes the base service manager by transferring ownership to the initial owner.
     * @param initialOwner The address to which the ownership of the contract will be transferred.
     */
    function __ServiceManagerBase_init(
        address initialOwner
    ) internal onlyInitializing {
        _transferOwnership(initialOwner);
    }

    /// @inheritdoc IServiceManagerUI
    function updateAVSMetadataURI(
        string memory _metadataURI
    ) external onlyOwner {
        IAVSDirectory(avsDirectory).updateAVSMetadataURI(_metadataURI);
    }

    /// @inheritdoc IServiceManagerUI
    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external onlyStakeRegistry {
        IAVSDirectory(avsDirectory).registerOperatorToAVS(
            operator,
            operatorSignature
        );
    }

    /// @inheritdoc IServiceManagerUI
    function deregisterOperatorFromAVS(
        address operator
    ) external onlyStakeRegistry {
        IAVSDirectory(avsDirectory).deregisterOperatorFromAVS(operator);
    }

    /**
     * @notice Retrieves the addresses of all strategies that are part of the current quorum.
     * @dev Fetches the quorum configuration from the ECDSAStakeRegistry and extracts the strategy addresses.
     * @return strategies An array of addresses representing the strategies in the current quorum.
     */
    function getRestakeableStrategies()
        external
        view
        returns (address[] memory)
    {
        Quorum memory quorum = ECDSAStakeRegistry(stakeRegistry).quorum();
        address[] memory strategies = new address[](quorum.strategies.length);
        for (uint256 i = 0; i < quorum.strategies.length; i++) {
            strategies[i] = address(quorum.strategies[i].strategy);
        }
        return strategies;
    }

    /**
     * @notice Retrieves the addresses of strategies where the operator has restaked.
     * @dev This function fetches the quorum details from the ECDSAStakeRegistry, retrieves the operator's shares for each strategy,
     * and filters out strategies with non-zero shares indicating active restaking by the operator.
     * @param _operator The address of the operator whose restaked strategies are to be retrieved.
     * @return restakedStrategies An array of addresses of strategies where the operator has active restakes.
     */
    function getOperatorRestakedStrategies(
        address _operator
    ) external view returns (address[] memory) {
        Quorum memory quorum = ECDSAStakeRegistry(stakeRegistry).quorum();
        uint256 count = quorum.strategies.length;
        IStrategy[] memory strategies = new IStrategy[](count);
        for (uint256 i; i < count; i++) {
            strategies[i] = quorum.strategies[i].strategy;
        }
        uint256[] memory shares = IDelegationManager(delegationManager)
            .getOperatorShares(_operator, strategies);

        address[] memory activeStrategies = new address[](count);
        uint256 activeCount;
        for (uint256 i; i < count; i++) {
            if (shares[i] > 0) {
                activeCount++;
            }
        }

        // Resize the array to fit only the active strategies
        address[] memory restakedStrategies = new address[](activeCount);
        for (uint256 j = 0; j < count; j++) {
            if (shares[j] > 0) {
                restakedStrategies[j] = activeStrategies[j];
            }
        }

        return restakedStrategies;
    }

    /// @inheritdoc IServiceManager
    function payForRange(
        IPaymentCoordinator.RangePayment[] calldata rangePayments
    ) public virtual onlyOwner {
        for (uint256 i = 0; i < rangePayments.length; ++i) {
            rangePayments[i].token.transferFrom(
                msg.sender,
                address(this),
                rangePayments[i].amount
            );
            rangePayments[i].token.approve(
                paymentCoordinator,
                rangePayments[i].amount
            );
        }

        IPaymentCoordinator(paymentCoordinator).payForRange(rangePayments);
    }

    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[50] private __GAP;
}
