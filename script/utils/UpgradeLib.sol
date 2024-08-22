// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
// Deploy L2AVS proxy

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

library OperatorSetUpgradeLib {
    using stdJson for string;
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    bytes32 internal constant ADMIN_SLOT =
     0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;


    function upgrade(address proxy, address implementation, bytes memory data) internal {
        ProxyAdmin admin = ProxyAdmin(getAdmin(proxy));
        admin.upgradeAndCall(TransparentUpgradeableProxy(payable(proxy)), implementation, data);
    }

    function upgrade(address proxy, address implementation) internal {
        ProxyAdmin admin = ProxyAdmin(getAdmin(proxy));
        admin.upgrade(TransparentUpgradeableProxy(payable(proxy)), implementation);
    }

    function getAdmin(address proxy) internal view returns (address){
        bytes32 value = vm.load(proxy, ADMIN_SLOT);
        return address(uint160(uint256(value)));
    }

    function getImplementation(address proxy) internal view returns (address) {
        bytes32 value = vm.load(proxy, IMPLEMENTATION_SLOT);
        return address(uint160(uint256(value)));
    }
}