// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Proxiable} from "./GreeterProxiable.sol";

contract GreeterV2Proxiable is Proxiable {
    string public greeting;

    function initialize(string memory _greeting) public {
        greeting = _greeting;
    }

    function resetGreeting() public {
        greeting = "resetted";
    }
}

