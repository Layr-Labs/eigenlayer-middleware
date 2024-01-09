// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "test/integration/User.t.sol";

import "test/integration/IntegrationChecks.t.sol";

contract Integration_Full_Register_Deregister is IntegrationChecks {

    using BitmapUtils for *;

    // 1. Register for all quorums by churning old operators
    // 2. Deregister from all quorums
    // 3. Re-register for all quorums without needing churn
    function testFuzz_churnAll_deregisterAll_reregisterAll(uint24 _random) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT | ALT_METHODS,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE | TWO | MANY,
                numStrategies: ONE | TWO | MANY,
                minimumStake: NO_MINIMUM | HAS_MINIMUM,
                fillTypes: FULL
            })
        });

        User operator = _newRandomOperator();
        bytes memory quorums = quorumArray;

        // Select churnable operators in each quorum. If needed, deals/deposits assets
        // for the operator, and fills any non-full quorums
        User[] memory churnTargets = _getChurnTargets(operator, quorums);

        check_Never_Registered(operator);
        check_Can_Churn(operator, churnTargets, quorums);

        // 1. Register for all quorums by churning old operators
        operator.registerOperatorWithChurn(quorums, churnTargets);
        check_Register_State(operator, quorums);
        check_Churned_State(operator, churnTargets, quorums);

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
    function testFuzz_churnAll_deregisterAll_reregisterAll(uint24 _random) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT | ALT_METHODS,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE | TWO | MANY,
                numStrategies: ONE | TWO | MANY,
                minimumStake: NO_MINIMUM | HAS_MINIMUM,
                fillTypes: FULL
            })
        });

        User operator = _newRandomOperator();
        bytes memory quorums = quorumArray;

        // Select churnable operators in each quorum, dealing additional assets to
        // the main operator if needed
        User[] memory churnTargets = _getChurnTargets(operator, quorums);

        check_Never_Registered(operator);
        check_Can_Churn(operator, churnTargets, quorums);

        // 1. Register for all quorums by churning old operators
        operator.registerOperatorWithChurn(quorums, churnTargets);
        check_Register_State(operator, quorums);
        check_Churned_State(operator, churnTargets, quorums);

        // 2. Deregister from all quorums
        operator.deregisterOperator(quorums);
        check_Deregister_State(operator, quorums);
        check_CompleteDeregister_State(operator);

        // 3. Old operators re-register for quorums
        // Note: churnTargets.length == quorums.length, so we do these one at a time
        for (uint i = 0; i < churnTargets.length; i++) {
            User churnTarget = churnTargets[i];
            bytes memory quorum = quorums[i:i+1];

            check_Can_Register(churnTarget, quorum);
            churnTarget.registerOperator(quorum);
            check_Register_State(churnTarget, quorum);
        }

        // Check that the operator could churn each target again
        check_Can_Churn(operator, churnTargets, quorums);
    }

    // 1. Register for *some* quorums with churn, and the rest without churn
    // 2. Deregister from all quorums
    // 3. Re-register for all quorums without needing churn
    function testFuzz_registerSome_deregisterSome_deregisterRemaining(uint24 _random) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT | ALT_METHODS,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE | TWO | MANY,
                numStrategies: ONE | TWO | MANY,
                minimumStake: NO_MINIMUM | HAS_MINIMUM,
                fillTypes: EMPTY | SOME_FILL
            })
        });

        User operator = _newRandomOperator();
        bytes memory quorums = quorumArray;

        // Select some quorums to register using churn, and the rest without churn
        bytes memory churnQuorums = _selectRand(quorums);
        bytes memory standardQuorums = 
            quorums
                .minus(churnQuorums.orderedBytesArrayToBitmap())
                .bitmapToBytesArray();

        // Select churnable operators in each quorum. If needed, deals/deposits assets
        // for the operator, and fills any non-full quorums
        User[] memory churnTargets = _getChurnTargets(operator, churnQuorums);

        check_Never_Registered(operator);
        check_Can_Churn(operator, churnTargets, churnQuorums);
        check_Can_Register(operator, standardQuorums);

        // 1. Register for *some* quorums with churn, and the rest without churn
        operator.registerOperatorWithChurn({
            churnQuorums: churnQuorums,
            churnTargets: churnTargets,
            standardQuorums: standardQuorums
        });
        check_Register_State(operator, quorums);
        check_Churned_State(operator, churnTargets, quorums);

        // 2. Deregister from all quorums
        operator.deregisterOperator(quorums);
        check_Deregister_State(operator, quorums);
        check_CompleteDeregister_State(operator);

        // 3. Re-register for all quorums without needing churn
        operator.registerOperator(quorums);
        check_Register_State(operator, quorums);
    }

    // 1. Register for all quorums by churning old operators
    // 2. Each old operator deposits funds into EigenLayer
    // 3. Each old operator re-registers by churning
    function testFuzz_registerSome_deregisterSome_reregisterSome(uint24 _random) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT | ALT_METHODS,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE | TWO | MANY,
                numStrategies: ONE | TWO | MANY,
                minimumStake: NO_MINIMUM | HAS_MINIMUM,
                fillTypes: FULL
            })
        });

        revert("TODO");

        // User operator = _newRandomOperator();
        // // Select at least one quorum to register for
        // bytes memory quorums = _selectRand(quorumArray);

        // check_Never_Registered(operator);
        // check_Can_Register(operator, quorums);

        // // 1. Register for some quorums
        // operator.registerOperator(quorums);
        // check_Register_State(operator, quorums);

        // // 2. Deregister from at least one quorum
        // bytes memory quorumsToRemove = _selectRand(quorums);
        // operator.deregisterOperator(quorumsToRemove);
        // check_Deregister_State(operator, quorumsToRemove);

        // // 3. Reregister for at least one quorum
        // bytes memory quorumsToAdd = _selectRand(quorumsToRemove);
        // operator.registerOperator(quorumsToAdd);
        // check_Register_State(operator, quorumsToAdd);
    }
}