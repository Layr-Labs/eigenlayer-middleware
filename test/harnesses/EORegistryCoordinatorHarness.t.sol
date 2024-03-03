// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "../../src/EORegistryCoordinator.sol";

import "forge-std/Test.sol";

// wrapper around the EORegistryCoordinator contract that exposes the internal functions for unit testing.
contract EORegistryCoordinatorHarness is EORegistryCoordinator, Test {
    constructor(
        IServiceManager _serviceManager,
        IEOStakeRegistry _stakeRegistry,
        IEOBLSApkRegistry _blsApkRegistry,
        IEOIndexRegistry _indexRegistry
    ) EORegistryCoordinator(_serviceManager, _stakeRegistry, _blsApkRegistry, _indexRegistry) {
        _transferOwnership(msg.sender);
    }

    function setQuorumCount(uint8 count) external {
        quorumCount = count;
    }

    function setOperatorId(address operator, bytes32 operatorId) external {
        _operatorInfo[operator].operatorId = operatorId;
    }

    // @notice exposes the internal `_registerOperator` function, overriding all access controls
    function _registerOperatorExternal(
        address operator, 
        bytes32 operatorId,
        bytes calldata quorumNumbers,
        SignatureWithSaltAndExpiry memory operatorSignature
    ) external returns (RegisterResults memory results) {
        BN254.G1Point memory emptySignature; 
        return _registerOperator(operator, operatorId, quorumNumbers, operatorSignature,emptySignature);
    }

    // @notice exposes the internal `_deregisterOperator` function, overriding all access controls
    function _deregisterOperatorExternal(
        address operator, 
        bytes calldata quorumNumbers
    ) external {
        _deregisterOperator(operator, quorumNumbers);
    }

    // @notice exposes the internal `_updateOperator` function, overriding all access controls
    function _updateOperatorExternal(
        address operator,
        OperatorInfo memory operatorInfo,
        bytes memory quorumsToUpdate
    ) external {
        _updateOperator(operator, operatorInfo, quorumsToUpdate);
    }

    // @notice exposes the internal `_updateOperatorBitmap` function, overriding all access controls
    function _updateOperatorBitmapExternal(bytes32 operatorId, uint192 quorumBitmap) external {
        _updateOperatorBitmap(operatorId, quorumBitmap);
    }
}
