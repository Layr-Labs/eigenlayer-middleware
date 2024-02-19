// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

contract GreeterV2 {
    string public greeting;
    
    function initialize(string memory _greeting) public {
        greeting = _greeting;
    }

    function resetGreeting() public {
        greeting = "resetted";
    }
}
