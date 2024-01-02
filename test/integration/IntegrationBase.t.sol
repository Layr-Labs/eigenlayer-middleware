// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "src/libraries/BitmapUtils.sol";

import "test/integration/IntegrationDeployer.t.sol";
import "test/integration/TimeMachine.t.sol";
import "test/integration/User.t.sol";

abstract contract IntegrationBase is IntegrationDeployer {

    using Strings for *;
    using BitmapUtils for *;

    uint numOperators = 0;

    /**
     * Gen/Init methods:
     */

    function _newRandomOperator() internal returns (User, IStrategy[] memory, uint[] memory) {
        string memory operatorName = string.concat("- Operator", numOperators.toString());
        numOperators++;

        (User operator, IStrategy[] memory strategies, uint[] memory tokenBalances) = _randUser(operatorName);
        
        operator.registerAsOperator();
        operator.depositIntoEigenlayer(strategies, tokenBalances);

        assert_Snap_Added_StakerShares(operator, strategies, tokenBalances, "_newRandomOperator: failed to add delegatable shares");
        assert_Snap_Added_OperatorShares(operator, strategies, tokenBalances, "_newRandomOperator: failed to award shares to operator");
        assertTrue(delegationManager.isOperator(address(operator)), "_newRandomOperator: operator should be registered");

        return (operator, strategies, tokenBalances);
    }

    /// Middleware assertions:

    function assert_HasNoOperatorInfo(User user, string memory err) internal {
        IRegistryCoordinator.OperatorInfo memory info = registryCoordinator.getOperator(address(user));

        assertEq(info.operatorId, bytes32(0), err);
        assertTrue(info.status == IRegistryCoordinator.OperatorStatus.NEVER_REGISTERED, err);
    }

    function assert_EmptyQuorumBitmap(User user, string memory err) internal {
        uint192 bitmap = registryCoordinator.getCurrentQuorumBitmap(user.operatorId());

        assertTrue(bitmap == 0, err);
    }

    function assert_QuorumsExist(bytes memory quorums, string memory err) internal {
        uint8 count = registryCoordinator.quorumCount();
        for (uint i = 0; i < quorums.length; i++) {
            uint8 quorum = uint8(quorums[i]);

            assertTrue(quorum < count, err);
        }
    }

    function assert_NotRegisteredForQuorums(User user, bytes memory quorums, string memory err) internal {
        uint192 bitmap = registryCoordinator.getCurrentQuorumBitmap(user.operatorId());

        for (uint i = 0; i < quorums.length; i++) {
            uint8 quorum = uint8(quorums[i]);

            assertFalse(bitmap.isSet(quorum), err);
        }
    }

    function assert_MeetsMinimumShares(User user, bytes memory quorums, string memory err) internal {
        for (uint i = 0; i < quorums.length; i++) {
            uint8 quorum = uint8(quorums[i]);

            uint96 minimum = stakeRegistry.minimumStakeForQuorum(quorum);
            uint96 weight = stakeRegistry.weightOfOperatorForQuorum(quorum, address(user));

            assertTrue(weight >= minimum, err);
        }
    }

    /*******************************************************************************
                          SNAPSHOT ASSERTIONS (MIDDLEWARE)
                       TIME TRAVELERS ONLY BEYOND THIS POINT
    *******************************************************************************/

    /// @dev Checks that `quorums` were added to the user's registered quorums
    /// NOTE: This means curBitmap - prevBitmap = quorums
    function assert_Snap_RegisteredForQuorums(User user, bytes memory quorums, string memory err) internal {
        bytes32 operatorId = user.operatorId();
        uint quorumsAdded = quorums.orderedBytesArrayToBitmap();

        uint192 curBitmap = _getQuorumBitmap(operatorId);
        uint192 prevBitmap = _getPrevQuorumBitmap(operatorId);

        assertTrue(curBitmap.minus(prevBitmap) == quorumsAdded, err);
    }

    function _getQuorumBitmap(bytes32 operatorId) internal view returns (uint192) {
        return registryCoordinator.getCurrentQuorumBitmap(operatorId);
    }

    function _getPrevQuorumBitmap(bytes32 operatorId) internal timewarp() returns (uint192) {
        return _getQuorumBitmap(operatorId);
    }

    /// Core assertions:

    function assert_HasNoDelegatableShares(User user, string memory err) internal {
        (IStrategy[] memory strategies, uint[] memory shares) = 
            delegationManager.getDelegatableShares(address(user));
        
        assertEq(strategies.length, 0, err);
        assertEq(strategies.length, shares.length, "assert_HasNoDelegatableShares: return length mismatch");
    }

    function assert_HasUnderlyingTokenBalances(
        User user, 
        IStrategy[] memory strategies, 
        uint[] memory expectedBalances, 
        string memory err
    ) internal {
        for (uint i = 0; i < strategies.length; i++) {
            IStrategy strat = strategies[i];
            
            uint expectedBalance = expectedBalances[i];
            uint tokenBalance = strat.underlyingToken().balanceOf(address(user));

            assertEq(expectedBalance, tokenBalance, err);
        }
    }

    function assert_HasNoUnderlyingTokenBalance(User user, IStrategy[] memory strategies, string memory err) internal {
        assert_HasUnderlyingTokenBalances(user, strategies, new uint[](strategies.length), err);
    }

    function assert_HasExpectedShares(
        User user, 
        IStrategy[] memory strategies, 
        uint[] memory expectedShares, 
        string memory err
    ) internal {
        for (uint i = 0; i < strategies.length; i++) {
            IStrategy strat = strategies[i];

            uint actualShares = strategyManager.stakerStrategyShares(address(user), strat);

            assertEq(expectedShares[i], actualShares, err);
        }
    }

    function assert_HasOperatorShares(
        User user, 
        IStrategy[] memory strategies, 
        uint[] memory expectedShares, 
        string memory err
    ) internal {
        for (uint i = 0; i < strategies.length; i++) {
            IStrategy strat = strategies[i];

            uint actualShares = delegationManager.operatorShares(address(user), strat);

            assertEq(expectedShares[i], actualShares, err);
        }
    }

    /// @dev Asserts that ALL of the `withdrawalRoots` is in `delegationManager.pendingWithdrawals`
    function assert_AllWithdrawalsPending(bytes32[] memory withdrawalRoots, string memory err) internal {
        for (uint i = 0; i < withdrawalRoots.length; i++) {
            assert_WithdrawalPending(withdrawalRoots[i], err);
        }
    }

    /// @dev Asserts that NONE of the `withdrawalRoots` is in `delegationManager.pendingWithdrawals`
    function assert_NoWithdrawalsPending(bytes32[] memory withdrawalRoots, string memory err) internal {
        for (uint i = 0; i < withdrawalRoots.length; i++) {
            assert_WithdrawalNotPending(withdrawalRoots[i], err);
        }
    }

    /// @dev Asserts that the hash of each withdrawal corresponds to the provided withdrawal root
    function assert_WithdrawalPending(bytes32 withdrawalRoot, string memory err) internal {
        assertTrue(delegationManager.pendingWithdrawals(withdrawalRoot), err);
    }

    function assert_WithdrawalNotPending(bytes32 withdrawalRoot, string memory err) internal {
        assertFalse(delegationManager.pendingWithdrawals(withdrawalRoot), err);
    }

    function assert_ValidWithdrawalHashes(
        IDelegationManager.Withdrawal[] memory withdrawals,
        bytes32[] memory withdrawalRoots,
        string memory err
    ) internal {
        for (uint i = 0; i < withdrawals.length; i++) {
            assert_ValidWithdrawalHash(withdrawals[i], withdrawalRoots[i], err);
        }
    }

    function assert_ValidWithdrawalHash(
        IDelegationManager.Withdrawal memory withdrawal,
        bytes32 withdrawalRoot,
        string memory err
    ) internal {
        assertEq(withdrawalRoot, delegationManager.calculateWithdrawalRoot(withdrawal), err);
    }
    
    /*******************************************************************************
                             SNAPSHOT ASSERTIONS (CORE)
                       TIME TRAVELERS ONLY BEYOND THIS POINT
    *******************************************************************************/

    /// Snapshot assertions for delegationManager.operatorShares:

    /// @dev Check that the operator has `addedShares` additional operator shares 
    // for each strategy since the last snapshot
    function assert_Snap_Added_OperatorShares(
        User operator, 
        IStrategy[] memory strategies, 
        uint[] memory addedShares,
        string memory err
    ) internal {
        uint[] memory curShares = _getOperatorShares(operator, strategies);
        // Use timewarp to get previous operator shares
        uint[] memory prevShares = _getPrevOperatorShares(operator, strategies);

        // For each strategy, check (prev + added == cur)
        for (uint i = 0; i < strategies.length; i++) {
            assertEq(prevShares[i] + addedShares[i], curShares[i], err);
        }
    }

    /// @dev Check that the operator has `removedShares` fewer operator shares
    /// for each strategy since the last snapshot
    function assert_Snap_Removed_OperatorShares(
        User operator, 
        IStrategy[] memory strategies, 
        uint[] memory removedShares,
        string memory err
    ) internal {
        uint[] memory curShares = _getOperatorShares(operator, strategies);
        // Use timewarp to get previous operator shares
        uint[] memory prevShares = _getPrevOperatorShares(operator, strategies);

        // For each strategy, check (prev - removed == cur)
        for (uint i = 0; i < strategies.length; i++) {
            assertEq(prevShares[i] - removedShares[i], curShares[i], err);
        }
    }

    /// @dev Check that the operator's shares in ALL strategies have not changed
    /// since the last snapshot
    function assert_Snap_Unchanged_OperatorShares(
        User operator,
        string memory err
    ) internal {
        IStrategy[] memory strategies = allStrats;

        uint[] memory curShares = _getOperatorShares(operator, strategies);
        // Use timewarp to get previous operator shares
        uint[] memory prevShares = _getPrevOperatorShares(operator, strategies);

        // For each strategy, check (prev == cur)
        for (uint i = 0; i < strategies.length; i++) {
            assertEq(prevShares[i], curShares[i], err);
        }
    }

    function assert_Snap_Delta_OperatorShares(
        User operator, 
        IStrategy[] memory strategies, 
        int[] memory shareDeltas,
        string memory err
    ) internal {
        uint[] memory curShares = _getOperatorShares(operator, strategies);
        // Use timewarp to get previous operator shares
        uint[] memory prevShares = _getPrevOperatorShares(operator, strategies);

        // For each strategy, check (prev + added == cur)
        for (uint i = 0; i < strategies.length; i++) {
            uint expectedShares;
            if (shareDeltas[i] < 0) {
                expectedShares = prevShares[i] - uint(-shareDeltas[i]);
            } else {
                expectedShares = prevShares[i] + uint(shareDeltas[i]);
            }
            assertEq(expectedShares, curShares[i], err);
        }
    }

    /// Snapshot assertions for strategyMgr.stakerStrategyShares and eigenPodMgr.podOwnerShares:

    /// @dev Check that the staker has `addedShares` additional delegatable shares
    /// for each strategy since the last snapshot
    function assert_Snap_Added_StakerShares(
        User staker, 
        IStrategy[] memory strategies, 
        uint[] memory addedShares,
        string memory err
    ) internal {
        uint[] memory curShares = _getStakerShares(staker, strategies);
        // Use timewarp to get previous staker shares
        uint[] memory prevShares = _getPrevStakerShares(staker, strategies);

        // For each strategy, check (prev + added == cur)
        for (uint i = 0; i < strategies.length; i++) {
            assertEq(prevShares[i] + addedShares[i], curShares[i], err);
        }
    }

    /// @dev Check that the staker has `removedShares` fewer delegatable shares
    /// for each strategy since the last snapshot
    function assert_Snap_Removed_StakerShares(
        User staker, 
        IStrategy[] memory strategies, 
        uint[] memory removedShares,
        string memory err
    ) internal {
        uint[] memory curShares = _getStakerShares(staker, strategies);
        // Use timewarp to get previous staker shares
        uint[] memory prevShares = _getPrevStakerShares(staker, strategies);

        // For each strategy, check (prev - removed == cur)
        for (uint i = 0; i < strategies.length; i++) {
            assertEq(prevShares[i] - removedShares[i], curShares[i], err);
        }
    }

    /// @dev Check that the staker's delegatable shares in ALL strategies have not changed
    /// since the last snapshot
    function assert_Snap_Unchanged_StakerShares(
        User staker,
        string memory err
    ) internal {
        IStrategy[] memory strategies = allStrats;

        uint[] memory curShares = _getStakerShares(staker, strategies);
        // Use timewarp to get previous staker shares
        uint[] memory prevShares = _getPrevStakerShares(staker, strategies);

        // For each strategy, check (prev == cur)
        for (uint i = 0; i < strategies.length; i++) {
            assertEq(prevShares[i], curShares[i], err);
        }
    }

    function assert_Snap_Removed_StrategyShares(
        IStrategy[] memory strategies,
        uint[] memory removedShares,
        string memory err
    ) internal {
        uint[] memory curShares = _getTotalStrategyShares(strategies);

        // Use timewarp to get previous strategy shares
        uint[] memory prevShares = _getPrevTotalStrategyShares(strategies);

        for (uint i = 0; i < strategies.length; i++) {
            uint prevShare = prevShares[i];
            uint curShare = curShares[i];

            assertEq(prevShare - removedShares[i], curShare, err);
        }
    }

    function assert_Snap_Unchanged_StrategyShares(
        IStrategy[] memory strategies,
        string memory err
    ) internal {
        uint[] memory curShares = _getTotalStrategyShares(strategies);

        // Use timewarp to get previous strategy shares
        uint[] memory prevShares = _getPrevTotalStrategyShares(strategies);

        for (uint i = 0; i < strategies.length; i++) {
            uint prevShare = prevShares[i];
            uint curShare = curShares[i];

            assertEq(prevShare, curShare, err);
        }
    }

    /// Snapshot assertions for underlying token balances:

    /// @dev Check that the staker has `addedTokens` additional underlying tokens 
    // since the last snapshot
    function assert_Snap_Added_TokenBalances(
        User staker,
        IERC20[] memory tokens,
        uint[] memory addedTokens,
        string memory err
    ) internal {
        uint[] memory curTokenBalances = _getTokenBalances(staker, tokens);
        // Use timewarp to get previous token balances
        uint[] memory prevTokenBalances = _getPrevTokenBalances(staker, tokens);

        for (uint i = 0; i < tokens.length; i++) {
            uint prevBalance = prevTokenBalances[i];
            uint curBalance = curTokenBalances[i];

            assertEq(prevBalance + addedTokens[i], curBalance, err);
        }
    }

    /// @dev Check that the staker has `removedTokens` fewer underlying tokens 
    // since the last snapshot
    function assert_Snap_Removed_TokenBalances(
        User staker,
        IStrategy[] memory strategies,
        uint[] memory removedTokens,
        string memory err
    ) internal {
        IERC20[] memory tokens = _getUnderlyingTokens(strategies);

        uint[] memory curTokenBalances = _getTokenBalances(staker, tokens);
        // Use timewarp to get previous token balances
        uint[] memory prevTokenBalances = _getPrevTokenBalances(staker, tokens);

        for (uint i = 0; i < tokens.length; i++) {
            uint prevBalance = prevTokenBalances[i];
            uint curBalance = curTokenBalances[i];

            assertEq(prevBalance - removedTokens[i], curBalance, err);
        }
    }

    /// @dev Check that the staker's underlying token balance for ALL tokens have
    /// not changed since the last snapshot
    function assert_Snap_Unchanged_TokenBalances(
        User staker,
        string memory err
    ) internal {
        IERC20[] memory tokens = allTokens;

        uint[] memory curTokenBalances = _getTokenBalances(staker, tokens);
        // Use timewarp to get previous token balances
        uint[] memory prevTokenBalances = _getPrevTokenBalances(staker, tokens);

        for (uint i = 0; i < tokens.length; i++) {
            assertEq(prevTokenBalances[i], curTokenBalances[i], err);
        }
    }

    /// Other snapshot assertions:

    function assert_Snap_Added_QueuedWithdrawals(
        User staker, 
        IDelegationManager.Withdrawal[] memory withdrawals,
        string memory err
    ) internal {
        uint curQueuedWithdrawals = _getCumulativeWithdrawals(staker);
        // Use timewarp to get previous cumulative withdrawals
        uint prevQueuedWithdrawals = _getPrevCumulativeWithdrawals(staker);

        assertEq(prevQueuedWithdrawals + withdrawals.length, curQueuedWithdrawals, err);
    }

    function assert_Snap_Added_QueuedWithdrawal(
        User staker, 
        string memory err
    ) internal {
        uint curQueuedWithdrawal = _getCumulativeWithdrawals(staker);
        // Use timewarp to get previous cumulative withdrawals
        uint prevQueuedWithdrawal = _getPrevCumulativeWithdrawals(staker);

        assertEq(prevQueuedWithdrawal + 1, curQueuedWithdrawal, err);
    }

    /*******************************************************************************
                                UTILITY METHODS
    *******************************************************************************/

    function _randWithdrawal(
        IStrategy[] memory strategies, 
        uint[] memory shares
    ) internal returns (IStrategy[] memory, uint[] memory) {
        uint stratsToWithdraw = _randUint({ min: 1, max: strategies.length });

        IStrategy[] memory withdrawStrats = new IStrategy[](stratsToWithdraw);
        uint[] memory withdrawShares = new uint[](stratsToWithdraw);

        for (uint i = 0; i < stratsToWithdraw; i++) {
            // For LSTs, withdraw a random amount of shares (at least 1)
            uint portion = _randUint({ min: 1, max: shares[i] });
            uint sharesToWithdraw = shares[i] - portion;

            withdrawStrats[i] = strategies[i];
            withdrawShares[i] = sharesToWithdraw;
        }

        return (withdrawStrats, withdrawShares);
    }

    function _randBalanceUpdate(
        User staker,
        IStrategy[] memory strategies
    ) internal returns (int[] memory, int[] memory, int[] memory) {

        int[] memory tokenDeltas = new int[](strategies.length);
        int[] memory stakerShareDeltas = new int[](strategies.length);
        int[] memory operatorShareDeltas = new int[](strategies.length);

        for (uint i = 0; i < strategies.length; i++) {
            IStrategy strat = strategies[i];

            // For LSTs, mint a random token amount
            uint portion = _randUint({ min: MIN_BALANCE, max: MAX_BALANCE });
            StdCheats.deal(address(strat.underlyingToken()), address(staker), portion);

            int delta = int(portion);
            tokenDeltas[i] = delta;
            stakerShareDeltas[i] = int(strat.underlyingToShares(uint(delta)));
            operatorShareDeltas[i] = int(strat.underlyingToShares(uint(delta)));
        }
        return (tokenDeltas, stakerShareDeltas, operatorShareDeltas);
    }

    /// @dev For some strategies/underlying token balances, calculate the expected shares received
    /// from depositing all tokens
    function _calculateExpectedShares(IStrategy[] memory strategies, uint[] memory tokenBalances) internal returns (uint[] memory) {
        uint[] memory expectedShares = new uint[](strategies.length);

        for (uint i = 0; i < strategies.length; i++) {
            IStrategy strat = strategies[i];

            expectedShares[i] = strat.underlyingToShares(tokenBalances[i]);
        }

        return expectedShares;
    }

    /// @dev For some strategies/underlying token balances, calculate the expected shares received
    /// from depositing all tokens
    function _calculateExpectedTokens(IStrategy[] memory strategies, uint[] memory shares) internal returns (uint[] memory) {
        uint[] memory expectedTokens = new uint[](strategies.length);

        for (uint i = 0; i < strategies.length; i++) {
            IStrategy strat = strategies[i];

            expectedTokens[i] = strat.sharesToUnderlying(shares[i]);
        }

        return expectedTokens;
    }

    function _getWithdrawalHashes(
        IDelegationManager.Withdrawal[] memory withdrawals
    ) internal view returns (bytes32[] memory) {
        bytes32[] memory withdrawalRoots = new bytes32[](withdrawals.length);

        for (uint i = 0; i < withdrawals.length; i++) {
            withdrawalRoots[i] = delegationManager.calculateWithdrawalRoot(withdrawals[i]);
        }

        return withdrawalRoots;
    }

    /// @dev Converts a list of strategies to underlying tokens
    function _getUnderlyingTokens(IStrategy[] memory strategies) internal view returns (IERC20[] memory) {
        IERC20[] memory tokens = new IERC20[](strategies.length);

        for (uint i = 0; i < tokens.length; i++) {
            IStrategy strat = strategies[i];

            tokens[i] = strat.underlyingToken();
        }

        return tokens;
    }

    modifier timewarp() {
        uint curState = timeMachine.warpToLast();
        _;
        timeMachine.warpToPresent(curState);
    }

    /// @dev Uses timewarp modifier to get operator shares at the last snapshot
    function _getPrevOperatorShares(
        User operator, 
        IStrategy[] memory strategies
    ) internal timewarp() returns (uint[] memory) {
        return _getOperatorShares(operator, strategies);
    }

    /// @dev Looks up each strategy and returns a list of the operator's shares
    function _getOperatorShares(User operator, IStrategy[] memory strategies) internal view returns (uint[] memory) {
        uint[] memory curShares = new uint[](strategies.length);

        for (uint i = 0; i < strategies.length; i++) {
            curShares[i] = delegationManager.operatorShares(address(operator), strategies[i]);
        }

        return curShares;
    }

    /// @dev Uses timewarp modifier to get staker shares at the last snapshot
    function _getPrevStakerShares(
        User staker, 
        IStrategy[] memory strategies
    ) internal timewarp() returns (uint[] memory) {
        return _getStakerShares(staker, strategies);
    }

    /// @dev Looks up each strategy and returns a list of the staker's shares
    function _getStakerShares(User staker, IStrategy[] memory strategies) internal view returns (uint[] memory) {
        uint[] memory curShares = new uint[](strategies.length);

        for (uint i = 0; i < strategies.length; i++) {
            IStrategy strat = strategies[i];

            curShares[i] = strategyManager.stakerStrategyShares(address(staker), strat);
        }

        return curShares;
    }

    function _getPrevCumulativeWithdrawals(User staker) internal timewarp() returns (uint) {
        return _getCumulativeWithdrawals(staker);
    }

    function _getCumulativeWithdrawals(User staker) internal view returns (uint) {
        return delegationManager.cumulativeWithdrawalsQueued(address(staker));
    }

    function _getPrevTokenBalances(User staker, IERC20[] memory tokens) internal timewarp() returns (uint[] memory) {
        return _getTokenBalances(staker, tokens);
    }

    function _getTokenBalances(User staker, IERC20[] memory tokens) internal view returns (uint[] memory) {
        uint[] memory balances = new uint[](tokens.length);

        for (uint i = 0; i < tokens.length; i++) {
            balances[i] = tokens[i].balanceOf(address(staker));
        }

        return balances;
    }

    function _getPrevTotalStrategyShares(IStrategy[] memory strategies) internal timewarp() returns (uint[] memory) {
        return _getTotalStrategyShares(strategies);
    }

    function _getTotalStrategyShares(IStrategy[] memory strategies) internal view returns (uint[] memory) {
        uint[] memory shares = new uint[](strategies.length);

        for (uint i = 0; i < strategies.length; i++) {
            shares[i] = strategies[i].totalShares();
        }

        return shares;
    }
}