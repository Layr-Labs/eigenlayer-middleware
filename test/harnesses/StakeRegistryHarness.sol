// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "../../src/StakeRegistry.sol";

// wrapper around the StakeRegistry contract that exposes the internal functions for unit testing.
contract StakeRegistryHarness is StakeRegistry {
    mapping(uint8 => mapping(address => uint96)) private __weightOfOperatorForQuorum;

    constructor(
        IRegistryCoordinator _registryCoordinator,
        IDelegationManager _delegationManager
    ) StakeRegistry(_registryCoordinator, _delegationManager) {
    }

    function recordOperatorStakeUpdate(bytes32 operatorId, uint8 quorumNumber, uint96 newStake) external returns(int256) {
        return _recordOperatorStakeUpdate(operatorId, quorumNumber, newStake);
    }

    function recordTotalStakeUpdate(uint8 quorumNumber, int256 stakeDelta) external {
        _recordTotalStakeUpdate(quorumNumber, stakeDelta);
    }

    // mocked function so we can set this arbitrarily without having to mock other elements
    function weightOfOperatorForQuorum(uint8 quorumNumber, address operator) public override view returns(uint96) {
        return __weightOfOperatorForQuorum[quorumNumber][operator];
    }

    function _weightOfOperatorForQuorum(uint8 quorumNumber, address operator) internal override view returns(uint96, bool) {
        uint96 weight = __weightOfOperatorForQuorum[quorumNumber][operator];
        return (
            weight, 
            weight >= minimumStakeForQuorum[quorumNumber]
        );
    }

    // mocked function so we can set this arbitrarily without having to mock other elements
    function setOperatorWeight(uint8 quorumNumber, address operator, uint96 weight) external {
        __weightOfOperatorForQuorum[quorumNumber][operator] = weight;
    }

    function calculateDelta(uint96 prev, uint96 cur) external pure returns (int256) {
        return _calculateDelta(prev, cur);
    }

    function applyDelta(uint96 value, int256 delta) external pure returns (uint96) {
        return _applyDelta(value, delta);
    }
}
