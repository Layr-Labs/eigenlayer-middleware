// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";

import {BitmapUtils} from "./libraries/BitmapUtils.sol";

/**
 * @title A `Registry` that keeps track of stakes of operators for up to 256 quorums.
 * Specifically, it keeps track of
 *      1) The stake of each operator in all the quorums they are a part of for block ranges
 *      2) The total stake of all operators in each quorum for block ranges
 *      3) The minimum stake required to register for each quorum
 * It allows an additional functionality (in addition to registering and deregistering) to update the stake of an operator.
 * @author Layr Labs, Inc.
 */
contract ECDSAStakeRegistry {

    using BitmapUtils for *;

    /**
     * @notice In weighing a particular strategy, the amount of underlying asset for that strategy is
     * multiplied by its multiplier, then divided by WEIGHTING_DIVISOR
     */
    struct StrategyParams {
        IStrategy strategy;
        uint96 multiplier;
    }
    
    // EVENTS

    /// @notice emitted whenever the stake of `operator` is updated
    event OperatorStakeUpdate(
        bytes32 indexed operatorId,
        uint8 quorumNumber,
        uint96 stake
    );
    /// @notice emitted when the minimum stake for a quorum is updated
    event MinimumStakeForQuorumUpdated(uint8 indexed quorumNumber, uint96 minimumStake);
    /// @notice emitted when a new quorum is created
    event QuorumCreated(uint8 indexed quorumNumber);
    /// @notice emitted when `strategy` has been added to the array at `strategyParams[quorumNumber]`
    event StrategyAddedToQuorum(uint8 indexed quorumNumber, IStrategy strategy);
    /// @notice emitted when `strategy` has removed from the array at `strategyParams[quorumNumber]`
    event StrategyRemovedFromQuorum(uint8 indexed quorumNumber, IStrategy strategy);
    /// @notice emitted when `strategy` has its `multiplier` updated in the array at `strategyParams[quorumNumber]`
    event StrategyMultiplierUpdated(uint8 indexed quorumNumber, IStrategy strategy, uint256 multiplier);

    /// @notice Constant used as a divisor in calculating weights.
    uint256 public constant WEIGHTING_DIVISOR = 1e18;
    /// @notice Maximum length of dynamic arrays in the `strategiesConsideredAndMultipliers` mapping.
    uint8 public constant MAX_WEIGHING_FUNCTION_LENGTH = 32;
    /// @notice Constant used as a divisor in dealing with BIPS amounts.
    uint256 internal constant MAX_BIPS = 10000;

    /// @notice The address of the DelegationManager contract for EigenLayer.
    IDelegationManager public immutable delegation;

    /// @notice the coordinator contract that this registry is associated with
    address public immutable registryCoordinator;

    /// @notice In order to register for a quorum i, an operator must have at least `minimumStakeForQuorum[i]`
    /// evaluated by this contract's 'VoteWeigher' logic.
    uint96[256] public minimumStakeForQuorum;

    /// @notice mapping from operator's operatorId to quorum number to their current stake
    mapping(bytes32 => mapping(uint8 => uint96)) public operatorStake;

    /**
     * @notice mapping from quorum number to the total stake for that quorum
     */
    mapping(uint8 => uint96) public totalStake;

    /**
     * @notice mapping from quorum number to the list of strategies considered and their
     * corresponding multipliers for that specific quorum
     */
    mapping(uint8 => StrategyParams[]) public strategyParams;

    // @notice mapping from quorum number to whether or not it exists
    mapping(uint8 => bool) internal _quorumExists;

    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[40] private __GAP;
    
    modifier onlyRegistryCoordinator() {
        require(
            msg.sender == address(registryCoordinator),
            "StakeRegistry.onlyRegistryCoordinator: caller is not the RegistryCoordinator"
        );
        _;
    }

    modifier onlyCoordinatorOwner() {
        require(msg.sender == IRegistryCoordinator(registryCoordinator).owner(), "StakeRegistry.onlyCoordinatorOwner: caller is not the owner of the registryCoordinator");
        _;
    }

    modifier quorumExists(uint8 quorumNumber) {
        require(_quorumExists[quorumNumber], "StakeRegistry.quorumExists: quorum does not exist");
        _;
    }

    constructor(
        IRegistryCoordinator _registryCoordinator, 
        IDelegationManager _delegation
    ) {
        registryCoordinator = address(_registryCoordinator);
        delegation = _delegation;
    }

    /*******************************************************************************
                      EXTERNAL FUNCTIONS - REGISTRY COORDINATOR
    *******************************************************************************/

    /**
     * @notice Registers the `operator` with `operatorId` for the specified `quorumNumbers`.
     * @param operator The address of the operator to register.
     * @param operatorId The id of the operator to register.
     * @param quorumNumbers The quorum numbers the operator is registering for, where each byte is an 8 bit integer quorumNumber.
     * @return The operator's current stake for each quorum, and the total stake for each quorum
     * @dev access restricted to the RegistryCoordinator
     * @dev Preconditions (these are assumed, not validated in this contract):
     *         1) `quorumNumbers` has no duplicates
     *         2) `quorumNumbers.length` != 0
     *         3) `quorumNumbers` is ordered in ascending order
     *         4) the operator is not already registered
     */
    function registerOperator(
        address operator,
        bytes32 operatorId,
        bytes calldata quorumNumbers
    ) public virtual onlyRegistryCoordinator returns (uint96[] memory, uint96[] memory) {

        uint96[] memory currentStakes = new uint96[](quorumNumbers.length);
        uint96[] memory totalStakes = new uint96[](quorumNumbers.length);
        for (uint256 i = 0; i < quorumNumbers.length; i++) {            
            
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            require(_quorumExists[quorumNumber], "StakeRegistry.registerOperator: quorum does not exist");

            // Retrieve the operator's current weighted stake for the quorum, reverting if they have not met
            // the minimum.
            (uint96 currentStake, bool hasMinimumStake) = _weightOfOperatorForQuorum(quorumNumber, operator);
            require(
                hasMinimumStake,
                "StakeRegistry.registerOperator: Operator does not meet minimum stake requirement for quorum"
            );

            // Update the operator's stake
            int256 stakeDelta = _recordOperatorStakeUpdate({
                operatorId: operatorId, 
                quorumNumber: quorumNumber,
                newStake: currentStake
            });

            // Update this quorum's total stake by applying the operator's delta
            currentStakes[i] = currentStake;
            totalStakes[i] = _recordTotalStakeUpdate(quorumNumber, stakeDelta);
        }

        return (currentStakes, totalStakes);
    }

    /**
     * @notice Deregisters the operator with `operatorId` for the specified `quorumNumbers`.
     * @param operatorId The id of the operator to deregister.
     * @param quorumNumbers The quorum numbers the operator is deregistering from, where each byte is an 8 bit integer quorumNumber.
     * @dev access restricted to the RegistryCoordinator
     * @dev Preconditions (these are assumed, not validated in this contract):
     *         1) `quorumNumbers` has no duplicates
     *         2) `quorumNumbers.length` != 0
     *         3) `quorumNumbers` is ordered in ascending order
     *         4) the operator is not already deregistered
     *         5) `quorumNumbers` is a subset of the quorumNumbers that the operator is registered for
     */
    function deregisterOperator(
        bytes32 operatorId,
        bytes calldata quorumNumbers
    ) public virtual onlyRegistryCoordinator {
        /**
         * For each quorum, remove the operator's stake for the quorum and update
         * the quorum's total stake to account for the removal
         */
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            require(_quorumExists[quorumNumber], "StakeRegistry.deregisterOperator: quorum does not exist");

            // Update the operator's stake for the quorum and retrieve the shares removed
            int256 stakeDelta = _recordOperatorStakeUpdate({
                operatorId: operatorId, 
                quorumNumber: quorumNumber, 
                newStake: 0
            });

            // Apply the operator's stake delta to the total stake for this quorum
            _recordTotalStakeUpdate(quorumNumber, stakeDelta);
        }
    }

    /**
     * @notice Called by the registry coordinator to update an operator's stake for one
     * or more quorums.
     *
     * If the operator no longer has the minimum stake required for a quorum, they are
     * added to the `quorumsToRemove`, which is returned to the registry coordinator
     * @return A bitmap of quorums where the operator no longer meets the minimum stake
     * and should be deregistered.
     */
    function updateOperatorStake(
        address operator, 
        bytes32 operatorId, 
        bytes calldata quorumNumbers
    ) external onlyRegistryCoordinator returns (uint192) {
        uint192 quorumsToRemove;

        /**
         * For each quorum, update the operator's stake and record the delta
         * in the quorum's total stake.
         *
         * If the operator no longer has the minimum stake required to be registered
         * in the quorum, the quorum number is added to `quorumsToRemove`, which
         * is returned to the registry coordinator.
         */
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            require(_quorumExists[quorumNumber], "StakeRegistry.updateOperatorStake: quorum does not exist");

            // Fetch the operator's current stake, applying weighting parameters and checking
            // against the minimum stake requirements for the quorum.
            (uint96 stakeWeight, bool hasMinimumStake) = _weightOfOperatorForQuorum(quorumNumber, operator);

            // If the operator no longer meets the minimum stake, set their stake to zero and mark them for removal
            if (!hasMinimumStake) {
                stakeWeight = 0;
                quorumsToRemove = uint192(quorumsToRemove.setBit(quorumNumber));
            }

            // Update the operator's stake and retrieve the delta
            // If we're deregistering them, their weight is set to 0
            int256 stakeDelta = _recordOperatorStakeUpdate({
                operatorId: operatorId,
                quorumNumber: quorumNumber,
                newStake: stakeWeight
            });

            // Apply the delta to the quorum's total stake
            _recordTotalStakeUpdate(quorumNumber, stakeDelta);
        }

        return quorumsToRemove;
    }

    /// @notice Initialize a new quorum and push its first history update
    function initializeQuorum(
        uint8 quorumNumber,
        uint96 minimumStake,
        StrategyParams[] memory _strategyParams
    ) public virtual onlyRegistryCoordinator {
        require(!_quorumExists[quorumNumber], "StakeRegistry.initializeQuorum: quorum already exists");
        _addStrategyParams(quorumNumber, _strategyParams);
        _setMinimumStakeForQuorum(quorumNumber, minimumStake);

        _quorumExists[quorumNumber] = true;
    }

    function setMinimumStakeForQuorum(
        uint8 quorumNumber, 
        uint96 minimumStake
    ) public virtual onlyCoordinatorOwner quorumExists(quorumNumber) {
        _setMinimumStakeForQuorum(quorumNumber, minimumStake);
    }

    /** 
     * @notice Adds strategies and weights to the quorum
     * @dev Checks to make sure that the *same* strategy cannot be added multiple times (checks against both against existing and new strategies).
     * @dev This function has no check to make sure that the strategies for a single quorum have the same underlying asset. This is a concious choice,
     * since a middleware may want, e.g., a stablecoin quorum that accepts USDC, USDT, DAI, etc. as underlying assets and trades them as "equivalent".
     */
    function addStrategies(
        uint8 quorumNumber, 
        StrategyParams[] memory _strategyParams
    ) public virtual onlyCoordinatorOwner quorumExists(quorumNumber) {
        _addStrategyParams(quorumNumber, _strategyParams);
    }

    /**
     * @notice Remove strategies and their associated weights from the quorum's considered strategies
     * @dev higher indices should be *first* in the list of @param indicesToRemove, since otherwise
     * the removal of lower index entries will cause a shift in the indices of the other strategies to remove
     */
    function removeStrategies(
        uint8 quorumNumber,
        uint256[] memory indicesToRemove
    ) public virtual onlyCoordinatorOwner quorumExists(quorumNumber) {
        uint256 toRemoveLength = indicesToRemove.length;
        require(toRemoveLength > 0, "StakeRegistry.removeStrategies: no indices to remove provided");

        StrategyParams[] storage _strategyParams = strategyParams[quorumNumber];

        for (uint256 i = 0; i < toRemoveLength; i++) {
            emit StrategyRemovedFromQuorum(quorumNumber, _strategyParams[indicesToRemove[i]].strategy);
            emit StrategyMultiplierUpdated(quorumNumber, _strategyParams[indicesToRemove[i]].strategy, 0);

            // Replace index to remove with the last item in the list, then pop the last item
            _strategyParams[indicesToRemove[i]] = _strategyParams[_strategyParams.length - 1];
            _strategyParams.pop();
        }
    }

    /**
     * @notice Modifys the weights of existing strategies for a specific quorum
     * @param quorumNumber is the quorum number to which the strategies belong
     * @param strategyIndices are the indices of the strategies to change
     * @param newMultipliers are the new multipliers for the strategies
     */
    function modifyStrategyParams(
        uint8 quorumNumber,
        uint256[] calldata strategyIndices,
        uint96[] calldata newMultipliers
    ) public virtual onlyCoordinatorOwner quorumExists(quorumNumber) {
        uint256 numStrats = strategyIndices.length;
        require(numStrats > 0, "StakeRegistry.modifyStrategyParams: no strategy indices provided");
        require(newMultipliers.length == numStrats, "StakeRegistry.modifyStrategyParams: input length mismatch");

        StrategyParams[] storage _strategyParams = strategyParams[quorumNumber];

        for (uint256 i = 0; i < numStrats; i++) {
            // Change the strategy's associated multiplier
            _strategyParams[strategyIndices[i]].multiplier = newMultipliers[i];
            emit StrategyMultiplierUpdated(quorumNumber, _strategyParams[strategyIndices[i]].strategy, newMultipliers[i]);
        }
    }

    /*******************************************************************************
                            INTERNAL FUNCTIONS
    *******************************************************************************/

    function _setMinimumStakeForQuorum(uint8 quorumNumber, uint96 minimumStake) internal {
        minimumStakeForQuorum[quorumNumber] = minimumStake;
        emit MinimumStakeForQuorumUpdated(quorumNumber, minimumStake);
    }

    /**
     * @notice Records that `operatorId`'s current stake for `quorumNumber` is now `newStake`
     * @return The change in the operator's stake as a signed int256
     */
    function _recordOperatorStakeUpdate(
        bytes32 operatorId,
        uint8 quorumNumber,
        uint96 newStake
    ) internal returns (int256) {

        uint96 prevStake = operatorStake[operatorId][quorumNumber];
        operatorStake[operatorId][quorumNumber] = newStake;

        // Log update and return stake delta
        emit OperatorStakeUpdate(operatorId, quorumNumber, newStake);
        return _calculateDelta({ prev: prevStake, cur: newStake });
    }

    /// @notice Applies a delta to the total stake recorded for `quorumNumber`
    /// @return Returns the new total stake for the quorum
    function _recordTotalStakeUpdate(uint8 quorumNumber, int256 stakeDelta) internal returns (uint96) {
        uint96 prevStake = totalStake[quorumNumber];

        // Return early if no update is needed
        if (stakeDelta == 0) {
            return prevStake;
        }
        
        // Calculate the new total stake by applying the delta to our previous stake
        uint96 newStake = _applyDelta(prevStake, stakeDelta);

        totalStake[quorumNumber] = newStake;

        return newStake;
    }

    /** 
     * @notice Adds `strategyParams` to the `quorumNumber`-th quorum.
     * @dev Checks to make sure that the *same* strategy cannot be added multiple times (checks against both against existing and new strategies).
     * @dev This function has no check to make sure that the strategies for a single quorum have the same underlying asset. This is a concious choice,
     * since a middleware may want, e.g., a stablecoin quorum that accepts USDC, USDT, DAI, etc. as underlying assets and trades them as "equivalent".
     */
     function _addStrategyParams(
        uint8 quorumNumber,
        StrategyParams[] memory _strategyParams
    ) internal {
        require(_strategyParams.length > 0, "StakeRegistry._addStrategyParams: no strategies provided");
        uint256 numStratsToAdd = _strategyParams.length;
        uint256 numStratsExisting = strategyParams[quorumNumber].length;
        require(
            numStratsExisting + numStratsToAdd <= MAX_WEIGHING_FUNCTION_LENGTH,
            "StakeRegistry._addStrategyParams: exceed MAX_WEIGHING_FUNCTION_LENGTH"
        );
        for (uint256 i = 0; i < numStratsToAdd; i++) {
            // fairly gas-expensive internal loop to make sure that the *same* strategy cannot be added multiple times
            for (uint256 j = 0; j < (numStratsExisting + i); j++) {
                require(
                    strategyParams[quorumNumber][j].strategy != _strategyParams[i].strategy,
                    "StakeRegistry._addStrategyParams: cannot add same strategy 2x"
                );
            }
            require(
                _strategyParams[i].multiplier > 0,
                "StakeRegistry._addStrategyParams: cannot add strategy with zero weight"
            );
            strategyParams[quorumNumber].push(_strategyParams[i]);
            emit StrategyAddedToQuorum(quorumNumber, _strategyParams[i].strategy);
            emit StrategyMultiplierUpdated(
                quorumNumber,
                _strategyParams[i].strategy,
                _strategyParams[i].multiplier
            );
        }
    }

    /// @notice Returns the change between a previous and current value as a signed int
    function _calculateDelta(uint96 prev, uint96 cur) internal pure returns (int256) {
        return int256(uint256(cur)) - int256(uint256(prev));
    }

    /// @notice Adds or subtracts delta from value, according to its sign
    function _applyDelta(uint96 value, int256 delta) internal pure returns (uint96) {
        if (delta < 0) {
            return value - uint96(uint256(-delta));
        } else {
            return value + uint96(uint256(delta));
        }
    }

    /**
     * @notice This function computes the total weight of the @param operator in the quorum @param quorumNumber.
     * @dev this method DOES NOT check that the quorum exists
     * @return `uint96` The weighted sum of the operator's shares across each strategy considered by the quorum
     * @return `bool` True if the operator meets the quorum's minimum stake
     */
    function _weightOfOperatorForQuorum(uint8 quorumNumber, address operator) internal virtual view returns (uint96, bool) {
        uint96 weight;
        uint256 stratsLength = strategyParamsLength(quorumNumber);
        StrategyParams memory strategyAndMultiplier;

        for (uint256 i = 0; i < stratsLength; i++) {
            // accessing i^th StrategyParams struct for the quorumNumber
            strategyAndMultiplier = strategyParams[quorumNumber][i];

            // shares of the operator in the strategy
            uint256 sharesAmount = delegation.operatorShares(operator, strategyAndMultiplier.strategy);

            // add the weight from the shares for this strategy to the total weight
            if (sharesAmount > 0) {
                weight += uint96(sharesAmount * strategyAndMultiplier.multiplier / WEIGHTING_DIVISOR);
            }
        }

        // Return the weight, and `true` if the operator meets the quorum's minimum stake
        bool hasMinimumStake = weight >= minimumStakeForQuorum[quorumNumber];
        return (weight, hasMinimumStake);
    }

    /*******************************************************************************
                            VIEW FUNCTIONS
    *******************************************************************************/

    /**
     * @notice This function computes the total weight of the @param operator in the quorum @param quorumNumber.
     * @dev reverts if the quorum does not exist
     */
    function weightOfOperatorForQuorum(
        uint8 quorumNumber, 
        address operator
    ) public virtual view quorumExists(quorumNumber) returns (uint96) {
        (uint96 stake, ) = _weightOfOperatorForQuorum(quorumNumber, operator);
        return stake;
    }

    /// @notice Returns the length of the dynamic array stored in `strategyParams[quorumNumber]`.
    function strategyParamsLength(uint8 quorumNumber) public view returns (uint256) {
        return strategyParams[quorumNumber].length;
    }

    /// @notice Returns the strategy and weight multiplier for the `index`'th strategy in the quorum `quorumNumber`
    function strategyParamsByIndex(
        uint8 quorumNumber, 
        uint256 index
    ) public view returns (StrategyParams memory)
    {
        return strategyParams[quorumNumber][index];
    }

}
