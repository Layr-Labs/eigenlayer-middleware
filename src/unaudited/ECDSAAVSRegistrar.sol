// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IECDSAStakeRegistry} from "../interfaces/IECDSAStakeRegistry.sol";
import {IServiceManager} from "../interfaces/IServiceManager.sol";

contract AVSRegistrar is IAVSRegistrar, Ownable {
    IAllocationManager public allocationManager;
    IECDSAStakeRegistry public immutable stakeRegistry;
    address public immutable avs;

    error AVSRegistrar__OnlyAllocationManager();

    modifier onlyAllocationManager() {
        if (msg.sender != address(allocationManager)) {
            revert AVSRegistrar__OnlyAllocationManager();
        }
        _;
    }

    constructor(address _allocationManager, address _stakeRegistry, address _avs) Ownable() {
        allocationManager = IAllocationManager(_allocationManager);
        stakeRegistry = IECDSAStakeRegistry(_stakeRegistry);
        avs = _avs;
    }

    function registerOperator(
        address operator,
        address avs,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) external onlyAllocationManager {
        // Decode signing key
        (address signingKey) = abi.decode(data, (address));

        // Call stake registry to register operator
        // Weight check will be done in ECDSAStakeRegistry
        stakeRegistry.onOperatorSetRegistered(operator, signingKey);
    }

    function deregisterOperator(
        address operator,
        address avs,
        uint32[] calldata operatorSetIds
    ) external onlyAllocationManager {
        stakeRegistry.onOperatorSetDeregistered(operator);
    }

    function updateAllocationManager(
        address _allocationManager
    ) external onlyOwner {
        allocationManager = IAllocationManager(_allocationManager);
    }

    function supportsAVS(
        address avsAddr
    ) external view returns (bool) {
        return avs == avsAddr;
    }
}
