// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import "../src/StakeRegistry.sol";
import "../src/ServiceManagerBase.sol";
import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";

contract RewardSubmissionExample is Script, Test {

    // FILL IN THESE VALUES
    uint256 AMOUNT_TO_ETH_QUORUM = 1 ether;
    uint256 AMOUNT_TO_EIGEN_QUORUM = 1 ether;
    uint32 START_TIMESTAMP = 1727913600; // Must be on Thursday 00:00:00 GMT+0000 any given week
    uint32 DURATION = 2419200; // Must be multiple of 604800
    address SERVICE_MANAGER = 0x870679E138bCdf293b7Ff14dD44b70FC97e12fc0;
    address STAKE_REGISTRY = 0x006124Ae7976137266feeBFb3F4D2BE4C073139D;
    address TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; 

    bytes calldata_to_serviceManager;

    // forge test --mc RewardSubmissionExample --fork-url $MAINNET_RPC_URL -vvvv
    function test() external {
        calldata_to_serviceManager = _getCalldataToServiceManager();
        address rewardsInitiator = ServiceManagerBase(SERVICE_MANAGER).rewardsInitiator();

        deal(address(TOKEN), rewardsInitiator, AMOUNT_TO_ETH_QUORUM + AMOUNT_TO_EIGEN_QUORUM);

        vm.startPrank(rewardsInitiator);
        IERC20(TOKEN).approve(SERVICE_MANAGER, AMOUNT_TO_ETH_QUORUM + AMOUNT_TO_EIGEN_QUORUM);
        (bool success, ) = address(SERVICE_MANAGER).call(calldata_to_serviceManager);
        require(success, "rewards submission failed");
        vm.stopPrank();
    }

    // forge script script/RewardSubmissionExample.s.sol:RewardSubmissionExample --rpc-url $MAINNET_RPC_URL --private-key $MAINNET_PRIVATE_KEY -vvvv // --broadcast
    function run() external {
        calldata_to_serviceManager = _getCalldataToServiceManager();

        vm.startBroadcast();
        (bool success, ) = address(SERVICE_MANAGER).call(calldata_to_serviceManager);
        require(success, "rewards submission failed");
        vm.stopBroadcast();
    }

    function _getCalldataToServiceManager() public returns (bytes memory _calldata_to_serviceManager) {
        IRewardsCoordinator.RewardsSubmission[] memory rewardsSubmissions = new IRewardsCoordinator.RewardsSubmission[](2);

        // fetch ETH strategy weights
        uint256 length = StakeRegistry(STAKE_REGISTRY).strategyParamsLength(0); 
        IRewardsCoordinator.StrategyAndMultiplier[] memory ETH_strategyAndMultipliers = new IRewardsCoordinator.StrategyAndMultiplier[](length);
        for (uint256 i = 0; i < length; i++) {
            (IStrategy strategy, uint96 multiplier) = StakeRegistry(STAKE_REGISTRY).strategyParams(0, i);
            ETH_strategyAndMultipliers[i] = IRewardsCoordinator.StrategyAndMultiplier({
                strategy: strategy,
                multiplier: multiplier
            });
        }

        // strategies must be sorted by address
        ETH_strategyAndMultipliers = _sort(ETH_strategyAndMultipliers);

        // create ETH rewards submission
        rewardsSubmissions[0] = IRewardsCoordinator.RewardsSubmission({
            strategiesAndMultipliers: ETH_strategyAndMultipliers,
            token: IERC20(TOKEN),
            amount: AMOUNT_TO_ETH_QUORUM,
            startTimestamp: START_TIMESTAMP,
            duration: DURATION
        });

        // set EIGEN strategy
        IRewardsCoordinator.StrategyAndMultiplier[] memory EIGEN_strategyAndMultipliers = new IRewardsCoordinator.StrategyAndMultiplier[](1);
        EIGEN_strategyAndMultipliers[0] = IRewardsCoordinator.StrategyAndMultiplier({
            strategy: IStrategy(0xaCB55C530Acdb2849e6d4f36992Cd8c9D50ED8F7), // EigenStrategy
            multiplier: 1 ether
        });

        // create EIGEN rewards submission
        rewardsSubmissions[1] = IRewardsCoordinator.RewardsSubmission({
            strategiesAndMultipliers: EIGEN_strategyAndMultipliers,
            token: IERC20(TOKEN),
            amount: AMOUNT_TO_EIGEN_QUORUM,
            startTimestamp: START_TIMESTAMP,
            duration: DURATION
        });

        // encode calldata to call createAVSRewardsSubmission on ServiceManager
        _calldata_to_serviceManager = abi.encodeWithSelector(
            ServiceManagerBase.createAVSRewardsSubmission.selector,
            rewardsSubmissions
        );

        emit log_named_bytes("calldata_to_serviceManager", _calldata_to_serviceManager);
        return _calldata_to_serviceManager;
    }

    function _sort(IRewardsCoordinator.StrategyAndMultiplier[] memory strategyAndMultipliers) public pure returns (IRewardsCoordinator.StrategyAndMultiplier[] memory) {
        uint length = strategyAndMultipliers.length;
        for (uint i = 1; i < length; i++) {
            uint key = uint(uint160(address(strategyAndMultipliers[i].strategy)));
            uint96 multiplier = strategyAndMultipliers[i].multiplier;
            int j = int(i) - 1;
            while ((int(j) >= 0) && (uint(uint160(address(strategyAndMultipliers[uint(j)].strategy))) > key)) {
                strategyAndMultipliers[uint(j) + 1].strategy = strategyAndMultipliers[uint(j)].strategy;
                strategyAndMultipliers[uint(j) + 1].multiplier = strategyAndMultipliers[uint(j)].multiplier;
                j--;
            }
            strategyAndMultipliers[uint(j + 1)].strategy = IStrategy(address(uint160(key)));
            strategyAndMultipliers[uint(j + 1)].multiplier = multiplier;
        }
        return strategyAndMultipliers;
    }
}