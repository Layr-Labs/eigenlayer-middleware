// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {AVSRegistrar} from "../../src/AVSRegistrar.sol";

contract AVSRegistrarMock is AVSRegistrar {
    function registerOperator(
        address operator,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) external override {}

    function deregisterOperator(
        address operator,
        uint32[] calldata operatorSetIds
    ) external override {}
}
