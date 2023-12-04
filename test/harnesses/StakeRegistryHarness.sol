// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "../../src/StakeRegistry.sol";

// wrapper around the StakeRegistry contract that exposes the internal functions for unit testing.
contract StakeRegistryHarness is StakeRegistry {
    mapping(uint8 => mapping(address => uint96)) private _weightOfOperatorForQuorum;

    constructor(
        IRegistryCoordinator _registryCoordinator,
        IStrategyManager _strategyManager,
        IServiceManager _serviceManager
    ) StakeRegistry(_registryCoordinator, _strategyManager, _serviceManager) {
    }

    function recordOperatorStakeUpdate(bytes32 operatorId, uint8 quorumNumber, OperatorStakeUpdate memory operatorStakeUpdate) external returns(uint96) {
        return _recordOperatorStakeUpdate(operatorId, quorumNumber, operatorStakeUpdate);
    }

    function updateOperatorStake(address operator, bytes32 operatorId, uint8 quorumNumber) external returns (uint96, uint96) {
        return _updateOperatorStake(operator, operatorId, quorumNumber);
    }

    function recordTotalStakeUpdate(uint8 quorumNumber, OperatorStakeUpdate memory totalStakeUpdate) external {
        _recordTotalStakeUpdate(quorumNumber, totalStakeUpdate);
    }

    // mocked function so we can set this arbitrarily without having to mock other elements
    function weightOfOperatorForQuorum(uint8 quorumNumber, address operator) public override view returns(uint96) {
        return _weightOfOperatorForQuorum[quorumNumber][operator];
    }

    // mocked function so we can set this arbitrarily without having to mock other elements
    function setOperatorWeight(uint8 quorumNumber, address operator, uint96 weight) external {
        _weightOfOperatorForQuorum[quorumNumber][operator] = weight;
    }

    // mocked function to register an operator without having to mock other elements
    // This is just a copy/paste from `registerOperator`, since that no longer uses an internal method
    function registerOperatorNonCoordinator(address operator, bytes32 operatorId, bytes calldata quorumNumbers) external {
        // check the operator is registering for only valid quorums
        require(
            uint8(quorumNumbers[quorumNumbers.length - 1]) < quorumCount,
            "StakeRegistry._registerOperator: greatest quorumNumber must be less than quorumCount"
        );
        OperatorStakeUpdate memory _newTotalStakeUpdate;
        // add the `updateBlockNumber` info
        _newTotalStakeUpdate.updateBlockNumber = uint32(block.number);
        // for each quorum, evaluate stake and add to total stake
        for (uint8 quorumNumbersIndex = 0; quorumNumbersIndex < quorumNumbers.length; ) {
            // get the next quorumNumber
            uint8 quorumNumber = uint8(quorumNumbers[quorumNumbersIndex]);
            // evaluate the stake for the operator
            // since we don't use the first output, this will use 1 extra sload when deregistered operator's register again
            (, uint96 stake) = _updateOperatorStake(operator, operatorId, quorumNumber);
            // check if minimum requirement has been met, will be 0 if not
            require(
                stake != 0,
                "StakeRegistry._registerOperator: Operator does not meet minimum stake requirement for quorum"
            );
            // add operator stakes to total stake before update (in memory)
            uint256 _totalStakeHistoryLength = _totalStakeHistory[quorumNumber].length;
            // add calculate the total stake for the quorum
            uint96 totalStakeAfterUpdate = stake;
            if (_totalStakeHistoryLength != 0) {
                // only add the stake if there is a previous total stake
                // overwrite `stake` variable
                totalStakeAfterUpdate += _totalStakeHistory[quorumNumber][_totalStakeHistoryLength - 1].stake;
            }
            _newTotalStakeUpdate.stake = totalStakeAfterUpdate;
            // update storage of total stake
            _recordTotalStakeUpdate(quorumNumber, _newTotalStakeUpdate);
            unchecked {
                ++quorumNumbersIndex;
            }
        }
    }
}
