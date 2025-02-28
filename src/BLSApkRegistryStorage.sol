// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IBLSApkRegistry, IBLSApkRegistryTypes} from "./interfaces/IBLSApkRegistry.sol";
import {ISlashingRegistryCoordinator} from "./interfaces/ISlashingRegistryCoordinator.sol";

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

import {BN254} from "./libraries/BN254.sol";

abstract contract BLSApkRegistryStorage is Initializable, IBLSApkRegistry {
    /// @dev Returns the hash of the zero pubkey aka BN254.G1Point(0,0)
    bytes32 internal constant ZERO_PK_HASH =
        hex"ad3228b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5";

    /// @inheritdoc IBLSApkRegistry
    address public immutable registryCoordinator;

    /// INDIVIDUAL PUBLIC KEY STORAGE

    /// @inheritdoc IBLSApkRegistry
    mapping(address operator => bytes32 operatorId) public operatorToPubkeyHash;
    /// @inheritdoc IBLSApkRegistry
    mapping(bytes32 pubkeyHash => address operator) public pubkeyHashToOperator;
    /// @inheritdoc IBLSApkRegistry
    mapping(address operator => BN254.G1Point pubkeyG1) public operatorToPubkey;

    /// @inheritdoc IBLSApkRegistry
    mapping(uint8 quorumNumber => IBLSApkRegistryTypes.ApkUpdate[]) public apkHistory;
    /// @inheritdoc IBLSApkRegistry
    mapping(uint8 quorumNumber => BN254.G1Point) public currentApk;

    mapping(address operator => BN254.G2Point) internal operatorToPubkeyG2;

    constructor(
        ISlashingRegistryCoordinator _slashingRegistryCoordinator
    ) {
        registryCoordinator = address(_slashingRegistryCoordinator);
        // disable initializers so that the implementation contract cannot be initialized
        _disableInitializers();
    }

    uint256[44] private __GAP;
}
