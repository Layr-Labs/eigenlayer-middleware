// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IRewardsCoordinator} from
    "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import "./AVSDirectoryMock.sol";

contract RewardsCoordinatorMock is IRewardsCoordinator {
    function initialize(
        address initialOwner,
        uint256 initialPausedStatus,
        address _rewardsUpdater,
        uint32 _activationDelay,
        uint16 _defaultSplitBips
    ) external override {}

    function createAVSRewardsSubmission(
        RewardsSubmission[] calldata rewardsSubmissions
    ) external override {}






    function createOperatorDirectedAVSRewardsSubmission(
        address avs,
        OperatorDirectedRewardsSubmission[] calldata operatorDirectedRewardsSubmissions
    ) external override {}

    function processClaim(RewardsMerkleClaim calldata claim, address recipient) external override {}




    function setClaimerFor(
        address claimer
    ) external override {}

    function setClaimerFor(address earner, address claimer) external override {}







    function activationDelay() external view override returns (uint32) {}


    function claimerFor(
        address earner
    ) external view override returns (address) {}


    function defaultOperatorSplitBips() external view override returns (uint16) {}











    function rewardsUpdater() external view override returns (address) {}

    function CALCULATION_INTERVAL_SECONDS() external view override returns (uint32) {}

    function MAX_REWARDS_DURATION() external view override returns (uint32) {}

    function MAX_RETROACTIVE_LENGTH() external view override returns (uint32) {}

    function MAX_FUTURE_LENGTH() external view override returns (uint32) {}

    function GENESIS_REWARDS_TIMESTAMP() external view override returns (uint32) {}
}
