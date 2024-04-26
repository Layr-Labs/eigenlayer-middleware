// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";

import {IServiceManager} from "../interfaces/IServiceManager.sol";
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

    function __ServiceManagerBase_init(
        address initialOwner
    ) internal onlyInitializing {
        _transferOwnership(initialOwner);
    }

    function updateAVSMetadataURI(
        string memory _metadataURI
    ) external onlyOwner {
        IAVSDirectory(avsDirectory).updateAVSMetadataURI(_metadataURI);
    }

    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external onlyStakeRegistry {
        IAVSDirectory(avsDirectory).registerOperatorToAVS(
            operator,
            operatorSignature
        );
    }

    function deregisterOperatorFromAVS(
        address operator
    ) external onlyStakeRegistry {
        IAVSDirectory(avsDirectory).deregisterOperatorFromAVS(operator);
    }

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
