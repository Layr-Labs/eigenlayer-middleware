// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

contract Greeter {
    string public greeting;

    function initialize(string memory _greeting) public {
        greeting = _greeting;
    }
}

