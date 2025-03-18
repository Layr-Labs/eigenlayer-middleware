// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console2 as console} from "forge-std/Test.sol";

import {DelegationManager} from "eigenlayer-contracts/src/contracts/core/DelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IEigenPodManager} from "eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";

contract DelegationManagerHarness is DelegationManager {
    constructor(
        IStrategyManager _strategyManager,
        IEigenPodManager _eigenPodManager,
        IAllocationManager _allocationManager,
        IPauserRegistry _pauserRegistry,
        IPermissionController _permissionController,
        uint32 _MIN_WITHDRAWAL_DELAY
    )
        DelegationManager(
            _strategyManager,
            _eigenPodManager,
            _allocationManager,
            _pauserRegistry,
            _permissionController,
            _MIN_WITHDRAWAL_DELAY,
            "v0.0.1"
        )
    {}

    function setIsOperator(address operator, bool isOperator) external {
        if (isOperator) {
            delegatedTo[operator] = operator;
        } else {
            delegatedTo[operator] = address(0);
        }
    }

    function setOperatorShares(address operator, IStrategy strategy, uint256 shares) external {
        operatorShares[operator][strategy] = shares;
    }
}
