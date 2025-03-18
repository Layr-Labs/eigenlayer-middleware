// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../../src/RegistryCoordinator.sol";
import {ISocketRegistry} from "../../src/interfaces/ISocketRegistry.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IRegistryCoordinatorTypes} from "../../src/interfaces/IRegistryCoordinator.sol";

import "forge-std/Test.sol";

// wrapper around the RegistryCoordinator contract that exposes the internal functions for unit testing.
contract RegistryCoordinatorHarness is RegistryCoordinator, Test {
    constructor(
        IServiceManager _serviceManager,
        IStakeRegistry _stakeRegistry,
        IBLSApkRegistry _blsApkRegistry,
        IIndexRegistry _indexRegistry,
        ISocketRegistry _socketRegistry,
        IAllocationManager _allocationManager,
        IPauserRegistry _pauserRegistry,
        string memory _version
    )
        RegistryCoordinator(
            IRegistryCoordinatorTypes.RegistryCoordinatorParams(
                _serviceManager,
                IRegistryCoordinatorTypes.SlashingRegistryParams(
                    _stakeRegistry,
                    _blsApkRegistry,
                    _indexRegistry,
                    _socketRegistry,
                    _allocationManager,
                    _pauserRegistry
                )
            )
        )
    {
        _transferOwnership(msg.sender);
    }

    function setQuorumCount(
        uint8 count
    ) external {
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
        string memory socket,
        SignatureWithSaltAndExpiry memory operatorSignature
    ) external returns (RegisterResults memory results) {
        return _registerOperator({
            operator: operator,
            operatorId: operatorId,
            quorumNumbers: quorumNumbers,
            socket: socket,
            checkMaxOperatorCount: true
        });
    }

    // @notice exposes the internal `_deregisterOperator` function, overriding all access controls
    function _deregisterOperatorExternal(address operator, bytes calldata quorumNumbers) external {
        _deregisterOperator(operator, quorumNumbers);
    }

    // @notice exposes the internal `_updateOperatorBitmap` function, overriding all access controls
    function _updateOperatorBitmapExternal(bytes32 operatorId, uint192 quorumBitmap) external {
        _updateOperatorBitmap(operatorId, quorumBitmap);
    }

    function setOperatorSetsEnabled(
        bool enabled
    ) external {
        operatorSetsEnabled = enabled;
    }

    function setM2QuorumRegistrationDisabled(
        bool disabled
    ) external {
        isM2QuorumRegistrationDisabled = disabled;
    }

    function setM2QuorumBitmap(
        uint256 bitmap
    ) external {
        _m2QuorumBitmap = bitmap;
    }

    function supportsAVS(
        address avs
    ) public view override(IAVSRegistrar, SlashingRegistryCoordinator) returns (bool) {
        return avs == address(serviceManager);
    }
}
