// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

abstract contract LinearWeightQuorum is OwnableUpgradeable {
    
    /// @notice Constant used as a divisor in calculating weights.
    uint256 public constant WEIGHTING_DIVISOR = 1e18;
    /// @notice Maximum length of dynamic arrays in the `strategiesConsideredAndMultipliers` mapping.
    uint8 public constant MAX_WEIGHING_FUNCTION_LENGTH = 32;

    /// @notice The address of the Delegation contract for EigenLayer.
    IDelegationManager public immutable delegation;

    /**
     * @notice In weighing a particular strategy, the amount of underlying asset for that strategy is
     * multiplied by its multiplier, then divided by WEIGHTING_DIVISOR
     */
    struct StrategyParams {
        IStrategy strategy;
        uint96 multiplier;
    }

    // @notice list of strategies considered and their corresponding multipliers for this AVS     
    StrategyParams[] public strategyParams;

    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[49] private __GAP;

    constructor(
        IDelegationManager _delegationManager
    ) {
        delegation = _delegationManager;
    }


    /*******************************************************************************
                    EXTERNAL FUNCTIONS -- permissioned
    *******************************************************************************/
    /** 
     * @notice Adds strategies and weights
     * @dev Checks to make sure that the *same* strategy cannot be added multiple times (checks against both against existing and new strategies).
     * @dev This function has no check to make sure that the strategies for a single quorum have the same underlying asset. This is a concious choice,
     * since a middleware may want, e.g., a stablecoin quorum that accepts USDC, USDT, DAI, etc. as underlying assets and treats them as "equivalent".
     */
    function addStrategies(
        StrategyParams[] memory _strategyParams
    ) public virtual onlyOwner {
        _addStrategyParams(_strategyParams);
    }

    /**
     * @notice Remove strategies and their associated weights from the considered strategies
     * @dev higher indices should be *first* in the list of @param indicesToRemove, since otherwise
     * the removal of lower index entries will cause a shift in the indices of the other strategies to remove
     */
    function removeStrategies(
        uint256[] memory indicesToRemove
    ) public virtual onlyOwner {
        uint256 toRemoveLength = indicesToRemove.length;
        require(toRemoveLength > 0, "StakeRegistry.removeStrategies: no indices to remove provided");
        for (uint256 i = 0; i < toRemoveLength; i++) {
            // TODO: events
            // emit StrategyRemovedFromQuorum(quorumNumber, _strategyParams[indicesToRemove[i]].strategy);
            // emit StrategyMultiplierUpdated(quorumNumber, _strategyParams[indicesToRemove[i]].strategy, 0);

            // Replace index to remove with the last item in the list, then pop the last item
            strategyParams[indicesToRemove[i]] = strategyParams[strategyParams.length - 1];
            strategyParams.pop();
        }
    }

    /**
     * @notice Modifies the weights of existing strategies for a specific quorum
     * @param strategyIndices are the indices of the strategies to change
     * @param newMultipliers are the new multipliers for the strategies
     */
    function modifyStrategyParams(
        uint256[] calldata strategyIndices,
        uint96[] calldata newMultipliers
    ) public virtual onlyOwner {
        uint256 numStrats = strategyIndices.length;
        require(numStrats > 0, "StakeRegistry.modifyStrategyParams: no strategy indices provided");
        require(newMultipliers.length == numStrats, "StakeRegistry.modifyStrategyParams: input length mismatch");

        for (uint256 i = 0; i < numStrats; i++) {
            // Change the strategy's associated multiplier
            strategyParams[strategyIndices[i]].multiplier = newMultipliers[i];
            // TODO: events
            // emit StrategyMultiplierUpdated(quorumNumber, strategyParams[strategyIndices[i]].strategy, newMultipliers[i]);
        }
    }

    /*******************************************************************************
                            INTERNAL FUNCTIONS
    *******************************************************************************/
    /** 
     * @notice Adds `_strategyParams` to consideration.
     * @dev Checks to make sure that the *same* strategy cannot be added multiple times (checks against both against existing and new strategies).
     * @dev This function has no check to make sure that the strategies for a single quorum have the same underlying asset. This is a concious choice,
     * since a middleware may want, e.g., a stablecoin quorum that accepts USDC, USDT, DAI, etc. as underlying assets and treats them as "equivalent".
     */
    function _addStrategyParams(
        StrategyParams[] memory _strategyParams
    ) internal virtual {
        require(_strategyParams.length > 0, "StakeRegistry._addStrategyParams: no strategies provided");
        uint256 numStratsToAdd = _strategyParams.length;
        uint256 numStratsExisting = strategyParams.length;
        require(
            numStratsExisting + numStratsToAdd <= MAX_WEIGHING_FUNCTION_LENGTH,
            "StakeRegistry._addStrategyParams: exceed MAX_WEIGHING_FUNCTION_LENGTH"
        );
        for (uint256 i = 0; i < numStratsToAdd; i++) {
            // fairly gas-expensive internal loop to make sure that the *same* strategy cannot be added multiple times
            for (uint256 j = 0; j < (numStratsExisting + i); j++) {
                require(
                    strategyParams[j].strategy != _strategyParams[i].strategy,
                    "StakeRegistry._addStrategyParams: cannot add same strategy 2x"
                );
            }
            require(
                _strategyParams[i].multiplier > 0,
                "StakeRegistry._addStrategyParams: cannot add strategy with zero weight"
            );
            strategyParams.push(_strategyParams[i]);
            // TODO: events
            // emit StrategyAddedToQuorum(quorumNumber, _strategyParams[i].strategy);
            // emit StrategyMultiplierUpdated(_strategyParams[i].strategy, _strategyParams[i].multiplier);
        }
    }

    /*******************************************************************************
                            VIEW FUNCTIONS
    *******************************************************************************/
    /**
     * @notice This function computes the total weight of the @param operator.
     * @return `uint256` The weighted sum of the operator's shares across each strategy considered
     */
    function weightOfOperator(address operator) public virtual view returns (uint256) {
        uint256 weight;
        uint256 stratsLength = strategyParamsLength();
        StrategyParams memory strategyAndMultiplier;

        for (uint256 i = 0; i < stratsLength; i++) {
            // accessing i^th StrategyParams struct
            strategyAndMultiplier = strategyParams[i];

            // shares of the operator in the strategy
            uint256 sharesAmount = delegation.operatorShares(operator, strategyAndMultiplier.strategy);

            // add the weight from the shares for this strategy to the total weight
            if (sharesAmount > 0) {
                weight += uint96(sharesAmount * strategyAndMultiplier.multiplier / WEIGHTING_DIVISOR);
            }
        }
        return weight;
    }

    /// @notice Returns the length of the dynamic array stored in `strategyParams`.
    function strategyParamsLength() public view returns (uint256) {
        return strategyParams.length;
    }

    /// @notice Returns the strategy and weight multiplier for the `index`'th strategy
    function strategyParamsByIndex(
        uint256 index
    ) public view returns (StrategyParams memory)
    {
        return strategyParams[index];
    }
}
