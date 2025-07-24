// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IServiceManager} from "./interfaces/IServiceManager.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";

abstract contract RegistryCoordinatorStorage is IRegistryCoordinator {
    /**
     *
     *                            CONSTANTS AND IMMUTABLES
     *
     */

    /// @notice the ServiceManager for this AVS, which forwards calls onto EigenLayer's core contracts
    IServiceManager public immutable serviceManager;

    /**
     *
     *                                    STATE
     *
     */

    /// @notice Whether this AVS allows operator sets for creation/registration
    /// @dev If true, then operator sets may be created and operators may register to operator sets via the AllocationManager
    bool public operatorSetsEnabled;

    /// @notice Whether this AVS allows M2 quorums for registration
    /// @dev If true, operators may **not** register to M2 quorums. Deregistration is still allowed.
    bool public isM2QuorumRegistrationDisabled;

    /// @notice The bitmap containing all M2 quorums. This is only used for existing AVS middlewares that have M2 quorums
    /// and need to call `enableOperatorSets()` to enable operator sets mode.
    uint256 internal _m2QuorumBitmap;

    constructor(
        IServiceManager _serviceManager
    ) {
        serviceManager = _serviceManager;
    }

    uint256[48] private __GAP;
}
