// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "test/integration/User.t.sol";

import "test/integration/IntegrationChecks.t.sol";

contract Integration_Register_Deregister is IntegrationChecks {

    // 1. Register for all quorums
    function testFuzz_registerAll_Hello(uint24 _random) public {
        _configRand({
            _randomSeed: _random,
            _quorumTypes: ONE | TWO | MANY,
            _strategyTypes: ONE | TWO | MANY,
            _minStakeTypes: NO_MINIMUM | HAS_MINIMUM
        });

        // Create a random operator holding shares in various strategies
        (User operator, IStrategy[] memory strategies, uint[] memory shares) 
            = _newRandomOperator();
        // // Fetch random quorums to register for
        // // This returns at least one of the existing quorums
        // bytes memory quorums = _randQuorums();
        bytes memory quorums = quorumArray;

        // For fresh operators, check that we haven't seen them before.
        check_Never_Registered(operator);
        // Check that the operator meets the minimum stake and requirements to register and
        // that they aren't already registered for any of the quorums
        check_Can_Register(operator, quorums);
        
        // 1. Register for all quorums
        operator.registerOperator(quorums);
        check_Register_State(operator, strategies, shares, quorums);
    }

    // 1. Register for all quorums
    function testFuzz_registerAll_Hello2(uint24 _random) public {
        _configRand({
            _randomSeed: _random,
            _quorumTypes: ONE | TWO | MANY,
            _strategyTypes: ONE | TWO | MANY,
            _minStakeTypes: NO_MINIMUM | HAS_MINIMUM
        });

        // Create a random operator holding shares in various strategies
        (User operator, IStrategy[] memory strategies, uint[] memory shares) 
            = _newRandomOperator();
        // // Fetch random quorums to register for
        // // This returns at least one of the existing quorums
        // bytes memory quorums = _randQuorums();
        bytes memory quorums = quorumArray;

        // For fresh operators, check that we haven't seen them before.
        check_Never_Registered(operator);
        // Check that the operator meets the minimum stake and requirements to register and
        // that they aren't already registered for any of the quorums
        check_Can_Register(operator, quorums);
        
        // 1. Register for all quorums
        operator.registerOperator(quorums);
        check_Register_State(operator, strategies, shares, quorums);
    }
}