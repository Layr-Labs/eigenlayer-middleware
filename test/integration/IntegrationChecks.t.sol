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

        // RegistryCoordinator checks
        assert_HasNoOperatorInfo(operator,
            "operator should have empty id and NEVER_REGISTERED status");
        assert_EmptyQuorumBitmap(operator,
            "operator already has bits in quorum bitmap");

        // BLSApkRegistry checks
        assert_NoRegisteredPubkey(operator, 
            "operator already has a registered pubkey");

        // DelegationManager checks
        assert_NotRegisteredToAVS(operator, 
            "operator should not be registered to the AVS");
    }

    function check_Can_Register(
        User operator,
        bytes memory quorums
    ) internal {
        _log("check_Can_Register", operator);

        /// Check whether the operator is in a valid state to register for `quorums` with the AVS
        assert_QuorumsExist(quorums,
            "not all quorums exist");
        // assert_BelowMaxOperators(quorums,
        //     "operator cap reached");
        assert_NotRegisteredForQuorums(operator, quorums,
            "operator is already registered for some quorums");
        assert_MeetsMinimumShares(operator, quorums,
            "operator does not meet minimum shares for all quorums");
    }

    function check_Register_State(
        User operator,
        IStrategy[] memory strategies,
        uint[] memory shares,
        bytes memory quorums
    ) internal {
        _log("check_Register_State", operator);

        // RegistryCoordinator checks
        assert_HasOperatorInfoWithId(operator, 
            "operatorInfo should have operatorId");
        assert_HasRegisteredStatus(operator,
            "operatorInfo status should be REGISTERED");
        assert_IsRegisteredForQuorums(operator, quorums,
            "current operator bitmap should include quorums");
        assert_Snap_RegisteredForQuorums(operator, quorums,
            "operator did not register for all quorums");

        // BLSApkRegistry checks
        assert_HasRegisteredPubkey(operator, 
            "operator should have registered a pubkey");
        assert_Snap_Added_QuorumApk(operator, quorums, 
            "operator pubkey should have been added to each quorum apk");
        
        // StakeRegistry checks

        // IndexRegistry checks

        // DelegationManager checks
        assert_IsRegisteredToAVS(operator,
            "operator should be registered to AVS");
    }

    /// @dev Check that the operator correctly deregistered from some quorums
    function check_Deregister_State(
        User operator,
        bytes memory quorums
    ) internal {
        _log("check_Deregister_State", operator);


    }

    /// @dev Check that the operator correctly deregistered from ALL their quorums
    function check_CompleteDeregister_State(
        User operator
    ) internal {
        _log("check_CompleteDeregister_State", operator);


    }

    /// ex:
    /// - check_Register_State(Operator0)
    function _log(string memory s, User user) internal {
        emit log(string.concat("- ", s, "(", user.NAME(), ")"));
    }
}