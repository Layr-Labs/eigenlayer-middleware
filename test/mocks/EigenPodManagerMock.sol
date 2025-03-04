// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "eigenlayer-contracts/src/contracts/permissions/Pausable.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";

contract EigenPodManagerMock is Test, Pausable, IEigenPodManager {
    receive() external payable {}
    fallback() external payable {}

    mapping(address => int256) public podShares;

    constructor(
        IPauserRegistry _pauserRegistry
    ) Pausable(_pauserRegistry) {
        _setPausedStatus(0);
    }





    function stake(
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable {}

    function recordBeaconChainETHBalanceUpdate(
        address podOwner,
        int256 sharesDelta,
        uint64 proportionPodBalanceDecrease
    ) external {}



    function ethPOS() external view returns (IETHPOSDeposit) {}

    function eigenPodBeacon() external view returns (IBeacon) {}

    function strategyManager() external view returns (IStrategyManager) {}




    function beaconChainETHStrategy() external view returns (IStrategy) {}


    function stakerDepositShares(
        address user,
        IStrategy strategy
    ) external view returns (uint256 depositShares) {}



    function beaconChainSlashingFactor(
        address staker
    ) external view returns (uint64) {}

    function recordBeaconChainETHBalanceUpdate(
        address podOwner,
        uint256 prevRestakedBalanceWei,
        int256 balanceDeltaWei
    ) external {}


}
