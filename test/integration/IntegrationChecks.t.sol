// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "test/integration/IntegrationBase.t.sol";
import "test/integration/User.t.sol";

/// @notice Contract that provides utility functions to reuse common test blocks & checks
contract IntegrationChecks is IntegrationBase {
    
    /*******************************************************************************
                                PRE-REGISTER CHECKS
    *******************************************************************************/

    function check_Never_Registered(
        User operator
    ) internal {
        _log("check_Never_Registered",  operator);

        // RegistryCoordinator
        assert_HasNoOperatorInfo(operator,
            "operator should have empty id and NEVER_REGISTERED status");
        assert_EmptyQuorumBitmap(operator,
            "operator already has bits in quorum bitmap");

        // BLSApkRegistry
        assert_NoRegisteredPubkey(operator, 
            "operator already has a registered pubkey");

        // DelegationManager
        assert_NotRegisteredToAVS(operator, 
            "operator should not be registered to the AVS");
    }

    function check_Can_Register(
        User operator,
        bytes memory quorums
    ) internal {
        _log("check_Can_Register", operator);

        // RegistryCoordinator
        assert_QuorumsExist(quorums,
            "not all quorums exist");
        assert_NotRegisteredForQuorums(operator, quorums,
            "operator is already registered for some quorums");

        // StakeRegistry
        assert_MeetsMinimumWeight(operator, quorums,
            "operator does not meet minimum weight for all quorums");
        assert_NoExistingStake(operator, quorums, 
            "operator should not already have stake in any quorums");

        // IndexRegistry
        assert_BelowMaxOperators(quorums,
            "operator cap reached");
    }

    /*******************************************************************************
                                POST-REGISTER CHECKS
    *******************************************************************************/

    function check_Register_State(
        User operator,
        bytes memory quorums
    ) internal {
        _log("check_Register_State", operator);

        // RegistryCoordinator
        assert_HasOperatorInfoWithId(operator, 
            "operatorInfo should have operatorId");
        assert_HasRegisteredStatus(operator,
            "operatorInfo status should be REGISTERED");
        assert_IsRegisteredForQuorums(operator, quorums,
            "current operator bitmap should include quorums");
        assert_Snap_Registered_ForQuorums(operator, quorums,
            "operator did not register for all quorums");

        // BLSApkRegistry
        assert_HasRegisteredPubkey(operator, 
            "operator should have registered a pubkey");
        assert_Snap_Added_QuorumApk(operator, quorums, 
            "operator pubkey should have been added to each quorum apk");
        
        // StakeRegistry
        assert_HasAtLeastMinimumStake(operator, quorums,
            "operator should have at least the minimum stake in each quorum");
        assert_Snap_AddedOperatorWeight(operator, quorums,
            "failed to add operator weight to operator and total stake in each quorum");

        // IndexRegistry
        assert_Snap_Added_OperatorCount(quorums,
            "total operator count should have increased for each quorum");
        assert_Snap_Added_OperatorListEntry(quorums,
            "operator list should have one more entry");

        // DelegationManager
        assert_IsRegisteredToAVS(operator,
            "operator should be registered to AVS");
    }

    /*******************************************************************************
                                 BALANCE UPDATE CHECKS
    *******************************************************************************/

    function check_Deposit_State(
        User operator,
        bytes memory quorums,
        IStrategy[] memory strategies,
        uint[] memory tokenBalances
    ) internal {
        _log("check_Deposit_State", operator);

        // RegistryCoordinator
        assert_Snap_Unchanged_OperatorInfo(operator,
            "operator info should not have changed");
        assert_Snap_Unchanged_QuorumBitmap(operator,
            "operators quorum bitmap should not have changed");
        
        // BLSApkRegistry
        assert_Snap_Unchanged_QuorumApk(quorums,
            "quorum apks should not have changed");

        // StakeRegistry
        assert_Snap_Increased_OperatorWeight(operator, quorums,
            "operator weight should not have decreased after deposit");
        assert_Snap_Unchanged_OperatorStake(operator, quorums, 
            "operator stake should be unchanged");
        assert_Snap_Unchanged_TotalStake(quorums, 
            "total stake should be unchanged");

        // IndexRegistry
        assert_Snap_Unchanged_OperatorCount(quorums,
            "operator counts should not have changed");
        assert_Snap_Unchanged_OperatorListEntry(quorums,
            "operator list should not have changed");

        // Core
        assert_Snap_Added_OperatorShares(operator, strategies, tokenBalances,
            "operator should have additional stake");
    }

    /// @dev Checks that an operator's stake was successfully increased
    /// NOTE: This method assumes (and checks) that the operator already
    ///       met the minimum stake before stake was added.
    function check_DepositUpdate_State(
        User operator, 
        bytes memory quorums, 
        uint96[] memory addedWeights
    ) internal {
        _log("check_DepositUpdate_State", operator);

        // RegistryCoordinator
        assert_Snap_Unchanged_OperatorInfo(operator,
            "operator info should not have changed");
        assert_Snap_Unchanged_QuorumBitmap(operator,
            "operators quorum bitmap should not have changed");

        // BLSApkRegistry
        assert_Snap_Unchanged_QuorumApk(quorums,
            "quorum apks should not have changed");

        // StakeRegistry
        assert_HasAtLeastMinimumStake(operator, quorums,
            "operator should have at least the minimum stake in each quorum");
        assert_Snap_Unchanged_OperatorWeight(operator, quorums,
            "updateOperators should not effect operator weight calculation");
        assert_Snap_AddedWeightToStakes(operator, quorums, addedWeights,
            "weights should have been added to operator and total stakes");

        // IndexRegistry
        assert_Snap_Unchanged_OperatorCount(quorums,
            "total operator count should be unchanged for each quorum");
        assert_Snap_Unchanged_OperatorListEntry(quorums,
            "operator list should be unchanged for each quorum");

        // DelegationManager
        assert_IsRegisteredToAVS(operator,
            "operator should be registered to AVS");
    }

    /// @dev Validate state directly after the operator exits from Eigenlayer core (by queuing withdrawals)
    function check_Withdraw_State(
        User operator,
        bytes memory quorums,
        IStrategy[] memory strategies,
        uint[] memory shares
    ) internal {
        _log("check_Withdraw_State", operator);

        // RegistryCoordinator
        assert_Snap_Unchanged_OperatorInfo(operator,
            "operator info should not have changed");
        assert_Snap_Unchanged_QuorumBitmap(operator,
            "operators quorum bitmap should not have changed");
        
        // BLSApkRegistry
        assert_Snap_Unchanged_QuorumApk(quorums,
            "quorum apks should not have changed");

        // StakeRegistry
        assert_Snap_Decreased_OperatorWeight(operator, quorums,
            "operator weight should not have increased after deposit");
        assert_Snap_Unchanged_OperatorStake(operator, quorums, 
            "operator stake should be unchanged");
        assert_Snap_Unchanged_TotalStake(quorums, 
            "total stake should be unchanged");

        // IndexRegistry
        assert_Snap_Unchanged_OperatorCount(quorums,
            "operator counts should not have changed");
        assert_Snap_Unchanged_OperatorListEntry(quorums,
            "operator list should not have changed");

        // Core
        assert_Snap_Removed_OperatorShares(operator, strategies, shares,
            "operator should have reduced stake");
    }

    /// @dev Validate state when, after exiting from the core contracts, updateOperators is called
    /// We expect that the operator is completely deregistered.
    /// NOTE: This is a combination of check_Deregister_State and check_CompleteDeregister_State
    function check_WithdrawUpdate_State(
        User operator,
        bytes memory quorums
    ) internal {
        _log("check_WithdrawUpdate_State", operator);

        // RegistryCoordinator
        assert_HasOperatorInfoWithId(operator, 
            "operatorInfo should still have operatorId");
        assert_EmptyQuorumBitmap(operator,
            "operator should not have any bits in bitmap");
        assert_HasDeregisteredStatus(operator,
            "operatorInfo status should be DEREGISTERED");
        assert_Snap_Deregistered_FromQuorums(operator, quorums,
            "operator did not deregister from all quorums");

        // BLSApkRegistry
        assert_HasRegisteredPubkey(operator, 
            "operator should still have a registered pubkey");
        assert_Snap_Removed_QuorumApk(operator, quorums, 
            "operator pubkey should have been subtracted from each quorum apk");

        // StakeRegistry
        assert_NoExistingStake(operator, quorums,
            "operator should no longer have stake in any quorums");
        assert_Snap_Removed_TotalStake(operator, quorums,
            "failed to remove operator weight from total stake for each quorum");

        // IndexRegistry
        assert_Snap_Reduced_OperatorCount(quorums,
            "total operator count should have decreased for each quorum");
        assert_Snap_Removed_OperatorListEntry(quorums,
            "operator list should have one fewer entry");

        // DelegationManager
        assert_NotRegisteredToAVS(operator, 
            "operator should not be registered to the AVS");
    }

    /// @dev Used to validate a stake update after NO core balance changes occured
    function check_NoUpdate_State(
        User operator,
        bytes memory quorums
    ) internal {
        _log("check_NoChangeUpdate_State", operator);

        // RegistryCoordinator
        assert_Snap_Unchanged_OperatorInfo(operator,
            "operator info should not have changed");
        assert_Snap_Unchanged_QuorumBitmap(operator,
            "operators quorum bitmap should not have changed");

        // BLSApkRegistry
        assert_Snap_Unchanged_QuorumApk(quorums,
            "quorum apks should not have changed");

        // StakeRegistry
        assert_Snap_Unchanged_OperatorWeight(operator, quorums,
            "operator weight should be unchanged");
        assert_Snap_Unchanged_OperatorStake(operator, quorums,
            "operator stake should be unchanged");
        assert_Snap_Unchanged_TotalStake(quorums,
            "total stake should be unchanged");

        // IndexRegistry
        assert_Snap_Unchanged_OperatorCount(quorums,
            "total operator count should be unchanged for each quorum");
        assert_Snap_Unchanged_OperatorListEntry(quorums,
            "operator list should be unchanged for each quorum");
    }

    /*******************************************************************************
                                 POST-DEREGISTER CHECKS
    *******************************************************************************/

    /// @dev Check that the operator correctly deregistered from some quorums
    function check_Deregister_State(
        User operator,
        bytes memory quorums
    ) internal {
        _log("check_Deregister_State", operator);

        // RegistryCoordinator
        assert_HasOperatorInfoWithId(operator, 
            "operatorInfo should still have operatorId");
        assert_NotRegisteredForQuorums(operator, quorums,
            "current operator bitmap should not include quorums");
        assert_Snap_Deregistered_FromQuorums(operator, quorums,
            "operator did not deregister from all quorums");

        // BLSApkRegistry
        assert_HasRegisteredPubkey(operator, 
            "operator should still have a registered pubkey");
        assert_Snap_Removed_QuorumApk(operator, quorums, 
            "operator pubkey should have been subtracted from each quorum apk");

        // StakeRegistry
        assert_NoExistingStake(operator, quorums,
            "operator should no longer have stake in any quorums");
        assert_Snap_Removed_TotalStake(operator, quorums,
            "failed to remove operator weight from total stake for each quorum");

        // IndexRegistry
        assert_Snap_Reduced_OperatorCount(quorums,
            "total operator count should have decreased for each quorum");
        assert_Snap_Removed_OperatorListEntry(quorums,
            "operator list should have one fewer entry");
    }

    /// @dev Check that the operator correctly deregistered from ALL their quorums
    function check_CompleteDeregister_State(
        User operator
    ) internal {
        _log("check_CompleteDeregister_State", operator);

        // RegistryCoordinator
        assert_EmptyQuorumBitmap(operator,
            "operator should not have any bits in bitmap");
        assert_HasOperatorInfoWithId(operator, 
            "operatorInfo should still have operatorId");
        assert_HasDeregisteredStatus(operator,
            "operatorInfo status should be DEREGISTERED");

        // DelegationManager
        assert_NotRegisteredToAVS(operator, 
            "operator should not be registered to the AVS");
    }

    /*******************************************************************************
                                  UTIL METHODS
    *******************************************************************************/

    /// example output:
    /// - check_Register_State(Operator0)
    function _log(string memory s, User user) internal {
        emit log(string.concat("- ", s, "(", user.NAME(), ")"));
    }
}