// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../User.t.sol";

import "../IntegrationChecks.t.sol";

contract Integration_Full_Register_Deregister is IntegrationChecks {
    using BitmapUtils for *;

    // 1. Register for all quorums by churning old operators
    // 2. Deregister from all quorums
    // 3. Re-register for all quorums without needing churn
    function testFuzz_churnAll_deregisterAll_reregisterAll(
        uint24 _random
    ) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT | ALT_METHODS,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE | TWO | MANY,
                numStrategies: ONE | TWO | MANY,
                minimumStake: NO_MINIMUM | HAS_MINIMUM,
                fillTypes: FULL,
                quorumType: DELEGATED_STAKE
            })
        });

        User operator = _newRandomOperator();
        bytes memory quorums = quorumArray;

        // Select churnable operators in each quorum. If needed, deals/deposits assets
        // for the operator, and fills any non-full quorums
        User[] memory churnTargets = _getChurnTargets({
            incomingOperator: operator,
            churnQuorums: quorums,
            standardQuorums: new bytes(0)
        });

        check_Never_Registered(operator);

        // 1. Register for all quorums by churning old operators
        operator.registerOperatorWithChurn(quorums, churnTargets, new bytes(0));
        check_Churned_State({
            incomingOperator: operator,
            churnedOperators: churnTargets,
            churnedQuorums: quorums,
            standardQuorums: new bytes(0)
        });

        // 2. Deregister from all quorums
        operator.deregisterOperator(quorums);
        check_Deregister_State(operator, quorums);
        check_CompleteDeregister_State(operator);

        // 3. Re-register for all quorums without needing churn
        operator.registerOperator(quorums);
        check_Register_State(operator, quorums);
    }

    // 1. Register for all quorums by churning old operators
    // 2. Deregister from all quorums
    // 3. Old operators re-register for quorums
    // 4. Original operator re-registers for all quorums by churning old operators again
    function testFuzz_churnAll_deregisterAll_oldReregisterAll(
        uint24 _random
    ) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT | ALT_METHODS,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE | TWO | MANY,
                numStrategies: ONE | TWO | MANY,
                minimumStake: NO_MINIMUM | HAS_MINIMUM,
                fillTypes: FULL,
                quorumType: DELEGATED_STAKE
            })
        });

        User operator = _newRandomOperator();
        bytes memory quorums = quorumArray;

        // Select churnable operators in each quorum, dealing additional assets to
        // the main operator if needed
        User[] memory churnTargets = _getChurnTargets({
            incomingOperator: operator,
            churnQuorums: quorums,
            standardQuorums: new bytes(0)
        });

        check_Never_Registered(operator);

        // 1. Register for all quorums by churning old operators
        operator.registerOperatorWithChurn(quorums, churnTargets, new bytes(0));
        check_Churned_State({
            incomingOperator: operator,
            churnedOperators: churnTargets,
            churnedQuorums: quorums,
            standardQuorums: new bytes(0)
        });

        // 2. Deregister from all quorums
        operator.deregisterOperator(quorums);
        check_Deregister_State(operator, quorums);
        check_CompleteDeregister_State(operator);

        // 3. Old operators re-register for quorums
        // Note: churnTargets.length == quorums.length, so we do these one at a time
        for (uint256 i = 0; i < churnTargets.length; i++) {
            User churnTarget = churnTargets[i];
            bytes memory quorum = new bytes(1);
            quorum[0] = quorums[i];

            churnTarget.registerOperator(quorum);
            check_Register_State(churnTarget, quorum);
        }

        // 4. Original operator re-registers for all quorums by churning old operators again
        operator.registerOperatorWithChurn(quorums, churnTargets, new bytes(0));
        check_Churned_State({
            incomingOperator: operator,
            churnedOperators: churnTargets,
            churnedQuorums: quorums,
            standardQuorums: new bytes(0)
        });
    }

    // 1. Register for *some* quorums with churn, and the rest without churn
    // 2. Deregister from all quorums
    // 3. Re-register for all quorums without needing churn
    function testFuzz_churnSome_deregisterSome_deregisterRemaining(
        uint24 _random
    ) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT | ALT_METHODS,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE | TWO | MANY,
                numStrategies: ONE | TWO | MANY,
                minimumStake: NO_MINIMUM | HAS_MINIMUM,
                fillTypes: FULL,
                quorumType: DELEGATED_STAKE
            })
        });

        User operator = _newRandomOperator();
        bytes memory quorums = quorumArray;

        // Select some quorums to register using churn, and the rest without churn
        bytes memory churnQuorums = _selectRand(quorums);
        bytes memory standardQuorums = quorums.orderedBytesArrayToBitmap().minus(
            churnQuorums.orderedBytesArrayToBitmap()
        ).bitmapToBytesArray();

        // Select churnable operators in each quorum. If needed, deals/deposits assets
        // for the operator, and deregisters operators from standardQuorums to make room
        User[] memory churnTargets = _getChurnTargets({
            incomingOperator: operator,
            churnQuorums: churnQuorums,
            standardQuorums: standardQuorums
        });

        check_Never_Registered(operator);

        // 1. Register for *some* quorums with churn, and the rest without churn
        operator.registerOperatorWithChurn({
            churnQuorums: churnQuorums,
            churnTargets: churnTargets,
            standardQuorums: standardQuorums
        });
        check_Churned_State({
            incomingOperator: operator,
            churnedOperators: churnTargets,
            churnedQuorums: churnQuorums,
            standardQuorums: standardQuorums
        });

        // 2. Deregister from all quorums
        operator.deregisterOperator(quorums);
        check_Deregister_State(operator, quorums);
        check_CompleteDeregister_State(operator);

        // 3. Re-register for all quorums without needing churn
        operator.registerOperator(quorums);
        check_Register_State(operator, quorums);
    }
}
