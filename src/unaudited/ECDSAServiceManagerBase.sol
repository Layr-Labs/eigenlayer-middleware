// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";

import {IServiceManager} from "../interfaces/IServiceManager.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";

abstract contract ECDSAServiceManager is IServiceManager, OwnableUpgradeable {
    address public immutable stakeRegistry;
    address public immutable avsDirectory;

    constructor(address _avsDirectory, address _stakeRegistry) {
        avsDirectory = _avsDirectory;
        stakeRegistry = _stakeRegistry;
        _disableInitializers();
    }

    function __ServiceManagerBase_init(address initialOwner) internal virtual onlyInitializing {
        _transferOwnership(initialOwner);
    }

    function updateAVSMetadataURI(string memory _metadataURI) public virtual onlyOwner {
        IAVSDirectory(avsDirectory).updateAVSMetadataURI(_metadataURI);
    }

    /// TODO: Need to add Auth
    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) public {
        IAVSDirectory(avsDirectory).registerOperatorToAVS(operator, operatorSignature);
    }

    /// TODO: Need to add Auth
    function deregisterOperatorFromAVS(address operator) public virtual {
        IAVSDirectory(avsDirectory).deregisterOperatorFromAVS(operator);
    }

    function getRestakeableStrategies() external view returns (address[] memory) {
    }

    function getOperatorRestakedStrategies(address operator) external view returns (address[] memory) {}

    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[50] private __GAP;
}
