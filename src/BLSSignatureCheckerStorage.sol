// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IBLSSignatureChecker} from "./interfaces/IBLSSignatureChecker.sol";
import {ISlashingRegistryCoordinator} from "./interfaces/ISlashingRegistryCoordinator.sol";
import {IBLSApkRegistry} from "./interfaces/IBLSApkRegistry.sol";
import {IStakeRegistry, IDelegationManager} from "./interfaces/IStakeRegistry.sol";

abstract contract BLSSignatureCheckerStorage is IBLSSignatureChecker {
    /// @dev Returns the assumed gas cost of multiplying 2 pairings.
    uint256 internal constant PAIRING_EQUALITY_CHECK_GAS = 120000;

    /// @inheritdoc IBLSSignatureChecker
    ISlashingRegistryCoordinator public immutable registryCoordinator;
    /// @inheritdoc IBLSSignatureChecker
    IStakeRegistry public immutable stakeRegistry;
    /// @inheritdoc IBLSSignatureChecker
    IBLSApkRegistry public immutable blsApkRegistry;
    /// @inheritdoc IBLSSignatureChecker
    IDelegationManager public immutable delegation;

    /// STATE

    /// @inheritdoc IBLSSignatureChecker
    bool public staleStakesForbidden;

    constructor(
        ISlashingRegistryCoordinator _registryCoordinator
    ) {
        registryCoordinator = _registryCoordinator;
        stakeRegistry = _registryCoordinator.stakeRegistry();
        blsApkRegistry = _registryCoordinator.blsApkRegistry();
        delegation = stakeRegistry.delegation();
    }

    // slither-disable-next-line shadowing-state
    uint256[49] private __GAP;
}
