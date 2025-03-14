// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../User.t.sol";

import "../IntegrationChecks.t.sol";

contract Integration_NonFull_Register_Deregister is IntegrationChecks {
    using BitmapUtils for *;

    // 1. Register for all quorums
    // 2. Deregister from all quorums
    function testFuzz_registerAll_deregisterAll(
        uint24 _random
    ) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT | ALT_METHODS,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE | TWO | MANY,
                numStrategies: ONE | TWO | MANY,
                minimumStake: NO_MINIMUM | HAS_MINIMUM,
                fillTypes: EMPTY | SOME_FILL,
                quorumType: DELEGATED_STAKE
            })
        });

        User operator = _newRandomOperator();
        bytes memory quorums = quorumArray;

        check_Never_Registered(operator);

        // 1. Register for all quorums
        operator.registerOperator(quorums);
        check_Register_State(operator, quorums);

        // 2. Deregister from all quorums
        operator.deregisterOperator(quorums);
        check_Deregister_State(operator, quorums);
        check_CompleteDeregister_State(operator);
    }

    // 1. Register for some quorums
    // 2. Deregister from some quorums
    // 3. Deregister from any remaining quorums
    function testFuzz_registerSome_deregisterSome_deregisterRemaining(
        uint24 _random
    ) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT | ALT_METHODS,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE | TWO | MANY,
                numStrategies: ONE | TWO | MANY,
                minimumStake: NO_MINIMUM | HAS_MINIMUM,
                fillTypes: EMPTY | SOME_FILL,
                quorumType: DELEGATED_STAKE
            })
        });

        User operator = _newRandomOperator();
        // Select at least one quorum to register for
        bytes memory quorums = _selectRand(quorumArray);

        check_Never_Registered(operator);

        // 1. Register for some quorums
        operator.registerOperator(quorums);
        check_Register_State(operator, quorums);

        // 2. Deregister from at least one quorum
        bytes memory quorumsToRemove = _selectRand(quorums);
        operator.deregisterOperator(quorumsToRemove);
        check_Deregister_State(operator, quorumsToRemove);

        // 3. Deregister from any remaining quorums
        bytes memory quorumsRemaining = _calcRemaining({start: quorums, removed: quorumsToRemove});
        if (quorumsRemaining.length != 0) {
            operator.deregisterOperator(quorumsRemaining);
            check_Deregister_State(operator, quorumsRemaining);
        }
        check_CompleteDeregister_State(operator);
    }

    // 1. Register for some quorums
    // 2. Deregister from some quorums
    // 3. Reregister for some quorums
    function testFuzz_registerSome_deregisterSome_reregisterSome(
        uint24 _random
    ) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT | ALT_METHODS,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE | TWO | MANY,
                numStrategies: ONE | TWO | MANY,
                minimumStake: NO_MINIMUM | HAS_MINIMUM,
                fillTypes: EMPTY | SOME_FILL,
                quorumType: DELEGATED_STAKE
            })
        });

        User operator = _newRandomOperator();
        // Select at least one quorum to register for
        bytes memory quorums = _selectRand(quorumArray);

        check_Never_Registered(operator);

        // 1. Register for some quorums
        operator.registerOperator(quorums);
        check_Register_State(operator, quorums);

        // 2. Deregister from at least one quorum
        bytes memory quorumsToRemove = _selectRand(quorums);
        operator.deregisterOperator(quorumsToRemove);
        check_Deregister_State(operator, quorumsToRemove);

        // 3. Reregister for at least one quorum
        bytes memory quorumsToAdd = _selectRand(quorumsToRemove);
        operator.registerOperator(quorumsToAdd);
        check_Register_State(operator, quorumsToAdd);
    }
}
