// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "src/interfaces/IBLSPubkeyRegistry.sol";
import "src/interfaces/IRegistryCoordinator.sol";
import "src/interfaces/IBLSPublicKeyCompendium.sol";

import "src/libraries/BN254.sol";

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

abstract contract BLSPubkeyRegistryStorage is Initializable, IBLSPubkeyRegistry {
    /// @notice the registry coordinator contract
    IRegistryCoordinator public immutable registryCoordinator;
    /// @notice the BLSPublicKeyCompendium contract against which pubkey ownership is checked
    IBLSPublicKeyCompendium public immutable pubkeyCompendium;

    /// @notice maps quorumNumber => historical aggregate pubkey updates
    mapping(uint8 => ApkUpdate[]) public apkHistory;
    /// @notice maps quorumNumber => current aggregate pubkey of quorum
    mapping(uint8 => BN254.G1Point) public currentApk;

    constructor(IRegistryCoordinator _registryCoordinator, IBLSPublicKeyCompendium _pubkeyCompendium) {
        registryCoordinator = _registryCoordinator;
        pubkeyCompendium = _pubkeyCompendium;
        // disable initializers so that the implementation contract cannot be initialized
        _disableInitializers();
    }

    // storage gap for upgradeability
    uint256[48] private __GAP;
}
