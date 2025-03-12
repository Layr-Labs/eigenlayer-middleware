// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
// Deploy L2AVS proxy

import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

library OperatorSetUpgradeLib {
    using stdJson for string;

    // address(uint160(uint256(keccak256("hevm cheat code")))) == 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    // solhint-disable-next-line const-name-snakecase
    Vm private constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1.
     */
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1.
     */
    bytes32 internal constant ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function upgrade(address proxy, address implementation, bytes memory data) internal {
        ProxyAdmin admin = ProxyAdmin(getAdmin(proxy));
        admin.upgradeAndCall(ITransparentUpgradeableProxy(payable(proxy)), implementation, data);
    }

    function upgrade(address proxy, address implementation) internal {
        ProxyAdmin admin = ProxyAdmin(getAdmin(proxy));
        admin.upgrade(ITransparentUpgradeableProxy(payable(proxy)), implementation);
    }

    function getAdmin(
        address proxy
    ) internal view returns (address) {
        bytes32 value = vm.load(proxy, ADMIN_SLOT);
        return address(uint160(uint256(value)));
    }

    function getImplementation(
        address proxy
    ) internal view returns (address) {
        bytes32 value = vm.load(proxy, IMPLEMENTATION_SLOT);
        return address(uint160(uint256(value)));
    }
}
