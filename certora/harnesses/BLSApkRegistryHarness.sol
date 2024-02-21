// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "src/BLSApkRegistry.sol";

contract BLSApkRegistryHarness is BLSApkRegistry {
    constructor(
        IRegistryCoordinator _registryCoordinator
    ) BLSApkRegistry(_registryCoordinator) {}

    function getApkHistory(uint8 quorumNumber) public view returns (ApkUpdate[] memory) {
        return apkHistory[quorumNumber];
    }
}
