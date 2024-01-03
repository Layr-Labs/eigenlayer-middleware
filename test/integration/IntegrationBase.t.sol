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

    /// RegistryCoordinator assertions:

    function assert_HasNoOperatorInfo(User user, string memory err) internal {
        IRegistryCoordinator.OperatorInfo memory info = registryCoordinator.getOperator(address(user));

        assertEq(info.operatorId, bytes32(0), err);
        assertTrue(info.status == IRegistryCoordinator.OperatorStatus.NEVER_REGISTERED, err);
    }

    function assert_HasOperatorInfoWithId(User user, string memory err) internal {
        bytes32 expectedId = user.operatorId();
        bytes32 actualId = registryCoordinator.getOperatorId(address(user));

        assertEq(expectedId, actualId, err);
    }

    function assert_HasRegisteredStatus(User user, string memory err) internal {
        IRegistryCoordinator.OperatorStatus status = registryCoordinator.getOperatorStatus(address(user));

        assertTrue(status == IRegistryCoordinator.OperatorStatus.REGISTERED, err);
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

    /// BLSApkRegistry assertions:

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

    /// StakeRegistry assertions:

    /// @dev Checks that the user meets the minimum stake required for each quorum
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

    /// @dev Check that the user's pubkey was added to each quorum's apk
    function assert_Snap_Added_QuorumApk(User user, bytes memory quorums, string memory err) internal {
        BN254.G1Point memory userPubkey = user.pubkeyG1();

        for (uint i = 0; i < quorums.length; i++) {
            uint8 quorum = uint8(quorums[i]);

            BN254.G1Point memory curApk = _getQuorumApk(quorum);
            BN254.G1Point memory prevApk = _getPrevQuorumApk(quorum);

            BN254.G1Point memory expectedResult = prevApk.plus(userPubkey);
            assertEq(expectedResult.X, curApk.X, err);
            assertEq(expectedResult.Y, curApk.Y, err);
        }
    }

    function _getQuorumBitmap(bytes32 operatorId) internal view returns (uint192) {
        return registryCoordinator.getCurrentQuorumBitmap(operatorId);
    }

    function _getPrevQuorumBitmap(bytes32 operatorId) internal timewarp() returns (uint192) {
        return _getQuorumBitmap(operatorId);
    }

    function _getQuorumApk(uint8 quorum) internal view returns (BN254.G1Point memory) {
        return blsApkRegistry.getApk(quorum);
    }

    function _getPrevQuorumApk(uint8 quorum) internal timewarp() returns (BN254.G1Point memory) {
        return _getQuorumApk(quorum);
    }

    /// Core assertions:
    
    function assert_NotRegisteredToAVS(User operator, string memory err) internal {
        IDelegationManager.OperatorAVSRegistrationStatus status = delegationManager.avsOperatorStatus(address(serviceManager), address(operator));

        assertTrue(status == IDelegationManager.OperatorAVSRegistrationStatus.UNREGISTERED, err);
    }

    function assert_IsRegisteredToAVS(User operator, string memory err) internal {
        IDelegationManager.OperatorAVSRegistrationStatus status = delegationManager.avsOperatorStatus(address(serviceManager), address(operator));

        assertTrue(status == IDelegationManager.OperatorAVSRegistrationStatus.REGISTERED, err);
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
}