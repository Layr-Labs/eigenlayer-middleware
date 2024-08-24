// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IStakeRootCompendium.sol";
import "eigenlayer-contracts/src/contracts/libraries/Merkle.sol";

import {BN254} from "./libraries/BN254.sol";

contract OperatorCache {
    uint32 public immutable CACHE_WINDOW;

    /// @notice the stakeRoot compendium address
    IStakeRootCompendium public immutable stakeRootCompendium;

    struct Stakes {
        uint96 delegatedStake;
        uint96 slashableStake;
    }

    struct OperatorPartialLeaf {
        uint256 index;
        bytes proof;
        address operator; // ew ideally we don't need this and the address is just apart of the extraData
        Stakes stakes;
    }

    uint32 public latestCacheTimestamp;
    bytes32 public operatorSetRoot;
    Stakes public totalStakes;

    mapping(bytes32 => Stakes) operatorStakeCache;

    constructor(uint32 _CACHE_WINDOW, IStakeRootCompendium _stakeRootCompendium) {
        CACHE_WINDOW = _CACHE_WINDOW;
        stakeRootCompendium = _stakeRootCompendium;
    }

    /**
     * @notice gets the operatorSetRoot and total stakes and caches them if the cache is stale
     * @param stakeRootIndex the index of the stake root
     * @param operatorSet the operator set to populate the cache with
     * @param operatorSetRootProof the proof of the operator set root against the stake root
     * @param operatorTreeRoot the root of the left subtree of the operator set tree
     * @param totalStakesCalldata the total stakes of the operator set (the leaves of the left subtree)
     * @dev skips if the cache is not stale
     */
    function getOrCacheOperatorSet(
        uint32 stakeRootIndex,
        IAVSDirectory.OperatorSet calldata operatorSet,
        bytes calldata operatorSetRootProof,
        bytes32 operatorTreeRoot,
        Stakes calldata totalStakesCalldata
    ) external returns (bytes32, Stakes memory) {
        // if the latest cache is within the cache window, return
        if(block.timestamp - latestCacheTimestamp < CACHE_WINDOW) {
            return (operatorSetRoot, totalStakes);
        }

        // TODO: we probably need a ring buffer for latestCacheTimestamp and operatorSetRoots
        // get the stake root submission
        IStakeRootCompendium.StakeRootSubmission memory stakeRootSubmission = stakeRootCompendium.getStakeRootSubmission(stakeRootIndex);
        require(block.timestamp - stakeRootSubmission.calculationTimestamp < CACHE_WINDOW, "OperatorCache.populateTotalCache: stale stake root");
        require(stakeRootSubmission.blacklistableBefore < block.timestamp, "OperatorCache.populateTotalCache: stake root is blacklistable");
        latestCacheTimestamp = stakeRootSubmission.calculationTimestamp;

        // verify the operatorSetRoot and total stakes
        // the operatorSetTree looks like
        //         operatorSetRoot
        //          /          \
        // operatorTreeRoot    (uint256 totalSlashableStake_i, uint256 totalDelegatedStake_i)
        //
        bytes32 operatorSetRootMem = keccak256(
            abi.encodePacked(
                operatorTreeRoot, 
                keccak256(
                    abi.encodePacked(
                        uint256(totalStakesCalldata.delegatedStake), 
                        uint256(totalStakesCalldata.slashableStake)
                    )
                )
            )
        );

        uint32 operatorSetIndex = stakeRootCompendium.getOperatorSetIndexAtTimestamp(operatorSet, stakeRootSubmission.calculationTimestamp);
        require(
            Merkle.verifyInclusionKeccak(
                operatorSetRootProof,
                stakeRootSubmission.stakeRoot,
                operatorSetRootMem,
                operatorSetIndex
            ), 
            "OperatorCache.populateTotalCache: invalid operator set proof"
        );
        operatorSetRoot = operatorSetRootMem;
        totalStakes = totalStakesCalldata;

        return (operatorSetRootMem, totalStakesCalldata);
    }

    /**
     * @notice gets the sum of the stakes of certain operators and caches them if the cache is stale
     * @param operatorSet the operator set to get stakes for
     * @param isCached whether the operator is already cached
     * @param publicKeys the public keys of the operators to get stakes for
     * @param nonCachedOperators the operators that need caching
     * @dev PRECONDITION: requires the operatorSetRoot and totalStakes to not be stale
     * @dev skips for operators that are already cached
     */
    function getOrCacheOperatorStakes(
        IAVSDirectory.OperatorSet calldata operatorSet,
        bool[] calldata isCached,
        BN254.G1Point[] calldata publicKeys,
        OperatorPartialLeaf[] calldata nonCachedOperators
    ) external returns (Stakes memory) {
        bytes32 operatorSetRootMem = operatorSetRoot;
        uint256 nonCachedOperatorsIndex = 0;
        Stakes memory totalStakesOfOperators;

        // TODO: should we add publicKeys in this loop?
        // get the stakes of every operator
        for(uint256 i = 0; i < publicKeys.length; i++) {
            if (isCached[i]) {
                // if the operator is already cached, load it
                Stakes memory operatorStake = operatorStakeCache[_stakeCacheKey(operatorSet, publicKeys[i], operatorSetRoot)];
                require(operatorStake.delegatedStake != 0, "OperatorCache.getOrCacheOperatorStakes: operator is not cached or registered");
                totalStakesOfOperators.delegatedStake += operatorStake.delegatedStake;
                totalStakesOfOperators.slashableStake += operatorStake.slashableStake;
            } else {
                require(
                    Merkle.verifyInclusionKeccak(
                        nonCachedOperators[nonCachedOperatorsIndex].proof,
                        operatorSetRootMem,
                        _hashOperatorLeaf(nonCachedOperators[nonCachedOperatorsIndex], publicKeys[i]),
                        nonCachedOperators[nonCachedOperatorsIndex].index
                    ), 
                    "OperatorCache.getOrCacheOperatorStakes: invalid operator proof"
                );
                // TODO: we probably need a ring buffer to save gas here and overwrite a dirty slot
                operatorStakeCache[_stakeCacheKey(operatorSet, publicKeys[i], operatorSetRoot)] = nonCachedOperators[nonCachedOperatorsIndex].stakes;

                totalStakesOfOperators.delegatedStake += nonCachedOperators[nonCachedOperatorsIndex].stakes.delegatedStake;
                totalStakesOfOperators.slashableStake += nonCachedOperators[nonCachedOperatorsIndex].stakes.slashableStake;
                nonCachedOperatorsIndex++;
            }
        }
        return totalStakesOfOperators;
    }

    // the leaves of the stakeTree
    function _hashOperatorLeaf(OperatorPartialLeaf calldata operator, BN254.G1Point calldata publicKey) internal pure returns(bytes32) {
        return keccak256(
            abi.encodePacked(
                operator.operator, 
                operator.stakes.delegatedStake, 
                operator.stakes.slashableStake,
                keccak256(abi.encodePacked(publicKey.X, publicKey.Y))
            )
        );
    }

    function _stakeCacheKey(IAVSDirectory.OperatorSet calldata operatorSet, BN254.G1Point calldata publicKey, bytes32 operatorSetRootMem) internal pure returns(bytes32) {
        return keccak256(abi.encodePacked(operatorSet.avs, operatorSet.operatorSetId, publicKey.X, publicKey.Y, operatorSetRootMem));
    }
}