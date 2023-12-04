// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "../../src/interfaces/IServiceManager.sol";
import "eigenlayer-contracts/src/contracts/interfaces/ISlasher.sol";

contract ServiceManagerMock is IServiceManager{
    address public owner;
    ISlasher public slasher;

    constructor(ISlasher _slasher) {
        owner = msg.sender;
        slasher = _slasher;

    }

    /// @notice Permissioned function that causes the ServiceManager to freeze the operator on EigenLayer, through a call to the Slasher contract
    function freezeOperator(address operator) external {
        slasher.freezeOperator(operator);
    }
    
    /// @notice Returns the `latestServeUntilBlock` until which operators must serve.
    function latestServeUntilBlock() external pure returns (uint32) {
        return type(uint32).max;
    }
}
