// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";

contract RewardsCoordinatorMock is IRewardsCoordinator {
    /// @notice The address of the entity that can update the contract with new merkle roots
    function rewardsUpdater() external view returns (address) {}

    function CALCULATION_INTERVAL_SECONDS() external view returns (uint32) {}

    function MAX_REWARDS_DURATION() external view returns (uint32) {}

    function MAX_RETROACTIVE_LENGTH() external view returns (uint32) {}

    function MAX_FUTURE_LENGTH() external view returns (uint32) {}

    function GENESIS_REWARDS_TIMESTAMP() external view returns (uint32) {}

    function activationDelay() external view returns (uint32) {}

    function claimerFor(address earner) external view returns (address) {}

    function cumulativeClaimed(address claimer, IERC20 token) external view returns (uint256) {}

    function globalOperatorCommissionBips() external view returns (uint16) {}

    function operatorCommissionBips(address operator, address avs) external view returns (uint16) {}

    function calculateEarnerLeafHash(EarnerTreeMerkleLeaf calldata leaf) external pure returns (bytes32) {}

    function calculateTokenLeafHash(TokenTreeMerkleLeaf calldata leaf) external pure returns (bytes32) {}

    function checkClaim(RewardsMerkleClaim calldata claim) external view returns (bool) {}

    function currRewardsCalculationEndTimestamp() external view returns (uint32) {}

    function getRootIndexFromHash(bytes32 rootHash) external view returns (uint32) {}

    function getDistributionRootsLength() external view returns (uint256) {}

    function getCurrentClaimableDistributionRoot() external view returns (DistributionRoot memory) {}

    function getDistributionRootAtIndex(uint256 index) external view returns (DistributionRoot memory) {}

    function getCurrentDistributionRoot() external view returns (DistributionRoot memory) {}

    /// EXTERNAL FUNCTIONS ///

    function disableRoot(uint32 rootIndex) external {}

    function createAVSRewardsSubmission(RewardsSubmission[] calldata rewardsSubmissions) external {}

    function createRewardsForAllSubmission(RewardsSubmission[] calldata rewardsSubmission) external {}

    function processClaim(RewardsMerkleClaim calldata claim, address recipient) external {}

    function submitRoot(
        bytes32 root,
        uint32 rewardsCalculationEndTimestamp
    ) external {}

    function setRewardsUpdater(address _rewardsUpdater) external {}

    function setActivationDelay(uint32 _activationDelay) external {}

    function setGlobalOperatorCommission(uint16 _globalCommissionBips) external {}

    function setClaimerFor(address claimer) external {}

    /**
     * @notice Sets the permissioned `payAllForRangeSubmitter` address which can submit payAllForRange
     * @dev Only callable by the contract owner
     * @param _submitter The address of the payAllForRangeSubmitter
     * @param _newValue The new value for isPayAllForRangeSubmitter
     */
    function setRewardsForAllSubmitter(address _submitter, bool _newValue) external {}
}