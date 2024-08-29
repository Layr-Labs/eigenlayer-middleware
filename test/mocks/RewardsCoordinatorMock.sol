// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity ^0.8.12;
// 
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// 
// import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
// import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
// 
// contract RewardsCoordinatorMock is IRewardsCoordinator {
//     /// @notice The address of the entity that can update the contract with new merkle roots
//     function rewardsUpdater() external view returns (address) {}
// 
//     function CALCULATION_INTERVAL_SECONDS() external view returns (uint32) {}
// 
//     function MAX_REWARDS_DURATION() external view returns (uint32) {}
// 
//     function MAX_RETROACTIVE_LENGTH() external view returns (uint32) {}
// 
//     function MAX_FUTURE_LENGTH() external view returns (uint32) {}
// 
//     function GENESIS_REWARDS_TIMESTAMP() external view returns (uint32) {}
// 
//     function activationDelay() external view returns (uint32) {}
// 
//     function claimerFor(address earner) external view returns (address) {}
// 
//     function cumulativeClaimed(address claimer, IERC20 token) external view returns (uint256) {}
// 
//     /// @notice the commission for a specific operator for a specific avs
//     /// NOTE: Currently unused and simply returns the globalOperatorCommissionBips value but will be used in future release
//     function getOperatorCommissionBips(
//         address operator,
//         IAVSDirectory.OperatorSet calldata operatorSet,
//         RewardType rewardType
//     ) external view returns (uint16) {}
// 
//     /// @notice returns the length of the operator commission update history
//     function getOperatorCommissionUpdateHistoryLength(
//         address operator,
//         IAVSDirectory.OperatorSet calldata operatorSet,
//         RewardType rewardType
//     ) external view returns (uint256) {}
// 
//     function globalOperatorCommissionBips() external view returns (uint16) {}
// 
//     function operatorCommissionBips(address operator, address avs) external view returns (uint16) {}
// 
//     function calculateEarnerLeafHash(EarnerTreeMerkleLeaf calldata leaf) external pure returns (bytes32) {}
// 
//     function calculateTokenLeafHash(TokenTreeMerkleLeaf calldata leaf) external pure returns (bytes32) {}
// 
//     function checkClaim(RewardsMerkleClaim calldata claim) external view returns (bool) {}
// 
//     function currRewardsCalculationEndTimestamp() external view returns (uint32) {}
// 
//     function getRootIndexFromHash(bytes32 rootHash) external view returns (uint32) {}
// 
//     function getDistributionRootsLength() external view returns (uint256) {}
// 
//     function getDistributionRootAtIndex(uint256 index) external view returns (DistributionRoot memory) {}
// 
//     function getCurrentClaimableDistributionRoot() external view returns (DistributionRoot memory) {}
// 
//     function getCurrentDistributionRoot() external view returns (DistributionRoot memory) {}
// 
//     /// EXTERNAL FUNCTIONS ///
// 
//     function disableRoot(uint32 rootIndex) external {}
// 
//     function createAVSRewardsSubmission(RewardsSubmission[] calldata rewardsSubmissions) external {}
// 
//     function createRewardsForAllSubmission(RewardsSubmission[] calldata rewardsSubmission) external {}
// 
//     function processClaim(RewardsMerkleClaim calldata claim, address recipient) external {}
// 
//     function submitRoot(
//         bytes32 root,
//         uint32 rewardsCalculationEndTimestamp
//     ) external {}
// 
//     function setRewardsUpdater(address _rewardsUpdater) external {}
// 
//     function setActivationDelay(uint32 _activationDelay) external {}
// 
//     function setGlobalOperatorCommission(uint16 _globalCommissionBips) external {}
// 
//     function setClaimerFor(address claimer) external {}
// 
//     /**
//      * @notice Sets the permissioned `payAllForRangeSubmitter` address which can submit payAllForRange
//      * @dev Only callable by the contract owner
//      * @param _submitter The address of the payAllForRangeSubmitter
//      * @param _newValue The new value for isPayAllForRangeSubmitter
//      */
//     function setRewardsForAllSubmitter(address _submitter, bool _newValue) external {}
// 
//     /**
//      * @notice Sets the commission an operator takes in bips for a given reward type and operatorSet
//      * @param operatorSet The operatorSet to update commission for
//      * @param rewardType The associated rewardType to update commission for
//      * @param commissionBips The commission in bips for the operator, must be <= MAX_COMMISSION_BIPS
//      * @return effectTimestamp The timestamp at which the operator commission update will take effect
//      *
//      * @dev The commission can range from 1 to 10000
//      * @dev The commission update takes effect after 7 days
//      */
//     function setOperatorCommissionBips(
//         IAVSDirectory.OperatorSet calldata operatorSet,
//         RewardType rewardType,
//         uint16 commissionBips
//     ) external returns (uint32) {}
// 
//     function rewardOperatorSetForRange(OperatorSetRewardsSubmission[] calldata rewardsSubmissions) external{}
// }