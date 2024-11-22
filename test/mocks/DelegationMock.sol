// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console2 as console} from "forge-std/Test.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {StrategyManager} from "eigenlayer-contracts/src/contracts/core/StrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {SlashingLib} from "eigenlayer-contracts/src/contracts/libraries/SlashingLib.sol";

contract DelegationMock is IDelegationManager {

    function getSlashableSharesInQueue(address operator, IStrategy strategy) external view returns (uint256){}
    function burnOperatorShares(
        address operator,
        IStrategy strategy,
        uint64 prevMaxMagnitude,
        uint64 newMaxMagnitude
    ) external{}
    function initialize(address initialOwner, uint256 initialPausedStatus) external {}

    function registerAsOperator(
        OperatorDetails calldata registeringOperatorDetails,
        uint32 allocationDelay,
        string calldata metadataURI
    ) external {}

    function modifyOperatorDetails(
        OperatorDetails calldata newOperatorDetails
    ) external {}

    function updateOperatorMetadataURI(
        string calldata metadataURI
    ) external {}

    function delegateTo(
        address operator,
        SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external {}

    function undelegate(
        address staker
    ) external returns (bytes32[] memory) {}

    function queueWithdrawals(
        QueuedWithdrawalParams[] calldata params
    ) external returns (bytes32[] memory) {}

    function completeQueuedWithdrawals(
        IERC20[][] calldata tokens,
        bool[] calldata receiveAsTokens,
        uint256 numToComplete
    ) external {}

    function completeQueuedWithdrawal(
        Withdrawal calldata withdrawal,
        IERC20[] calldata tokens,
        bool receiveAsTokens
    ) external {}

    function completeQueuedWithdrawals(
        Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        bool[] calldata receiveAsTokens
    ) external {}

    function increaseDelegatedShares(
        address staker,
        IStrategy strategy,
        uint256 existingDepositShares,
        uint256 addedShares
    ) external {}

    function decreaseBeaconChainScalingFactor(
        address staker,
        uint256 existingShares,
        uint64 proportionOfOldBalance
    ) external {}

    function decreaseOperatorShares(address operator, IStrategy strategy, uint256 wadSlashed) external {}

    function completeQueuedWithdrawal(
        Withdrawal calldata withdrawal,
        IERC20[] calldata tokens,
        uint256 middlewareTimesIndex,
        bool receiveAsTokens
    ) external {}

    function completeQueuedWithdrawals(
        Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        uint256[] calldata middlewareTimesIndexes,
        bool[] calldata receiveAsTokens
    ) external {}

    function delegatedTo(
        address staker
    ) external view returns (address) {}

    function delegationApproverSaltIsSpent(address _delegationApprover, bytes32 salt) external view returns (bool) {}

    function cumulativeWithdrawalsQueued(
        address staker
    ) external view returns (uint256) {}

    function isDelegated(
        address staker
    ) external view returns (bool) {}

    function isOperator(
        address operator
    ) external view returns (bool) {}

    function operatorDetails(
        address operator
    ) external view returns (OperatorDetails memory) {}

    function delegationApprover(
        address operator
    ) external view returns (address) {}

    function getOperatorShares(
        address operator,
        IStrategy[] memory strategies
    ) external view returns (uint256[] memory) {}

    function getOperatorsShares(
        address[] memory operators,
        IStrategy[] memory strategies
    ) external view returns (uint256[][] memory) {}

    function getWithdrawableShares(
        address staker,
        IStrategy[] memory strategies
    ) external view returns (uint256[] memory withdrawableShares, uint256[] memory depositShares) {}

    function getDepositedShares(
        address staker
    ) external view returns (IStrategy[] memory, uint256[] memory) {}

    function depositScalingFactor(address staker, IStrategy strategy) external view returns (uint256) {}

    function getBeaconChainSlashingFactor(
        address staker
    ) external view returns (uint64) {}

    function MIN_WITHDRAWAL_DELAY_BLOCKS() external view returns (uint32) {}

    function getQueuedWithdrawals(
        address staker
    ) external view returns (Withdrawal[] memory withdrawals, uint256[][] memory shares) {}

    function calculateWithdrawalRoot(
        Withdrawal memory withdrawal
    ) external pure returns (bytes32) {}

    function DELEGATION_APPROVAL_TYPEHASH() external view returns (bytes32) {}

    function beaconChainETHStrategy() external view returns (IStrategy) {}

    function calculateDelegationApprovalDigestHash(
        address staker,
        address operator,
        address _delegationApprover,
        bytes32 approverSalt,
        uint256 expiry
    ) external view returns (bytes32) {}

    function setOperatorShares(
        address operator,
        IStrategy strategy,
        uint256 shares
    ) external {
        console.log("HERE");
    }

    function setIsOperator(address, bool) external {
        console.log("HERE");
    }

    function minWithdrawalDelayBlocks() external returns (uint32) {}
}