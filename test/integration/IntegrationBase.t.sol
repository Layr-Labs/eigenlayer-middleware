// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "../../src/libraries/BitmapUtils.sol";
import "../../src/libraries/BN254.sol";

import "./IntegrationConfig.t.sol";
import "./TimeMachine.t.sol";
import "./User.t.sol";

abstract contract IntegrationBase is IntegrationConfig {
    using Strings for *;
    using BitmapUtils for *;
    using BN254 for *;

    /// RegistryCoordinator:

    function assert_HasOperatorInfoWithId(User user, string memory err) internal {
        bytes32 expectedId = user.operatorId();
        bytes32 actualId = slashingRegistryCoordinator.getOperatorId(address(user));

        assertEq(expectedId, actualId, err);
    }

    /// @dev Also checks that the user has NEVER_REGISTERED status
    function assert_HasNoOperatorInfo(User user, string memory err) internal {
        ISlashingRegistryCoordinatorTypes.OperatorInfo memory info = _getOperatorInfo(user);

        assertEq(info.operatorId, bytes32(0), err);
        assertTrue(
            info.status == ISlashingRegistryCoordinatorTypes.OperatorStatus.NEVER_REGISTERED, err
        );
    }

    function assert_HasRegisteredStatus(User user, string memory err) internal {
        ISlashingRegistryCoordinatorTypes.OperatorStatus status =
            slashingRegistryCoordinator.getOperatorStatus(address(user));

        assertTrue(status == ISlashingRegistryCoordinatorTypes.OperatorStatus.REGISTERED, err);
    }

    function assert_HasDeregisteredStatus(User user, string memory err) internal {
        ISlashingRegistryCoordinatorTypes.OperatorStatus status =
            slashingRegistryCoordinator.getOperatorStatus(address(user));

        assertTrue(status == ISlashingRegistryCoordinatorTypes.OperatorStatus.DEREGISTERED, err);
    }

    function assert_EmptyQuorumBitmap(User user, string memory err) internal {
        uint192 bitmap = slashingRegistryCoordinator.getCurrentQuorumBitmap(user.operatorId());

        assertTrue(bitmap == 0, err);
    }

    function assert_NotRegisteredForQuorums(
        User user,
        bytes memory quorums,
        string memory err
    ) internal {
        uint192 bitmap = slashingRegistryCoordinator.getCurrentQuorumBitmap(user.operatorId());

        for (uint256 i = 0; i < quorums.length; i++) {
            uint8 quorum = uint8(quorums[i]);

            assertFalse(bitmap.isSet(quorum), err);
        }
    }

    /// @dev Checks that the user's current bitmap includes ALL of these quorums
    function assert_IsRegisteredForQuorums(
        User user,
        bytes memory quorums,
        string memory err
    ) internal {
        uint192 currentBitmap =
            slashingRegistryCoordinator.getCurrentQuorumBitmap(user.operatorId());
        uint192 subsetBitmap = uint192(quorums.orderedBytesArrayToBitmap());

        assertTrue(subsetBitmap.isSubsetOf(currentBitmap), err);
    }

    /// @dev Checks that the user is registered for each of the operator sets in the AllocationManager
    function assert_RegisteredForOperatorSets(
        User user,
        bytes memory operatorSetIds,
        string memory err
    ) internal {
        for (uint256 i = 0; i < operatorSetIds.length; i++) {
            uint32 operatorSetId = uint32(uint8(operatorSetIds[i]));
            OperatorSet memory operatorSet =
                OperatorSet({avs: avsAccountIdentifier, id: operatorSetId});
            assertTrue(allocationManager.isMemberOfOperatorSet(address(user), operatorSet), err);
        }
    }

    /// @dev Checks whether each of the quorums has been initialized in the RegistryCoordinator
    function assert_QuorumsExist(bytes memory quorums, string memory err) internal {
        uint8 count = slashingRegistryCoordinator.quorumCount();
        for (uint256 i = 0; i < quorums.length; i++) {
            uint8 quorum = uint8(quorums[i]);

            assertTrue(quorum < count, err);
        }
    }

    /// BLSApkRegistry:

    function assert_NoRegisteredPubkey(User user, string memory err) internal {
        (uint256 pubkeyX, uint256 pubkeyY) = blsApkRegistry.operatorToPubkey(address(user));
        bytes32 pubkeyHash = blsApkRegistry.operatorToPubkeyHash(address(user));

        assertEq(pubkeyX, 0, err);
        assertEq(pubkeyY, 0, err);
        assertEq(pubkeyHash, 0, err);
    }

    function assert_HasRegisteredPubkey(User user, string memory err) internal {
        BN254.G1Point memory expectedPubkey = user.pubkeyG1();
        (uint256 actualPkX, uint256 actualPkY) = blsApkRegistry.operatorToPubkey(address(user));

        bytes32 expectedHash = expectedPubkey.hashG1Point();
        bytes32 actualHash = blsApkRegistry.operatorToPubkeyHash(address(user));

        address reverseLookup = blsApkRegistry.pubkeyHashToOperator(expectedHash);

        assertEq(expectedPubkey.X, actualPkX, err);
        assertEq(expectedPubkey.Y, actualPkY, err);
        assertEq(expectedHash, actualHash, err);
        assertEq(address(user), reverseLookup, err);
    }

    /// StakeRegistry:

    function assert_NoExistingStake(User user, bytes memory quorums, string memory err) internal {
        bytes32 operatorId = user.operatorId();

        for (uint256 i = 0; i < quorums.length; i++) {
            uint8 quorum = uint8(quorums[i]);

            uint96 curStake = stakeRegistry.getCurrentStake(operatorId, quorum);

            assertEq(curStake, 0, err);
        }
    }

    /// @dev Checks that the user meets the minimum weight required for each quorum
    function assert_MeetsMinimumWeight(
        User user,
        bytes memory quorums,
        string memory err
    ) internal {
        for (uint256 i = 0; i < quorums.length; i++) {
            uint8 quorum = uint8(quorums[i]);

            uint96 minimum = stakeRegistry.minimumStakeForQuorum(quorum);
            uint96 weight = stakeRegistry.weightOfOperatorForQuorum(quorum, address(user));

            assertTrue(weight >= minimum, err);
        }
    }

    /// @dev Checks that the user meets the minimum stake required for each quorum
    function assert_HasAtLeastMinimumStake(
        User user,
        bytes memory quorums,
        string memory err
    ) internal {
        bytes32 operatorId = user.operatorId();

        for (uint256 i = 0; i < quorums.length; i++) {
            uint8 quorum = uint8(quorums[i]);

            uint96 minimum = stakeRegistry.minimumStakeForQuorum(quorum);
            uint96 stake = stakeRegistry.getCurrentStake(operatorId, quorum);

            assertTrue(stake >= minimum, err);
        }
    }

    /// IndexRegistry:

    /// @dev Checks that we're specifically UNDER the max operator count, i.e. we are allowing
    /// at least one more operator to register
    function assert_BelowMaxOperators(bytes memory quorums, string memory err) internal {
        for (uint256 i = 0; i < quorums.length; i++) {
            uint8 quorum = uint8(quorums[i]);

            uint32 maxOperatorCount =
                slashingRegistryCoordinator.getOperatorSetParams(quorum).maxOperatorCount;
            uint32 curOperatorCount = indexRegistry.totalOperatorsForQuorum(quorum);

            assertTrue(curOperatorCount < maxOperatorCount, err);
        }
    }

    /// AVSDirectory:

    function assert_NotRegisteredToAVS(User operator, string memory err) internal {
        IAVSDirectoryTypes.OperatorAVSRegistrationStatus status =
            avsDirectory.avsOperatorStatus(address(serviceManager), address(operator));

        assertTrue(status == IAVSDirectoryTypes.OperatorAVSRegistrationStatus.UNREGISTERED, err);
    }

    function assert_IsRegisteredToAVS(User operator, string memory err) internal {
        IAVSDirectory.OperatorAVSRegistrationStatus status =
            avsDirectory.avsOperatorStatus(address(serviceManager), address(operator));

        assertTrue(status == IAVSDirectoryTypes.OperatorAVSRegistrationStatus.REGISTERED, err);
    }

    /**
     *
     *                       SNAPSHOT ASSERTIONS (MIDDLEWARE)
     *                    TIME TRAVELERS ONLY BEYOND THIS POINT
     *
     */

    /// @dev Checks that `quorums` were added to the user's registered quorums
    /// NOTE: This means curBitmap - prevBitmap = quorums
    function assert_Snap_Registered_ForQuorums(
        User user,
        bytes memory quorums,
        string memory err
    ) internal {
        bytes32 operatorId = user.operatorId();
        uint256 quorumsAdded = quorums.orderedBytesArrayToBitmap();

        uint192 curBitmap = _getQuorumBitmap(operatorId);
        uint192 prevBitmap = _getPrevQuorumBitmap(operatorId);

        // assertTrue(curBitmap.minus(prevBitmap) == quorumsAdded, err);
        assertTrue(curBitmap == prevBitmap.plus(quorumsAdded), err);
    }

    function assert_Snap_Deregistered_FromQuorums(
        User user,
        bytes memory quorums,
        string memory err
    ) internal {
        bytes32 operatorId = user.operatorId();
        uint256 quorumsRemoved = quorums.orderedBytesArrayToBitmap();

        uint192 curBitmap = _getQuorumBitmap(operatorId);
        uint192 prevBitmap = _getPrevQuorumBitmap(operatorId);

        // Originally, this check looked like this:
        // assertTrue(curBitmap == prevBitmap.minus(quorumsRemoved), err);
        //
        // However, if quorumsRemoved were not the only quorums we removed from
        // the user, this check fails. The new check ensures that quorumsRemoved
        // were set in the previous bitmap, and are NOT set in the current bitmap
        assertTrue(quorumsRemoved.isSubsetOf(prevBitmap), err);
        assertTrue(quorumsRemoved.noBitsInCommon(curBitmap), err);
    }

    /// @dev Checks that user has deregistered from all operator sets in the AllocationManager
    function assert_Snap_Deregistered_FromOperatorSets(
        User user,
        bytes memory quorums,
        string memory err
    ) internal {
        for (uint256 i = 0; i < quorums.length; i++) {
            uint32 operatorSetId = uint32(uint8(quorums[i]));
            OperatorSet memory operatorSet =
                OperatorSet({avs: avsAccountIdentifier, id: operatorSetId});
            assertFalse(allocationManager.isMemberOfOperatorSet(address(user), operatorSet), err);
        }
    }

    function assert_Snap_Unchanged_OperatorInfo(User user, string memory err) internal {
        ISlashingRegistryCoordinatorTypes.OperatorInfo memory curInfo = _getOperatorInfo(user);
        ISlashingRegistryCoordinatorTypes.OperatorInfo memory prevInfo = _getPrevOperatorInfo(user);

        assertEq(prevInfo.operatorId, curInfo.operatorId, err);
        assertTrue(prevInfo.status == curInfo.status, err);
    }

    function assert_Snap_Unchanged_QuorumBitmap(User user, string memory err) internal {
        bytes32 operatorId = user.operatorId();

        uint192 curBitmap = _getQuorumBitmap(operatorId);
        uint192 prevBitmap = _getPrevQuorumBitmap(operatorId);

        assertEq(curBitmap, prevBitmap, err);
    }

    /// @dev Check that the user's pubkey was added to each quorum's apk
    function assert_Snap_Added_QuorumApk(
        User user,
        bytes memory quorums,
        string memory err
    ) internal {
        BN254.G1Point memory userPubkey = user.pubkeyG1();

        BN254.G1Point[] memory curApks = _getQuorumApks(quorums);
        BN254.G1Point[] memory prevApks = _getPrevQuorumApks(quorums);

        for (uint256 i = 0; i < quorums.length; i++) {
            BN254.G1Point memory expectedApk = prevApks[i].plus(userPubkey);
            assertEq(expectedApk.X, curApks[i].X, err);
            assertEq(expectedApk.Y, curApks[i].Y, err);
        }
    }

    function assert_Snap_Removed_QuorumApk(
        User user,
        bytes memory quorums,
        string memory err
    ) internal {
        BN254.G1Point memory userPubkey = user.pubkeyG1();

        BN254.G1Point[] memory curApks = _getQuorumApks(quorums);
        BN254.G1Point[] memory prevApks = _getPrevQuorumApks(quorums);

        for (uint256 i = 0; i < quorums.length; i++) {
            BN254.G1Point memory expectedApk = prevApks[i].plus(userPubkey.negate());
            assertEq(expectedApk.X, curApks[i].X, err);
            assertEq(expectedApk.Y, curApks[i].Y, err);
        }
    }

    function assert_Snap_Unchanged_QuorumApk(bytes memory quorums, string memory err) internal {
        BN254.G1Point[] memory curApks = _getQuorumApks(quorums);
        BN254.G1Point[] memory prevApks = _getPrevQuorumApks(quorums);

        for (uint256 i = 0; i < quorums.length; i++) {
            assertEq(curApks[i].X, prevApks[i].X, err);
            assertEq(curApks[i].Y, prevApks[i].Y, err);
        }
    }

    /// @dev For each churned quorum, checks that the incomingOperator's pk was added
    /// and the corresponding churned operator's pk was removed
    function assert_Snap_Churned_QuorumApk(
        User incomingOperator,
        User[] memory churnedOperators,
        bytes memory churnedQuorums,
        string memory err
    ) internal {
        // Sanity check input lengths
        assertEq(
            churnedOperators.length,
            churnedQuorums.length,
            "assert_Snap_Churned_QuorumApk: input length mismatch"
        );

        BN254.G1Point memory incomingPubkey = incomingOperator.pubkeyG1();

        BN254.G1Point[] memory curApks = _getQuorumApks(churnedQuorums);
        BN254.G1Point[] memory prevApks = _getPrevQuorumApks(churnedQuorums);

        // For each churned quorum, check:
        // - that the corresponding churned operator pubkey was removed
        // - ... AND that the incomingOperator pubkey was added
        for (uint256 i = 0; i < churnedQuorums.length; i++) {
            BN254.G1Point memory churnedPubkey = churnedOperators[i].pubkeyG1();

            BN254.G1Point memory expectedApk =
                prevApks[i].plus(churnedPubkey.negate()).plus(incomingPubkey);

            assertEq(expectedApk.X, curApks[i].X, err);
            assertEq(expectedApk.Y, curApks[i].Y, err);
        }
    }

    /// @dev Check that specific weights were added to the operator and total stakes for each quorum
    function assert_Snap_AddedWeightToStakes(
        User user,
        bytes memory quorums,
        uint96[] memory addedWeights,
        string memory err
    ) internal {
        uint96[] memory curOperatorStakes = _getStakes(user, quorums);
        uint96[] memory prevOperatorStakes = _getPrevStakes(user, quorums);

        uint96[] memory curTotalStakes = _getTotalStakes(quorums);
        uint96[] memory prevTotalStakes = _getPrevTotalStakes(quorums);

        for (uint256 i = 0; i < quorums.length; i++) {
            assertEq(curOperatorStakes[i], prevOperatorStakes[i] + addedWeights[i], err);
            assertEq(curTotalStakes[i], prevTotalStakes[i] + addedWeights[i], err);
        }
    }

    /// @dev Check that the operator's stake weight was added to the operator and total
    /// stakes for each quorum
    function assert_Snap_Added_OperatorWeight(
        User user,
        bytes memory quorums,
        string memory err
    ) internal {
        uint96[] memory addedWeights = _getWeights(user, quorums);

        assert_Snap_AddedWeightToStakes(user, quorums, addedWeights, err);
    }

    /// @dev For each churned quorum, checks that the incomingOperator's weight was added
    /// and the corresponding churned operator's weight was removed
    function assert_Snap_Churned_OperatorWeight(
        User incomingOperator,
        User[] memory churnedOperators,
        bytes memory churnedQuorums,
        string memory err
    ) internal {
        // Sanity check input lengths
        assertEq(
            churnedOperators.length,
            churnedQuorums.length,
            "assert_Snap_Churned_OperatorWeight: input length mismatch"
        );

        // Get weights added and removed for each quorum
        uint96[] memory addedWeights = _getWeights(incomingOperator, churnedQuorums);
        uint96[] memory removedWeights = new uint96[](churnedOperators.length);
        for (uint256 i = 0; i < churnedOperators.length; i++) {
            removedWeights[i] = _getWeight(uint8(churnedQuorums[i]), churnedOperators[i]);
        }

        uint96[] memory curIncomingOpStakes = _getStakes(incomingOperator, churnedQuorums);
        uint96[] memory prevIncomingOpStakes = _getPrevStakes(incomingOperator, churnedQuorums);

        uint96[] memory curTotalStakes = _getTotalStakes(churnedQuorums);
        uint96[] memory prevTotalStakes = _getPrevTotalStakes(churnedQuorums);

        // For each quorum, check that the incoming operator's individual stake was increased by addedWeights
        // and that the total stake is plus addedWeights and minus removedWeights
        for (uint256 i = 0; i < churnedQuorums.length; i++) {
            assertEq(curIncomingOpStakes[i], prevIncomingOpStakes[i] + addedWeights[i], err);
            assertEq(
                curTotalStakes[i], prevTotalStakes[i] + addedWeights[i] - removedWeights[i], err
            );
        }
    }

    function assert_Snap_Unchanged_OperatorStake(
        User user,
        bytes memory quorums,
        string memory err
    ) internal {
        uint96[] memory curStakes = _getStakes(user, quorums);
        uint96[] memory prevStakes = _getPrevStakes(user, quorums);

        for (uint256 i = 0; i < quorums.length; i++) {
            assertEq(curStakes[i], prevStakes[i], err);
        }
    }

    /// @dev Check that a user's calculated weight DID NOT DECREASE since the last snapshot
    function assert_Snap_Increased_OperatorWeight(
        User user,
        bytes memory quorums,
        string memory err
    ) internal {
        uint96[] memory curWeights = _getWeights(user, quorums);
        uint96[] memory prevWeights = _getPrevWeights(user, quorums);

        for (uint256 i = 0; i < quorums.length; i++) {
            assertTrue(curWeights[i] >= prevWeights[i], err);
        }
    }

    /// @dev Check that a user's calculated weight DID NOT INCREASE since the last snapshot
    function assert_Snap_Decreased_OperatorWeight(
        User user,
        bytes memory quorums,
        string memory err
    ) internal {
        uint96[] memory curWeights = _getWeights(user, quorums);
        uint96[] memory prevWeights = _getPrevWeights(user, quorums);

        for (uint256 i = 0; i < quorums.length; i++) {
            assertTrue(curWeights[i] <= prevWeights[i], err);
        }
    }

    function assert_Snap_Unchanged_OperatorWeight(
        User user,
        bytes memory quorums,
        string memory err
    ) internal {
        uint96[] memory curWeights = _getWeights(user, quorums);
        uint96[] memory prevWeights = _getPrevWeights(user, quorums);

        for (uint256 i = 0; i < quorums.length; i++) {
            assertEq(curWeights[i], prevWeights[i], err);
        }
    }

    /// @dev After registering for quorums, check that the operator's stake
    /// was added to the total stake for the quorum
    function assert_Snap_Added_TotalStake(
        bytes memory quorums,
        uint96[] memory addedWeights,
        string memory err
    ) internal {
        uint96[] memory curTotalStakes = _getTotalStakes(quorums);
        uint96[] memory prevTotalStakes = _getPrevTotalStakes(quorums);

        for (uint256 i = 0; i < quorums.length; i++) {
            assertEq(curTotalStakes[i], prevTotalStakes[i] + addedWeights[i], err);
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

        for (uint256 i = 0; i < quorums.length; i++) {
            assertEq(curTotalStakes[i], prevTotalStakes[i] - prevOperatorStakes[i], err);
        }
    }

    function assert_Snap_Unchanged_TotalStake(bytes memory quorums, string memory err) internal {
        uint96[] memory curTotalStakes = _getTotalStakes(quorums);
        uint96[] memory prevTotalStakes = _getPrevTotalStakes(quorums);

        for (uint256 i = 0; i < quorums.length; i++) {
            assertEq(curTotalStakes[i], prevTotalStakes[i], err);
        }
    }

    /// @dev After registering for quorums, checks that the totalOperatorsForQuorum increased by 1
    function assert_Snap_Added_OperatorCount(bytes memory quorums, string memory err) internal {
        uint32[] memory curOperatorCounts = _getOperatorCounts(quorums);
        uint32[] memory prevOperatorCounts = _getPrevOperatorCounts(quorums);

        for (uint256 i = 0; i < quorums.length; i++) {
            assertEq(curOperatorCounts[i], prevOperatorCounts[i] + 1, err);
        }
    }

    function assert_Snap_Reduced_OperatorCount(bytes memory quorums, string memory err) internal {
        uint32[] memory curOperatorCounts = _getOperatorCounts(quorums);
        uint32[] memory prevOperatorCounts = _getPrevOperatorCounts(quorums);

        for (uint256 i = 0; i < quorums.length; i++) {
            assertEq(curOperatorCounts[i], prevOperatorCounts[i] - 1, err);
        }
    }

    function assert_Snap_Unchanged_OperatorCount(
        bytes memory quorums,
        string memory err
    ) internal {
        uint32[] memory curOperatorCounts = _getOperatorCounts(quorums);
        uint32[] memory prevOperatorCounts = _getPrevOperatorCounts(quorums);

        for (uint256 i = 0; i < quorums.length; i++) {
            assertEq(curOperatorCounts[i], prevOperatorCounts[i], err);
        }
    }

    /// @dev After registering for quorums, checks:
    /// - that the list length grew by one
    /// - that the operator is in the current list, but not the previous list
    function assert_Snap_Added_OperatorListEntry(
        User operator,
        bytes memory quorums,
        string memory err
    ) internal {
        bytes32[][] memory curOperatorLists = _getOperatorLists(quorums);
        bytes32[][] memory prevOperatorLists = _getPrevOperatorLists(quorums);

        for (uint256 i = 0; i < quorums.length; i++) {
            assertEq(curOperatorLists[i].length, prevOperatorLists[i].length + 1, err);

            assertTrue(_contains(curOperatorLists[i], operator), err);
            assertFalse(_contains(prevOperatorLists[i], operator), err);
        }
    }

    /// @dev After registering for quorums, checks:
    /// - that the list length shrunk by one
    /// - that the operator is in the previous list, but not the current list
    function assert_Snap_Removed_OperatorListEntry(
        User operator,
        bytes memory quorums,
        string memory err
    ) internal {
        bytes32[][] memory curOperatorLists = _getOperatorLists(quorums);
        bytes32[][] memory prevOperatorLists = _getPrevOperatorLists(quorums);

        for (uint256 i = 0; i < quorums.length; i++) {
            assertEq(curOperatorLists[i].length, prevOperatorLists[i].length - 1, err);

            assertFalse(_contains(curOperatorLists[i], operator), err);
            assertTrue(_contains(prevOperatorLists[i], operator), err);
        }
    }

    function assert_Snap_Unchanged_OperatorListEntry(
        bytes memory quorums,
        string memory err
    ) internal {
        bytes32[][] memory curOperatorLists = _getOperatorLists(quorums);
        bytes32[][] memory prevOperatorLists = _getPrevOperatorLists(quorums);

        bytes32 curHash = keccak256(abi.encode(curOperatorLists));
        bytes32 prevHash = keccak256(abi.encode(prevOperatorLists));

        assertEq(curHash, prevHash, err);
    }

    /// @dev After registering for quorums with churn, checks:
    /// - that the list length stayed the same
    /// - that the incoming operator is in the current list, but was NOT in the previous list
    /// - that each churned operator is NOT in the current list, but was in the previous list
    function assert_Snap_Replaced_OperatorListEntries(
        User incomingOperator,
        User[] memory churnedOperators,
        bytes memory churnedQuorums,
        string memory err
    ) internal {
        // Sanity check input lengths
        assertEq(
            churnedOperators.length,
            churnedQuorums.length,
            "assert_Snap_Replaced_OperatorListEntries: input length mismatch"
        );

        bytes32[][] memory curOperatorLists = _getOperatorLists(churnedQuorums);
        bytes32[][] memory prevOperatorLists = _getPrevOperatorLists(churnedQuorums);

        for (uint256 i = 0; i < churnedQuorums.length; i++) {
            assertEq(curOperatorLists[i].length, prevOperatorLists[i].length, err);

            // check incomingOperator was added
            assertTrue(_contains(curOperatorLists[i], incomingOperator), err);
            assertFalse(_contains(prevOperatorLists[i], incomingOperator), err);

            // check churnedOperator was removed
            assertFalse(_contains(curOperatorLists[i], churnedOperators[i]), err);
            assertTrue(_contains(prevOperatorLists[i], churnedOperators[i]), err);
        }
    }

    /**
     *
     *                          SNAPSHOT ASSERTIONS (CORE)
     *                    TIME TRAVELERS ONLY BEYOND THIS POINT
     *
     */

    /// @dev Check that the operator has `addedShares` additional operator shares
    // for each strategy since the last snapshot
    function assert_Snap_Added_OperatorShares(
        User operator,
        IStrategy[] memory strategies,
        uint256[] memory addedShares,
        string memory err
    ) internal {
        uint256[] memory curShares = _getOperatorShares(operator, strategies);
        // Use timewarp to get previous operator shares
        uint256[] memory prevShares = _getPrevOperatorShares(operator, strategies);

        // For each strategy, check (prev + added == cur)
        for (uint256 i = 0; i < strategies.length; i++) {
            assertEq(prevShares[i] + addedShares[i], curShares[i], err);
        }
    }

    /// @dev Check that the operator has `removedShares` fewer operator shares
    /// for each strategy since the last snapshot
    function assert_Snap_Removed_OperatorShares(
        User operator,
        IStrategy[] memory strategies,
        uint256[] memory removedShares,
        string memory err
    ) internal {
        uint256[] memory curShares = _getOperatorShares(operator, strategies);
        // Use timewarp to get previous operator shares
        uint256[] memory prevShares = _getPrevOperatorShares(operator, strategies);

        // For each strategy, check (prev - removed == cur)
        for (uint256 i = 0; i < strategies.length; i++) {
            assertEq(prevShares[i] - removedShares[i], curShares[i], err);
        }
    }

    /// @dev Check that the staker has `addedShares` additional delegatable shares
    /// for each strategy since the last snapshot
    function assert_Snap_Added_StakerShares(
        User staker,
        IStrategy[] memory strategies,
        uint256[] memory addedShares,
        string memory err
    ) internal {
        uint256[] memory curShares = _getStakerShares(staker, strategies);
        // Use timewarp to get previous staker shares
        uint256[] memory prevShares = _getPrevStakerShares(staker, strategies);

        // For each strategy, check (prev + added == cur)
        for (uint256 i = 0; i < strategies.length; i++) {
            assertEq(prevShares[i] + addedShares[i], curShares[i], err);
        }
    }

    /// @dev Check that the staker has `removedShares` fewer delegatable shares
    /// for each strategy since the last snapshot
    function assert_Snap_Removed_StakerShares(
        User staker,
        IStrategy[] memory strategies,
        uint256[] memory removedShares,
        string memory err
    ) internal {
        uint256[] memory curShares = _getStakerShares(staker, strategies);
        // Use timewarp to get previous staker shares
        uint256[] memory prevShares = _getPrevStakerShares(staker, strategies);

        // For each strategy, check (prev - removed == cur)
        for (uint256 i = 0; i < strategies.length; i++) {
            assertEq(prevShares[i] - removedShares[i], curShares[i], err);
        }
    }

    function assert_Snap_Added_QueuedWithdrawals(
        User staker,
        IDelegationManager.Withdrawal[] memory withdrawals,
        string memory err
    ) internal {
        uint256 curQueuedWithdrawals = _getCumulativeWithdrawals(staker);
        // Use timewarp to get previous cumulative withdrawals
        uint256 prevQueuedWithdrawals = _getPrevCumulativeWithdrawals(staker);

        assertEq(prevQueuedWithdrawals + withdrawals.length, curQueuedWithdrawals, err);
    }

    function assert_Snap_Added_QueuedWithdrawal(User staker, string memory err) internal {
        uint256 curQueuedWithdrawal = _getCumulativeWithdrawals(staker);
        // Use timewarp to get previous cumulative withdrawals
        uint256 prevQueuedWithdrawal = _getPrevCumulativeWithdrawals(staker);

        assertEq(prevQueuedWithdrawal + 1, curQueuedWithdrawal, err);
    }

    /**
     *
     *                             UTILITY METHODS
     *
     */
    function _calcRemaining(
        bytes memory start,
        bytes memory removed
    ) internal pure returns (bytes memory) {
        uint256 startBM = start.orderedBytesArrayToBitmap();
        uint256 removeBM = removed.orderedBytesArrayToBitmap();

        return startBM.minus(removeBM).bitmapToBytesArray();
    }

    /// @dev For some strategies/underlying token balances, calculate the expected shares received
    /// from depositing all tokens
    function _calculateExpectedShares(
        IStrategy[] memory strategies,
        uint256[] memory tokenBalances
    ) internal returns (uint256[] memory) {
        uint256[] memory expectedShares = new uint256[](strategies.length);

        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy strat = strategies[i];

            expectedShares[i] = strat.underlyingToShares(tokenBalances[i]);
        }

        return expectedShares;
    }

    /// @dev For some strategies/underlying token balances, calculate the expected shares received
    /// from depositing all tokens
    function _calculateExpectedTokens(
        IStrategy[] memory strategies,
        uint256[] memory shares
    ) internal returns (uint256[] memory) {
        uint256[] memory expectedTokens = new uint256[](strategies.length);

        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy strat = strategies[i];

            expectedTokens[i] = strat.sharesToUnderlying(shares[i]);
        }

        return expectedTokens;
    }

    /// @dev Converts a list of strategies to underlying tokens
    function _getUnderlyingTokens(
        IStrategy[] memory strategies
    ) internal view returns (IERC20[] memory) {
        IERC20[] memory tokens = new IERC20[](strategies.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            IStrategy strat = strategies[i];

            tokens[i] = strat.underlyingToken();
        }

        return tokens;
    }

    function _contains(bytes32[] memory operatorIds, User operator) internal view returns (bool) {
        bytes32 checkId = operator.operatorId();

        for (uint256 i = 0; i < operatorIds.length; i++) {
            if (operatorIds[i] == checkId) {
                return true;
            }
        }

        return false;
    }

    /**
     *
     *                             TIMEWARP GETTERS
     *
     */
    modifier timewarp() {
        uint256 curState = timeMachine.warpToLast();
        _;
        timeMachine.warpToPresent(curState);
    }

    /// Core:

    /// @dev Uses timewarp modifier to get operator shares at the last snapshot
    function _getPrevOperatorShares(
        User operator,
        IStrategy[] memory strategies
    ) internal timewarp returns (uint256[] memory) {
        return _getOperatorShares(operator, strategies);
    }

    /// @dev Looks up each strategy and returns a list of the operator's shares
    function _getOperatorShares(
        User operator,
        IStrategy[] memory strategies
    ) internal view returns (uint256[] memory) {
        uint256[] memory curShares = new uint256[](strategies.length);

        for (uint256 i = 0; i < strategies.length; i++) {
            curShares[i] = delegationManager.operatorShares(address(operator), strategies[i]);
        }

        return curShares;
    }

    /// @dev Uses timewarp modifier to get staker shares at the last snapshot
    function _getPrevStakerShares(
        User staker,
        IStrategy[] memory strategies
    ) internal timewarp returns (uint256[] memory) {
        return _getStakerShares(staker, strategies);
    }

    /// @dev Looks up each strategy and returns a list of the staker's shares
    function _getStakerShares(
        User staker,
        IStrategy[] memory strategies
    ) internal view returns (uint256[] memory) {
        uint256[] memory curShares = new uint256[](strategies.length);

        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy strat = strategies[i];

            curShares[i] = strategyManager.stakerDepositShares(address(staker), strat);
        }

        return curShares;
    }

    function _getPrevCumulativeWithdrawals(
        User staker
    ) internal timewarp returns (uint256) {
        return _getCumulativeWithdrawals(staker);
    }

    function _getCumulativeWithdrawals(
        User staker
    ) internal view returns (uint256) {
        return delegationManager.cumulativeWithdrawalsQueued(address(staker));
    }

    /// RegistryCoordinator:

    function _getOperatorInfo(
        User user
    ) internal view returns (ISlashingRegistryCoordinatorTypes.OperatorInfo memory) {
        return slashingRegistryCoordinator.getOperator(address(user));
    }

    function _getPrevOperatorInfo(
        User user
    ) internal timewarp returns (ISlashingRegistryCoordinatorTypes.OperatorInfo memory) {
        return _getOperatorInfo(user);
    }

    function _getQuorumBitmap(
        bytes32 operatorId
    ) internal view returns (uint192) {
        return slashingRegistryCoordinator.getCurrentQuorumBitmap(operatorId);
    }

    function _getPrevQuorumBitmap(
        bytes32 operatorId
    ) internal timewarp returns (uint192) {
        return _getQuorumBitmap(operatorId);
    }

    /// BLSApkRegistry:

    function _getQuorumApks(
        bytes memory quorums
    ) internal view returns (BN254.G1Point[] memory) {
        BN254.G1Point[] memory apks = new BN254.G1Point[](quorums.length);

        for (uint256 i = 0; i < quorums.length; i++) {
            apks[i] = blsApkRegistry.getApk(uint8(quorums[i]));
        }

        return apks;
    }

    function _getPrevQuorumApks(
        bytes memory quorums
    ) internal timewarp returns (BN254.G1Point[] memory) {
        return _getQuorumApks(quorums);
    }

    /// StakeRegistry:

    function _getStakes(User user, bytes memory quorums) internal view returns (uint96[] memory) {
        bytes32 operatorId = user.operatorId();
        uint96[] memory stakes = new uint96[](quorums.length);

        for (uint256 i = 0; i < quorums.length; i++) {
            stakes[i] = stakeRegistry.getCurrentStake(operatorId, uint8(quorums[i]));
        }

        return stakes;
    }

    function _getPrevStakes(
        User user,
        bytes memory quorums
    ) internal timewarp returns (uint96[] memory) {
        return _getStakes(user, quorums);
    }

    function _getWeights(User user, bytes memory quorums) internal view returns (uint96[] memory) {
        uint96[] memory weights = new uint96[](quorums.length);

        for (uint256 i = 0; i < quorums.length; i++) {
            weights[i] = stakeRegistry.weightOfOperatorForQuorum(uint8(quorums[i]), address(user));
        }

        return weights;
    }

    function _getPrevWeights(
        User user,
        bytes memory quorums
    ) internal timewarp returns (uint96[] memory) {
        return _getWeights(user, quorums);
    }

    /// @dev Calculates the amount added to the user's stake weight for each quorum since the last snapshot
    /// NOTE: Fails if the user's stake weight was reduced
    function _getAddedWeight(User user, bytes memory quorums) internal returns (uint96[] memory) {
        uint96[] memory curWeights = _getWeights(user, quorums);
        uint96[] memory prevWeights = _getPrevWeights(user, quorums);

        uint96[] memory addedWeights = new uint96[](quorums.length);

        for (uint256 i = 0; i < quorums.length; i++) {
            uint96 curWeight = curWeights[i];
            uint96 prevWeight = prevWeights[i];

            if (curWeight < prevWeight) {
                revert("_getAddedWeight: expected positive weight delta");
            }

            addedWeights[i] = curWeight - prevWeight;
        }

        return addedWeights;
    }

    function _getTotalStakes(
        bytes memory quorums
    ) internal view returns (uint96[] memory) {
        uint96[] memory stakes = new uint96[](quorums.length);

        for (uint256 i = 0; i < quorums.length; i++) {
            stakes[i] = stakeRegistry.getCurrentTotalStake(uint8(quorums[i]));
        }

        return stakes;
    }

    function _getPrevTotalStakes(
        bytes memory quorums
    ) internal timewarp returns (uint96[] memory) {
        return _getTotalStakes(quorums);
    }

    /// IndexRegistry:

    function _getOperatorCounts(
        bytes memory quorums
    ) internal view returns (uint32[] memory) {
        uint32[] memory operatorCounts = new uint32[](quorums.length);

        for (uint256 i = 0; i < quorums.length; i++) {
            operatorCounts[i] = indexRegistry.totalOperatorsForQuorum(uint8(quorums[i]));
        }

        return operatorCounts;
    }

    function _getPrevOperatorCounts(
        bytes memory quorums
    ) internal timewarp returns (uint32[] memory) {
        return _getOperatorCounts(quorums);
    }

    function _getOperatorLists(
        bytes memory quorums
    ) internal view returns (bytes32[][] memory) {
        bytes32[][] memory operatorLists = new bytes32[][](quorums.length);

        for (uint256 i = 0; i < quorums.length; i++) {
            operatorLists[i] =
                indexRegistry.getOperatorListAtBlockNumber(uint8(quorums[i]), uint32(block.number));
        }

        return operatorLists;
    }

    function _getPrevOperatorLists(
        bytes memory quorums
    ) internal timewarp returns (bytes32[][] memory) {
        return _getOperatorLists(quorums);
    }
}
