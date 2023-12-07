// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {ISlasher} from "eigenlayer-contracts/src/contracts/interfaces/ISlasher.sol";
import {Pausable} from "eigenlayer-contracts/src/contracts/permissions/Pausable.sol";

import {BLSSignatureChecker} from "src/BLSSignatureChecker.sol";

import {IRegistryCoordinator} from "src/interfaces/IRegistryCoordinator.sol";
import {IServiceManager} from "src/interfaces/IServiceManager.sol";

/**
 * @title Base implementation of `IServiceManager` interface, designed to be inherited from by more complex ServiceManagers.
 * @author Layr Labs, Inc.
 * @notice This contract is used for:
 * - proxying calls to the Slasher contract
 * - implementing the two most important functionalities of a ServiceManager:
 *  - freezing operators as the result of various "challenges"
 *  - defining the latestServeUntilBlock which is used by the Slasher to determine whether a withdrawal can be completed
 */
abstract contract ServiceManagerBase is
    IServiceManager,
    Initializable,
    OwnableUpgradeable,
    BLSSignatureChecker,
    Pausable
{
    /// @notice Called in the event of challenge resolution, in order to forward a call to the Slasher, which 'freezes' the `operator`.
    /// @dev This function should contain slashing logic, to make sure operators are not needlessly being slashed
    //       hence it is marked as virtual and must be implemented in each avs' respective service manager contract
    function freezeOperator(address operatorAddr) external virtual;

    ISlasher public immutable slasher;

    /// @notice when applied to a function, ensures that the function is only callable by the `registryCoordinator`.
    modifier onlyRegistryCoordinator() {
        require(
            msg.sender == address(registryCoordinator),
            "onlyRegistryCoordinator: not from registry coordinator"
        );
        _;
    }

    /// @notice when applied to a function, ensures that the function is only callable by the `registryCoordinator`.
    /// or by StakeRegistry
    modifier onlyRegistryCoordinatorOrStakeRegistry() {
        require(
            (msg.sender == address(registryCoordinator)) ||
                (msg.sender ==
                    address(
                        IRegistryCoordinator(
                            address(registryCoordinator)
                        ).stakeRegistry()
                    )),
            "onlyRegistryCoordinatorOrStakeRegistry: not from registry coordinator or stake registry"
        );
        _;
    }

    constructor(
        IRegistryCoordinator _registryCoordinator,
        ISlasher _slasher
    ) BLSSignatureChecker(_registryCoordinator) {
        slasher = _slasher;
        _disableInitializers();
    }

    function initialize(
        IPauserRegistry _pauserRegistry,
        address initialOwner
    ) public initializer {
        _initializePauser(_pauserRegistry, UNPAUSE_ALL);
        _transferOwnership(initialOwner);
    }

    // VIEW FUNCTIONS

    /// @dev need to override function here since its defined in both these contracts
    function owner()
        public
        view
        override(OwnableUpgradeable, IServiceManager)
        returns (address)
    {
        return OwnableUpgradeable.owner();
    }
}
