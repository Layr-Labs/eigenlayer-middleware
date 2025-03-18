// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../User.t.sol";

import "../IntegrationChecks.t.sol";

contract Integration_NonFull_Register_CoreBalanceChange_Update is IntegrationChecks {
    // 1. Register for all quorums
    // 2. (core) Deposit additional tokens
    // 3. Update stakes
    // 4. Deregister from all quorums
    function testFuzz_registerAll_increaseCoreBalance_update_deregisterAll(
        uint24 _random
    ) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT | ALT_METHODS,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE | TWO | MANY,
                numStrategies: ONE | TWO | MANY,
                minimumStake: HAS_MINIMUM,
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

        // Award operator tokens to deposit into core
        (IStrategy[] memory strategies, uint256[] memory tokenBalances) = _dealRandTokens(operator);

        // 2. (core) Deposit tokens and return the weight added in each initialized quorum
        operator.depositIntoEigenlayer(strategies, tokenBalances);
        check_Deposit_State(operator, quorums, strategies, tokenBalances);
        uint96[] memory addedWeights = _getAddedWeight(operator, quorums);

        // 3. Update stakes
        operator.updateStakes();
        check_DepositUpdate_State(operator, quorums, addedWeights);

        // 4. Deregister from all quorums
        operator.deregisterOperator(quorums);
        check_Deregister_State(operator, quorums);
        check_CompleteDeregister_State(operator);
    }

    // 1. Register for all quorums
    // 2. (core) Deposit additional tokens
    // 3. Deregister from all quorums
    function testFuzz_registerAll_increaseCoreBalance_deregisterAll(
        uint24 _random
    ) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT | ALT_METHODS,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE | TWO | MANY,
                numStrategies: ONE | TWO | MANY,
                minimumStake: HAS_MINIMUM,
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

        // Award operator tokens to deposit into core
        (IStrategy[] memory strategies, uint256[] memory tokenBalances) = _dealRandTokens(operator);

        // 2. (core) Deposit tokens
        operator.depositIntoEigenlayer(strategies, tokenBalances);
        check_Deposit_State(operator, quorums, strategies, tokenBalances);

        // 3. Deregister from all quorums
        operator.deregisterOperator(quorums);
        check_Deregister_State(operator, quorums);
        check_CompleteDeregister_State(operator);
    }

    // 1. Register for all quorums
    // 2. (core) Queue full withdrawal
    // 3. updateOperators/updateOperatorsForQuorum
    function testFuzz_registerAll_decreaseCoreBalance_update(
        uint24 _random
    ) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT | ALT_METHODS,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE | TWO | MANY,
                numStrategies: ONE | TWO | MANY,
                minimumStake: HAS_MINIMUM,
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

        // 2. (core) queue full withdrawal
        (IStrategy[] memory strategies, uint256[] memory shares) = operator.exitEigenlayer();
        check_Withdraw_State(operator, quorums, strategies, shares);

        // 3. Update stakes
        operator.updateStakes();
        check_WithdrawUpdate_State(operator, quorums);
    }

    // 1. Register for all quorums
    // 2. (core) Queue full withdrawal
    // 3. Deregister from all quorums
    function testFuzz_registerAll_decreaseCoreBalance_deregisterAll(
        uint24 _random
    ) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT | ALT_METHODS,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE | TWO | MANY,
                numStrategies: ONE | TWO | MANY,
                minimumStake: HAS_MINIMUM,
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

        // 2. (core) queue full withdrawal
        (IStrategy[] memory strategies, uint256[] memory shares) = operator.exitEigenlayer();
        check_Withdraw_State(operator, quorums, strategies, shares);

        // 3. Deregister from all quorums
        operator.deregisterOperator(quorums);
        check_Deregister_State(operator, quorums);
        check_CompleteDeregister_State(operator);
    }

    // 1. Register for all quorums
    // 2. updateOperators/updateOperatorsForQuorum
    // 3. Deregister from all quorums
    function testFuzz_registerAll_update_deregisterAll(
        uint24 _random
    ) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT | ALT_METHODS,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE | TWO | MANY,
                numStrategies: ONE | TWO | MANY,
                minimumStake: HAS_MINIMUM,
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

        // 2. Update stakes
        operator.updateStakes();
        check_NoUpdate_State(operator, quorums);

        // 3. Deregister from all quorums
        operator.deregisterOperator(quorums);
        check_Deregister_State(operator, quorums);
        check_CompleteDeregister_State(operator);
    }
}
