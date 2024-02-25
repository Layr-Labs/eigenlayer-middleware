// SPDX-License-Identifier: MIT
pragma solidity =0.8.12;

interface ICustomChainManager {
    function registerValidator(address operator, uint96[] calldata stakes) external;
    function deregisterValidator(address operator) external;
}
