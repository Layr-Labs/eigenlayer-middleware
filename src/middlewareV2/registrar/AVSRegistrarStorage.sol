// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {IAVSRegistrarInternal} from "../../interfaces/IAVSRegistrarInternal.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

/// @notice A minimal storage contract for the AVSRegistrar
abstract contract AVSRegistrarStorage is IAVSRegistrar, IAVSRegistrarInternal {
    /**
     *
     *                            CONSTANTS AND IMMUTABLES
     *
     */

    /// @notice The allocation manager in EigenLayer core
    IAllocationManager public immutable allocationManager;

    /// @notice Pointer to the EigenLayer core Key Registrar
    IKeyRegistrar public immutable keyRegistrar;

    /// @notice The AVS that this registrar is for
    /// @dev In practice, the AVS address in EigenLayer core is address that initialized the Metadata URI.
    address public avs;

    constructor(IAllocationManager _allocationManager, IKeyRegistrar _keyRegistrar) {
        allocationManager = _allocationManager;
        keyRegistrar = _keyRegistrar;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __GAP;
}
