// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "test/integration/IntegrationBase.t.sol";
import "test/integration/User.t.sol";

/// @notice Contract that provides utility functions to reuse common test blocks & checks
contract IntegrationChecks is IntegrationBase {
    
    function check_Never_Registered(
        User operator
    ) internal {
        _log(operator, ": check_Never_Registered");

        assert_HasNoOperatorInfo(operator,
            "operator already has an operatorId or status");
        assert_EmptyQuorumBitmap(operator,
            "operator already has bits in quorum bitmap");
    }

    function check_Can_Register(
        User operator,
        bytes memory quorums
    ) internal {
        _log(operator, ": check_Can_Register");

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
        _log(operator, ": check_Register_State");

        assert_Snap_RegisteredForQuorums(operator, quorums,
            "operator did not register for all quorums");
    }

    function _log(User user, string memory s) internal {
        emit log(string.concat(user.NAME(), s));
    }
}