// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "test/integration/IntegrationBase.t.sol";
import "test/integration/User.t.sol";

/// @notice Contract that provides utility functions to reuse common test blocks & checks
contract IntegrationChecks is IntegrationBase {
    
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
        assert_MeetsMinimumShares(operator, quorums,
            "operator does not meet minimum shares for all quorums");

        // IndexRegistry
        assert_BelowMaxOperators(quorums,
            "operator cap reached");
    }

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
        assert_Snap_Added_OperatorStake(operator, quorums,
            "failed to add operator weight to each quorum");
        assert_Snap_Added_TotalStake(operator, quorums,
            "failed to add operator weight to total stake for each quorum");

        // IndexRegistry
        assert_Snap_Added_OperatorCount(quorums,
            "total operator count should have increased for each quorum");
        assert_Snap_Added_OperatorListEntry(quorums,
            "operator list should have one more entry");

        // DelegationManager
        assert_IsRegisteredToAVS(operator,
            "operator should be registered to AVS");
    }

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
        assert_Snap_Removed_OperatorStake(operator, quorums,
            "failed to remove operator weight from each quorum");
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

    /// ex:
    /// - check_Register_State(Operator0)
    function _log(string memory s, User user) internal {
        emit log(string.concat("- ", s, "(", user.NAME(), ")"));
    }
}