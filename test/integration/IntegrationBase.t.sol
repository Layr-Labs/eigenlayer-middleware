// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "src/libraries/BitmapUtils.sol";
import "src/libraries/BN254.sol";

import "test/integration/IntegrationDeployer.t.sol";
import "test/integration/TimeMachine.t.sol";
import "test/integration/User.t.sol";

abstract contract IntegrationBase is IntegrationDeployer {

    using Strings for *;
    using BitmapUtils for *;
    using BN254 for *;

    uint numOperators = 0;

    /**
     * Gen/Init methods:
     */

    function _newRandomOperator() internal returns (User, IStrategy[] memory, uint[] memory) {
        string memory operatorName = string.concat("Operator", numOperators.toString());
        numOperators++;

        (User operator, IStrategy[] memory strategies, uint[] memory tokenBalances) = _randUser(operatorName);
        
        operator.registerAsOperator();
        operator.depositIntoEigenlayer(strategies, tokenBalances);

        assert_Snap_Added_StakerShares(operator, strategies, tokenBalances, "_newRandomOperator: failed to add delegatable shares");
        assert_Snap_Added_OperatorShares(operator, strategies, tokenBalances, "_newRandomOperator: failed to award shares to operator");
        assertTrue(delegationManager.isOperator(address(operator)), "_newRandomOperator: operator should be registered");

        return (operator, strategies, tokenBalances);
    }

    /// RegistryCoordinator:

    function assert_HasOperatorInfoWithId(User user, string memory err) internal {
        bytes32 expectedId = user.operatorId();
        bytes32 actualId = registryCoordinator.getOperatorId(address(user));

        assertEq(expectedId, actualId, err);
    }

    /// @dev Also checks that the user has NEVER_REGISTERED status
    function assert_HasNoOperatorInfo(User user, string memory err) internal {
        IRegistryCoordinator.OperatorInfo memory info = registryCoordinator.getOperator(address(user));

        assertEq(info.operatorId, bytes32(0), err);
        assertTrue(info.status == IRegistryCoordinator.OperatorStatus.NEVER_REGISTERED, err);
    }

    function assert_HasRegisteredStatus(User user, string memory err) internal {
        IRegistryCoordinator.OperatorStatus status = registryCoordinator.getOperatorStatus(address(user));

        assertTrue(status == IRegistryCoordinator.OperatorStatus.REGISTERED, err);
    }

    function assert_HasDeregisteredStatus(User user, string memory err) internal {
        IRegistryCoordinator.OperatorStatus status = registryCoordinator.getOperatorStatus(address(user));

        assertTrue(status == IRegistryCoordinator.OperatorStatus.DEREGISTERED, err);
    }

    function assert_EmptyQuorumBitmap(User user, string memory err) internal {
        uint192 bitmap = registryCoordinator.getCurrentQuorumBitmap(user.operatorId());

        assertTrue(bitmap == 0, err);
    }

    function assert_NotRegisteredForQuorums(User user, bytes memory quorums, string memory err) internal {
        uint192 bitmap = registryCoordinator.getCurrentQuorumBitmap(user.operatorId());

        for (uint i = 0; i < quorums.length; i++) {
            uint8 quorum = uint8(quorums[i]);

            assertFalse(bitmap.isSet(quorum), err);
        }
    }

    /// @dev Checks that the user's current bitmap includes ALL of these quorums
    function assert_IsRegisteredForQuorums(User user, bytes memory quorums, string memory err) internal {
        uint192 currentBitmap = registryCoordinator.getCurrentQuorumBitmap(user.operatorId());
        uint192 subsetBitmap = uint192(quorums.bytesArrayToBitmap());

        assertTrue(subsetBitmap.isSubsetOf(currentBitmap), err);
    }

    /// @dev Checks whether each of the quorums has been initialized in the RegistryCoordinator
    function assert_QuorumsExist(bytes memory quorums, string memory err) internal {
        uint8 count = registryCoordinator.quorumCount();
        for (uint i = 0; i < quorums.length; i++) {
            uint8 quorum = uint8(quorums[i]);

            assertTrue(quorum < count, err);
        }
    }

    /// BLSApkRegistry:

    function assert_NoRegisteredPubkey(User user, string memory err) internal {
        (uint pubkeyX, uint pubkeyY) = blsApkRegistry.operatorToPubkey(address(user));
        bytes32 pubkeyHash = blsApkRegistry.operatorToPubkeyHash(address(user));

        assertEq(pubkeyX, 0, err);
        assertEq(pubkeyY, 0, err);
        assertEq(pubkeyHash, 0, err);
    }

    function assert_HasRegisteredPubkey(User user, string memory err) internal {
        BN254.G1Point memory expectedPubkey = user.pubkeyG1();
        (uint actualPkX, uint actualPkY) = blsApkRegistry.operatorToPubkey(address(user));

        bytes32 expectedHash = expectedPubkey.hashG1Point();
        bytes32 actualHash = blsApkRegistry.operatorToPubkeyHash(address(user));

        address reverseLookup = blsApkRegistry.pubkeyHashToOperator(expectedHash);

        assertEq(expectedPubkey.X, actualPkX, err);
        assertEq(expectedPubkey.Y, actualPkY, err);
        assertEq(expectedHash, actualHash, err);
        assertEq(address(user), reverseLookup, err);
    }

    /// StakeRegistry:

    /// @dev Checks that the user meets the minimum stake required for each quorum
    function assert_MeetsMinimumShares(User user, bytes memory quorums, string memory err) internal {
        for (uint i = 0; i < quorums.length; i++) {
            uint8 quorum = uint8(quorums[i]);

            uint96 minimum = stakeRegistry.minimumStakeForQuorum(quorum);
            uint96 weight = stakeRegistry.weightOfOperatorForQuorum(quorum, address(user));

            assertTrue(weight >= minimum, err);
        }
    }

    /// IndexRegistry:

    /// @dev Checks that we're specifically UNDER the max operator count, i.e. we are allowing
    /// at least one more operator to register
    function assert_BelowMaxOperators(bytes memory quorums, string memory err) internal {
        for (uint i = 0; i < quorums.length; i++) {
            uint8 quorum = uint8(quorums[i]);

            uint32 maxOperatorCount = registryCoordinator.getOperatorSetParams(quorum).maxOperatorCount;
            uint32 curOperatorCount = indexRegistry.totalOperatorsForQuorum(quorum);

            assertTrue(curOperatorCount < maxOperatorCount, err);
        }
    }

    /// DelegationManager:
    
    function assert_NotRegisteredToAVS(User operator, string memory err) internal {
        IDelegationManager.OperatorAVSRegistrationStatus status = delegationManager.avsOperatorStatus(address(serviceManager), address(operator));

        assertTrue(status == IDelegationManager.OperatorAVSRegistrationStatus.UNREGISTERED, err);
    }

    function assert_IsRegisteredToAVS(User operator, string memory err) internal {
        IDelegationManager.OperatorAVSRegistrationStatus status = delegationManager.avsOperatorStatus(address(serviceManager), address(operator));

        assertTrue(status == IDelegationManager.OperatorAVSRegistrationStatus.REGISTERED, err);
    }

    /*******************************************************************************
                          SNAPSHOT ASSERTIONS (MIDDLEWARE)
                       TIME TRAVELERS ONLY BEYOND THIS POINT
    *******************************************************************************/

    /// @dev Checks that `quorums` were added to the user's registered quorums
    /// NOTE: This means curBitmap - prevBitmap = quorums
    function assert_Snap_Registered_ForQuorums(User user, bytes memory quorums, string memory err) internal {
        bytes32 operatorId = user.operatorId();
        uint quorumsAdded = quorums.orderedBytesArrayToBitmap();

        uint192 curBitmap = _getQuorumBitmap(operatorId);
        uint192 prevBitmap = _getPrevQuorumBitmap(operatorId);

        // assertTrue(curBitmap.minus(prevBitmap) == quorumsAdded, err);
        assertTrue(curBitmap == prevBitmap.plus(quorumsAdded), err);
    }

    function assert_Snap_Deregistered_FromQuorums(User user, bytes memory quorums, string memory err) internal {
        bytes32 operatorId = user.operatorId();
        uint quorumsRemoved = quorums.orderedBytesArrayToBitmap();

        uint192 curBitmap = _getQuorumBitmap(operatorId);
        uint192 prevBitmap = _getPrevQuorumBitmap(operatorId);

        // assertTrue(prevBitmap.plus(quorumsRemoved) == curBitmap, err);
        assertTrue(curBitmap == prevBitmap.minus(quorumsRemoved), err);
    }

    /// @dev Check that the user's pubkey was added to each quorum's apk
    function assert_Snap_Added_QuorumApk(User user, bytes memory quorums, string memory err) internal {
        BN254.G1Point memory userPubkey = user.pubkeyG1();

        BN254.G1Point[] memory curApks = _getQuorumApks(quorums);
        BN254.G1Point[] memory prevApks = _getPrevQuorumApks(quorums);

        for (uint i = 0; i < quorums.length; i++) {
            BN254.G1Point memory expectedApk = prevApks[i].plus(userPubkey);
            assertEq(expectedApk.X, curApks[i].X, err);
            assertEq(expectedApk.Y, curApks[i].Y, err);
        }
    }

    function assert_Snap_Removed_QuorumApk(User user, bytes memory quorums, string memory err) internal {
        BN254.G1Point memory userPubkey = user.pubkeyG1();

        BN254.G1Point[] memory curApks = _getQuorumApks(quorums);
        BN254.G1Point[] memory prevApks = _getPrevQuorumApks(quorums);

        for (uint i = 0; i < quorums.length; i++) {
            BN254.G1Point memory expectedApk = prevApks[i].plus(userPubkey.negate());
            assertEq(expectedApk.X, curApks[i].X, err);
            assertEq(expectedApk.Y, curApks[i].Y, err);
        }
    }

    /// @dev After registering for quorums, check that the operator's weight
    /// was correctly added.
    function assert_Snap_Added_OperatorStake(
        User user, 
        bytes memory quorums,
        string memory err
    ) internal {
        uint96[] memory curStakes = _getStakes(user, quorums);
        uint96[] memory prevStakes = _getPrevStakes(user, quorums);

        uint96[] memory curWeights = _getWeights(user, quorums);
        uint96[] memory prevWeights = _getPrevWeights(user, quorums);

        for (uint i = 0; i < quorums.length; i++) {
            assertEq(curStakes[i], prevStakes[i] + prevWeights[i], err);
            // Sanity check -- current and previous weight should be the same
            assertEq(curWeights[i], prevWeights[i], "assert_Snap_Added_OperatorStake: weight should not have changed");
            // Sanity check -- prev stake should be 0 (cur can still be zero if the quorum has no minimum)
            assertEq(prevStakes[i], 0, "assert_Snap_Added_OperatorStake: previous weight should be been zero");
        }
    }

    function assert_Snap_Removed_OperatorStake(
        User user, 
        bytes memory quorums,
        string memory err
    ) internal {
        uint96[] memory curStakes = _getStakes(user, quorums);
        uint96[] memory prevStakes = _getPrevStakes(user, quorums);

        // uint96[] memory curWeights = _getWeights(user, quorums);
        uint96[] memory prevWeights = _getPrevWeights(user, quorums);

        for (uint i = 0; i < quorums.length; i++) {
            assertEq(curStakes[i], prevStakes[i] - prevWeights[i], err);
        }
    }

    /// @dev After registering for quorums, check that the operator's stake
    /// was added to the total stake for the quorum
    function assert_Snap_Added_TotalStake(
        User user, 
        bytes memory quorums,
        string memory err
    ) internal {
        uint96[] memory curOperatorStakes = _getStakes(user, quorums);

        uint96[] memory curTotalStakes = _getTotalStakes(quorums);
        uint96[] memory prevTotalStakes = _getPrevTotalStakes(quorums);

        for (uint i = 0; i < quorums.length; i++) {
            assertEq(curTotalStakes[i], prevTotalStakes[i] + curOperatorStakes[i], err);
        }
    }

    function assert_Snap_Removed_TotalStake(
        User user, 
        bytes memory quorums,
        string memory err
    ) internal {
        // uint96[] memory curOperatorStakes = _getStakes(user, quorums);
        uint96[] memory prevOperatorStakes = _getPrevStakes(user, quorums);

        uint96[] memory curTotalStakes = _getTotalStakes(quorums);
        uint96[] memory prevTotalStakes = _getPrevTotalStakes(quorums);

        for (uint i = 0; i < quorums.length; i++) {
            assertEq(curTotalStakes[i], prevTotalStakes[i] - prevOperatorStakes[i], err);
        }
    }

    /// @dev After registering for quorums, checks that the totalOperatorsForQuorum increased by 1
    function assert_Snap_Added_OperatorCount(bytes memory quorums, string memory err) internal {
        uint32[] memory curOperatorCounts = _getOperatorCounts(quorums);
        uint32[] memory prevOperatorCounts = _getPrevOperatorCounts(quorums);
        
        for (uint i = 0; i < quorums.length; i++) {
            assertEq(curOperatorCounts[i], prevOperatorCounts[i] + 1, err);
        }
    }

    function assert_Snap_Reduced_OperatorCount(bytes memory quorums, string memory err) internal {
        uint32[] memory curOperatorCounts = _getOperatorCounts(quorums);
        uint32[] memory prevOperatorCounts = _getPrevOperatorCounts(quorums);
        
        for (uint i = 0; i < quorums.length; i++) {
            assertEq(curOperatorCounts[i], prevOperatorCounts[i] - 1, err);
        }
    }

    /// @dev After registering for quorums, checks that the list of operators calculated
    /// for each quorum grew by one
    function assert_Snap_Added_OperatorListEntry(bytes memory quorums, string memory err) internal {
        bytes32[][] memory curOperatorLists = _getOperatorLists(quorums);
        bytes32[][] memory prevOperatorLists = _getPrevOperatorLists(quorums);

        for (uint i = 0; i < quorums.length; i++) {
            assertEq(curOperatorLists[i].length, prevOperatorLists[i].length + 1, err);
        }
    }

    function assert_Snap_Removed_OperatorListEntry(bytes memory quorums, string memory err) internal {
        bytes32[][] memory curOperatorLists = _getOperatorLists(quorums);
        bytes32[][] memory prevOperatorLists = _getPrevOperatorLists(quorums);

        for (uint i = 0; i < quorums.length; i++) {
            assertEq(curOperatorLists[i].length, prevOperatorLists[i].length - 1, err);
        }
    }

    /*******************************************************************************
                             SNAPSHOT ASSERTIONS (CORE)
                       TIME TRAVELERS ONLY BEYOND THIS POINT
    *******************************************************************************/

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

    /// @dev Converts a list of strategies to underlying tokens
    function _getUnderlyingTokens(IStrategy[] memory strategies) internal view returns (IERC20[] memory) {
        IERC20[] memory tokens = new IERC20[](strategies.length);

        for (uint i = 0; i < tokens.length; i++) {
            IStrategy strat = strategies[i];

            tokens[i] = strat.underlyingToken();
        }

        return tokens;
    }

    /*******************************************************************************
                                TIMEWARP GETTERS
    *******************************************************************************/

    modifier timewarp() {
        uint curState = timeMachine.warpToLast();
        _;
        timeMachine.warpToPresent(curState);
    }

    /// Core:

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
    
    /// RegistryCoordinator:

    function _getQuorumBitmap(bytes32 operatorId) internal view returns (uint192) {
        return registryCoordinator.getCurrentQuorumBitmap(operatorId);
    }

    function _getPrevQuorumBitmap(bytes32 operatorId) internal timewarp() returns (uint192) {
        return _getQuorumBitmap(operatorId);
    }

    /// BLSApkRegistry:

    function _getQuorumApks(bytes memory quorums) internal view returns (BN254.G1Point[] memory) {
        BN254.G1Point[] memory apks = new BN254.G1Point[](quorums.length);

        for (uint i = 0; i < quorums.length; i++) {
            apks[i] = blsApkRegistry.getApk(uint8(quorums[i]));
        }

        return apks;
    }

    function _getPrevQuorumApks(bytes memory quorums) internal timewarp() returns (BN254.G1Point[] memory) {
        return _getQuorumApks(quorums);
    }

    /// StakeRegistry:

    function _getStakes(User user, bytes memory quorums) internal view returns (uint96[] memory) {
        bytes32 operatorId = user.operatorId();
        uint96[] memory stakes = new uint96[](quorums.length);

        for (uint i = 0; i < quorums.length; i++) {
            stakes[i] = stakeRegistry.getCurrentStake(operatorId, uint8(quorums[i]));
        }

        return stakes;
    }

    function _getPrevStakes(User user, bytes memory quorums) internal timewarp() returns (uint96[] memory) {
        return _getStakes(user, quorums);
    }

    function _getWeights(User user, bytes memory quorums) internal view returns (uint96[] memory) {
        uint96[] memory weights = new uint96[](quorums.length);

        for (uint i = 0; i < quorums.length; i++) {
            weights[i] = stakeRegistry.weightOfOperatorForQuorum(uint8(quorums[i]), address(user));
        }

        return weights;
    }

    function _getPrevWeights(User user, bytes memory quorums) internal timewarp() returns (uint96[] memory) {
        return _getWeights(user, quorums);
    }

    function _getTotalStakes(bytes memory quorums) internal view returns (uint96[] memory) {
        uint96[] memory stakes = new uint96[](quorums.length);

        for (uint i = 0; i < quorums.length; i++) {
            stakes[i] = stakeRegistry.getCurrentTotalStake(uint8(quorums[i]));
        }
        
        return stakes;
    }

    function _getPrevTotalStakes(bytes memory quorums) internal timewarp() returns (uint96[] memory) {
        return _getTotalStakes(quorums);
    }

    /// IndexRegistry:

    function _getOperatorCounts(bytes memory quorums) internal view returns (uint32[] memory) {
        uint32[] memory operatorCounts = new uint32[](quorums.length);

        for (uint i = 0; i < quorums.length; i++) {
            operatorCounts[i] = indexRegistry.totalOperatorsForQuorum(uint8(quorums[i]));
        }

        return operatorCounts;
    }

    function _getPrevOperatorCounts(bytes memory quorums) internal timewarp() returns (uint32[] memory) {
        return _getOperatorCounts(quorums);
    }

    function _getOperatorLists(bytes memory quorums) internal view returns (bytes32[][] memory) {
        bytes32[][] memory operatorLists = new bytes32[][](quorums.length);

        for (uint i = 0; i < quorums.length; i++) {
            operatorLists[i] = indexRegistry.getOperatorListAtBlockNumber(uint8(quorums[i]), uint32(block.number));
        }

        return operatorLists;
    }

    function _getPrevOperatorLists(bytes memory quorums) internal timewarp() returns (bytes32[][] memory) {
        return _getOperatorLists(quorums);
    }
}