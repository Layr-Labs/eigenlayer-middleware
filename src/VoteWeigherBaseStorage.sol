// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import "src/interfaces/IServiceManager.sol";
import "src/interfaces/IVoteWeigher.sol";

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

/**
 * @title Storage variables for the `VoteWeigherBase` contract.
 * @author Layr Labs, Inc.
 * @notice Terms of Service: https://docs.eigenlayer.xyz/overview/terms-of-service
 * @notice This storage contract is separate from the logic to simplify the upgrade process.
 */
abstract contract VoteWeigherBaseStorage is Initializable, IVoteWeigher {
    /// @notice Constant used as a divisor in calculating weights.
    uint256 public constant WEIGHTING_DIVISOR = 1e18;
    /// @notice Maximum length of dynamic arrays in the `strategiesConsideredAndMultipliers` mapping.
    uint8 public constant MAX_WEIGHING_FUNCTION_LENGTH = 32;
    /// @notice Constant used as a divisor in dealing with BIPS amounts.
    uint256 internal constant MAX_BIPS = 10000;

    /// @notice The address of the Delegation contract for EigenLayer.
    IDelegationManager public immutable delegation;

    /// @notice The ServiceManager contract for this middleware, where tasks are created / initiated.
    IServiceManager public immutable serviceManager;

    /**
     * @notice mapping from quorum number to the list of strategies considered and their
     * corresponding multipliers for that specific quorum
     */
    mapping(uint8 => StrategyAndWeightingMultiplier[]) public strategiesConsideredAndMultipliers;

    constructor(
        IDelegationManager _delegationManager,
        IServiceManager _serviceManager
    ) {
        delegation = _delegationManager;
        serviceManager = _serviceManager;
        // disable initializers so that the implementation contract cannot be initialized
        _disableInitializers();
    }

    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[49] private __GAP;
}
