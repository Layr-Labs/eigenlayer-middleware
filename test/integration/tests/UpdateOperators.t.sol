// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "test/integration/User.t.sol";

import "test/integration/IntegrationChecks.t.sol";

// import "test/integration/utils/Sort.t.sol";

contract Integration_AVS_Sync_GasCosts is IntegrationChecks {

    using BitmapUtils for *;

    function testFuzz_gasCosts_10Operators_25Strats(uint24 _random) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE,
                numStrategies: TWENTYFIVE,
                minimumStake: NO_MINIMUM,
                fillTypes: FULL
            })
        });
        _updateOperators_SingleQuorum();
    }

    // Configure quorum with several strategies and log gas costs
    function testFuzz_gasCosts_10Operators_20Strats(uint24 _random) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE,
                numStrategies: TWENTY,
                minimumStake: NO_MINIMUM,
                fillTypes: FULL
            })
        });

        _updateOperators_SingleQuorum();
    }

    function testFuzz_gasCosts_10Operators_15Strats(uint24 _random) public {
        _configRand({
            _randomSeed: _random,
            _userTypes: DEFAULT,
            _quorumConfig: QuorumConfig({
                numQuorums: ONE,
                numStrategies: FIFTEEN,
                minimumStake: NO_MINIMUM,
                fillTypes: FULL
            })
        });
        _updateOperators_SingleQuorum();
    }

    function _updateOperators_SingleQuorum() internal {
        // Sort operator addresses
        address[] memory operators = operatorsForQuorum[0];
        operators = _sortArray(operators);

        // Call params
        address[][] memory operatorsPerQuorum = new address[][](1);
        operatorsPerQuorum[0] = operators;
        bytes memory quorumNumbers = quorumArray;

        // Update Operators for quorum 0
        uint256 gasBefore = gasleft();
        registryCoordinator.updateOperatorsForQuorum(operatorsPerQuorum, quorumNumbers);
        uint256 gasAfter = gasleft();
        emit log_named_uint("gasUsed", gasBefore - gasAfter);
        console.log("Num operators updated: ", operators.length);
        console.log("Gas used for updateOperatorsForQuorum: ", gasBefore - gasAfter);
    }

    function _sortArray(address[] memory arr) internal pure returns (address[] memory) {
        uint256 l = arr.length;
        for(uint i = 0; i < l; i++) {
            for(uint j = i+1; j < l ;j++) {
                if(arr[i] > arr[j]) {
                    address temp = arr[i];
                    arr[i] = arr[j];
                    arr[j] = temp;
                }
            }
        }
        return arr;
    }
}