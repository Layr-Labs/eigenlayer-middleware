// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "../../src/RegistryCoordinator.sol";

import "forge-std/Test.sol";

// wrapper around the RegistryCoordinator contract that exposes the internal functions for unit testing.
contract RegistryCoordinatorHarness is RegistryCoordinator, Test {
    constructor(
        IServiceManager _serviceManager,
        IStakeRegistry _stakeRegistry,
        IBLSApkRegistry _blsApkRegistry,
        IIndexRegistry _indexRegistry
    ) RegistryCoordinator(_serviceManager, _stakeRegistry, _blsApkRegistry, _indexRegistry) {
        _transferOwnership(msg.sender);
    }

    function setQuorumCount(uint8 count) external {
        quorumCount = count;
    }

    function setOperatorId(address operator, bytes32 operatorId) external {
        _operatorInfo[operator].operatorId = operatorId;
    }

    function recordOperatorQuorumBitmapUpdate(bytes32 operatorId, uint192 quorumBitmap) external {
        uint256 operatorQuorumBitmapHistoryLength = _operatorBitmapHistory[operatorId].length;
        if (operatorQuorumBitmapHistoryLength != 0) {
            _operatorBitmapHistory[operatorId][operatorQuorumBitmapHistoryLength - 1].nextUpdateBlockNumber = uint32(block.number);
        }

        _operatorBitmapHistory[operatorId].push(QuorumBitmapUpdate({
            updateBlockNumber: uint32(block.number),
            nextUpdateBlockNumber: 0,
            quorumBitmap: quorumBitmap
        }));
    }
}
