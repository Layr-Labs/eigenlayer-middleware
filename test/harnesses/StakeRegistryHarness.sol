// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "../../src/StakeRegistry.sol";

// wrapper around the StakeRegistry contract that exposes the internal functions for unit testing.
contract StakeRegistryHarness is StakeRegistry {
    mapping(uint8 => mapping(address => uint96)) private __weightOfOperatorForQuorum;

    constructor(
        IRegistryCoordinator _registryCoordinator,
        IStrategyManager _strategyManager,
        IServiceManager _serviceManager
    ) StakeRegistry(_registryCoordinator, _strategyManager, _serviceManager) {
    }

    function recordOperatorStakeUpdate(bytes32 operatorId, uint8 quorumNumber, uint96 newStake) external returns(int256) {
        return _recordOperatorStakeUpdate(operatorId, quorumNumber, newStake);
    }

    function updateOperatorStake(address operator, bytes32 operatorId, uint8 quorumNumber) external returns (int256, bool) {
        return _updateOperatorStake(operator, operatorId, quorumNumber);
    }

    function recordTotalStakeUpdate(uint8 quorumNumber, int256 stakeDelta) external {
        _recordTotalStakeUpdate(quorumNumber, stakeDelta);
    }

    // mocked function so we can set this arbitrarily without having to mock other elements
    function weightOfOperatorForQuorum(uint8 quorumNumber, address operator) public override view returns(uint96) {
        return __weightOfOperatorForQuorum[quorumNumber][operator];
    }

    // mocked function so we can set this arbitrarily without having to mock other elements
    function setOperatorWeight(uint8 quorumNumber, address operator, uint96 weight) external {
        __weightOfOperatorForQuorum[quorumNumber][operator] = weight;
    }

    // mocked function to register an operator without having to mock other elements
    // This is just a copy/paste from `registerOperator`, since that no longer uses an internal method
    function registerOperatorNonCoordinator(address operator, bytes32 operatorId, bytes calldata quorumNumbers) external {
        for (uint256 i = 0; i < quorumNumbers.length; ) {            
            
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            require(_totalStakeHistory[quorumNumber].length != 0, "StakeRegistry.registerOperator: quorum does not exist");
            
            /**
             * Update the operator's stake for the quorum and retrieve their current stake
             * as well as the change in stake.
             * - If this method returns `hasMinimumStake == false`, the operator has not met 
             *   the minimum stake requirement for this quorum
             */
            (int256 stakeDelta, bool hasMinimumStake) = _updateOperatorStake({
                operator: operator, 
                operatorId: operatorId, 
                quorumNumber: quorumNumber
            });
            require(
                hasMinimumStake,
                "StakeRegistry.registerOperator: Operator does not meet minimum stake requirement for quorum"
            );

            // Update this quorum's total stake
            _recordTotalStakeUpdate(quorumNumber, stakeDelta);
            unchecked {
                ++i;
            }
        }
    }
}
