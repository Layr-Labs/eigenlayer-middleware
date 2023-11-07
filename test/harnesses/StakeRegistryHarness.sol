// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "src/StakeRegistry.sol";

// wrapper around the StakeRegistry contract that exposes the internal functions for unit testing.
contract StakeRegistryHarness is StakeRegistry {
    mapping(uint8 => mapping(address => uint96)) private __weightOfOperatorForQuorum;

    constructor(
        IRegistryCoordinator _registryCoordinator,
        IDelegationManager _delegationManager,
        IServiceManager _serviceManager
    ) StakeRegistry(_registryCoordinator, _delegationManager, _serviceManager) {
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
        return (__weightOfOperatorForQuorum[quorumNumber][operator], true);
    }

    // mocked function so we can set this arbitrarily without having to mock other elements
    function setOperatorWeight(uint8 quorumNumber, address operator, uint96 weight) external {
        __weightOfOperatorForQuorum[quorumNumber][operator] = weight;
    }

    // mocked function to register an operator without having to mock other elements
    // This is just a copy/paste from `registerOperator`, since that no longer uses an internal method
    function registerOperatorNonCoordinator(address operator, bytes32 operatorId, bytes calldata quorumNumbers) external returns (uint96[] memory, uint96[] memory) {
        uint96[] memory currentStakes = new uint96[](quorumNumbers.length);
        uint96[] memory totalStakes = new uint96[](quorumNumbers.length);
        for (uint256 i = 0; i < quorumNumbers.length; i++) {            
            
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            require(_quorumExists(quorumNumber), "StakeRegistry.registerOperator: quorum does not exist");

            // Retrieve the operator's current weighted stake for the quorum, reverting if they have not met
            // the minimum.
            (uint96 currentStake, bool hasMinimumStake) = _weightOfOperatorForQuorum(quorumNumber, operator);
            require(
                hasMinimumStake,
                "StakeRegistry.registerOperator: Operator does not meet minimum stake requirement for quorum"
            );

            // Update the operator's stake
            int256 stakeDelta = _recordOperatorStakeUpdate({
                operatorId: operatorId, 
                quorumNumber: quorumNumber,
                newStake: currentStake
            });

            // Update this quorum's total stake by applying the operator's delta
            currentStakes[i] = currentStake;
            totalStakes[i] = _recordTotalStakeUpdate(quorumNumber, stakeDelta);
        }

        return (currentStakes, totalStakes);
    }
}
