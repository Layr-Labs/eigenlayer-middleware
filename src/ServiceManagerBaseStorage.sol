// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

import {IServiceManager} from "./interfaces/IServiceManager.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";

import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IPaymentCoordinator} from
    "eigenlayer-contracts/src/contracts/interfaces/IPaymentCoordinator.sol";

/**
 * @title Storage variables for the `IndexRegistry` contract.
 * @author Layr Labs, Inc.
 * @notice This storage contract is separate from the logic to simplify the upgrade process.
 */
abstract contract ServiceManagerBaseStorage is Initializable, IServiceManager {
    /**
     *
     *                            CONSTANTS AND IMMUTABLES
     *
     */
    /// @notice The RegistryCoordinator contract for this middleware
    IAVSDirectory internal immutable _avsDirectory;
    IPaymentCoordinator internal immutable _paymentCoordinator;
    IRegistryCoordinator internal immutable _registryCoordinator;
    IStakeRegistry internal immutable _stakeRegistry;

    /**
     *
     *                            STATE VARIABLES
     *
     */
    address public paymentInitiator;

    /// @notice Sets the (immutable) `_registryCoordinator` address
    constructor(
        IAVSDirectory __avsDirectory,
        IPaymentCoordinator __paymentCoordinator,
        IRegistryCoordinator __registryCoordinator,
        IStakeRegistry __stakeRegistry
    ) {
        _avsDirectory = __avsDirectory;
        _paymentCoordinator = __paymentCoordinator;
        _registryCoordinator = __registryCoordinator;
        _stakeRegistry = __stakeRegistry;
        _disableInitializers();
    }

    // storage gap for upgradeability
    uint256[47] private __GAP;
}
