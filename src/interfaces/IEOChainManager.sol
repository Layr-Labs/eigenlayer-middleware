// SPDX-License-Identifier: MIT
pragma solidity =0.8.12;

interface IEOChainManager {
    function registerValidator(address operator, uint96[] calldata stakes, uint256[2] memory chainValidatorSignature,uint256[4] memory publicG2Key) external;
    function registerValidator(address operator, uint96[] calldata stakes) external;
    function deregisterValidator(address operator) external;
}
