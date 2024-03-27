// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {LinearWeightQuorum} from "./LinearWeightQuorum.sol";

/**
 * @notice This contract is similar to LinearWeightQuorum but with a staleness measure, `maxWeightStalenessBlocks`.
 * Provides a few main methods: `getOperatorWeight`, `updateWeightOfOperatorIfNecessary`, and `forceOperatorWeightUpdate`
 * -- see these functions for more details on usage & behavior.
 * Adds one owner-only function for modifying the value of `maxWeightStalenessBlocks`.
 */
contract StandaloneQuorum is LinearWeightQuorum {

    struct OperatorWeightEntry {
        uint224 weight;
        // the block number at which the weight was stored
        uint32 updateBlockNumber;
    }

    /**
     * @notice If an operator's weight was last updated greater than `maxWeightStalenessBlocks` before the current block, then
     * this weight entry is considered "stale"
     */
    uint32 public maxWeightStalenessBlocks;

    mapping(address => OperatorWeightEntry) internal _operatorWeightEntries;

    // @notice Getter for `_operatorWeightEntries` to allow returning a memory struct
    function operatorWeights(address operator) public virtual view returns (OperatorWeightEntry memory) {
        return _operatorWeightEntries[operator];
    }

    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[48] private __GAP;

    event MaxWeightStalenessBlocksSet(uint32 previousValue, uint32 newValue);

    constructor(
        IDelegationManager _delegationManager,
        uint32 _maxWeightStalenessBlocks
    )
        LinearWeightQuorum(_delegationManager)
    {
        _setMaxWeightStalenessBlocks(_maxWeightStalenessBlocks);
    }

    /*******************************************************************************
                    EXTERNAL FUNCTIONS -- unpermissioned
    *******************************************************************************/
    // @notice Updates the `operator`s weight if it is stale, and returns the operator's current weight
    function updateWeightOfOperatorIfNecessary(address operator) public virtual returns (uint256) {
        if (_operatorWeightEntries[operator].updateBlockNumber + maxWeightStalenessBlocks < block.number) {
            return (forceOperatorWeightUpdate(operator));
        } else {
            return uint256(_operatorWeightEntries[operator].weight);
        }
    }

    // @notice Updates the `operator`s weight, and returns the updated value
    function forceOperatorWeightUpdate(address operator) public virtual returns (uint256) {
        uint256 weight = weightOfOperator(operator);
        // TODO: event
        _operatorWeightEntries[operator] = OperatorWeightEntry({
            weight: uint224(weight),
            updateBlockNumber: uint32(block.number)
        });
        return weight;
    }

    /*******************************************************************************
                    EXTERNAL FUNCTIONS -- permissioned
    *******************************************************************************/
    function setMaxWeightStalenessBlocks(uint32 newValue) public virtual onlyOwner {
        _setMaxWeightStalenessBlocks(newValue);
    }

    /*******************************************************************************
                            INTERNAL FUNCTIONS
    *******************************************************************************/
    function _setMaxWeightStalenessBlocks(uint32 newValue) internal virtual {
        emit MaxWeightStalenessBlocksSet(maxWeightStalenessBlocks, newValue);
        maxWeightStalenessBlocks = newValue;
    }

    /*******************************************************************************
                            VIEW FUNCTIONS
    *******************************************************************************/
    // @notice Returns `0` if the operator's weight is stale, and their most recent weight update otherwise.
    function getOperatorWeight(address operator) public virtual view returns (uint256) {
        if (_operatorWeightEntries[operator].updateBlockNumber + maxWeightStalenessBlocks < block.number) {
            return 0;
        } else {
            return uint256(_operatorWeightEntries[operator].weight);
        }
    }
}
