// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {UpgradeableProxyUtils} from "./UpgradeableProxyUtils.sol";
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {Greeter, GreeterV2, NoInitializer, WithConstructor, GreeterProxiable, GreeterV2Proxiable} from "./ProxyTestContracts.sol";

contract UpgradeableProxyUtilsTest is Test {
    ProxyAdmin internal admin;

    function setUp() public {
        admin = new ProxyAdmin();
    }

    function testTransparent() public {
        address proxy = UpgradeableProxyUtils.deployTransparentProxy(
            "Greeter.sol",
            address(admin),
            abi.encodeCall(Greeter.initialize, ("hello"))
        );
        Greeter instance = Greeter(proxy);
        address implAddressV1 = UpgradeableProxyUtils.getImplementationAddress(proxy);
        address adminAddress = UpgradeableProxyUtils.getAdminAddress(proxy);

        assertFalse(adminAddress == address(0));
        assertEq(instance.greeting(), "hello");

        UpgradeableProxyUtils.upgradeProxy(proxy, "GreeterV2.sol", abi.encodeCall(GreeterV2.resetGreeting, ()));

        address implAddressV2 = UpgradeableProxyUtils.getImplementationAddress(proxy);

        assertEq(UpgradeableProxyUtils.getAdminAddress(proxy), adminAddress);
        assertEq(instance.greeting(), "resetted");
        assertFalse(implAddressV2 == implAddressV1);
    }

    function testBeacon() public {
        address beacon = UpgradeableProxyUtils.deployBeacon("Greeter.sol", address(admin), abi.encode());
        address implAddressV1 = IBeacon(beacon).implementation();

        address proxy = UpgradeableProxyUtils.deployBeaconProxy(beacon, abi.encodeCall(Greeter.initialize, ("hello")));
        Greeter instance = Greeter(proxy);

        assertEq(UpgradeableProxyUtils.getBeaconAddress(proxy), beacon);
        assertEq(instance.greeting(), "hello");

        UpgradeableProxyUtils.upgradeBeacon(beacon, "GreeterV2.sol");
        address implAddressV2 = IBeacon(beacon).implementation();

        GreeterV2(address(instance)).resetGreeting();

        assertEq(instance.greeting(), "resetted");
        assertFalse(implAddressV2 == implAddressV1);
    }

    function testUpgradeBeaconWithoutCaller() public {
        address beacon = UpgradeableProxyUtils.deployBeacon("Greeter.sol", address(admin), abi.encode());
        UpgradeableProxyUtils.upgradeBeacon(beacon, "GreeterV2.sol", abi.encode());
    }

    function testWithConstructor() public {
        bytes memory constructorData = abi.encode(123);
        address proxy = UpgradeableProxyUtils.deployTransparentProxy(
            "WithConstructor.sol",
            msg.sender,
            abi.encodeCall(WithConstructor.initialize, (456)),
            constructorData
        );

        assertEq(WithConstructor(proxy).a(), 123);
        assertEq(WithConstructor(proxy).b(), 456);
    }

    function testNoInitializer() public {
        /// Can access getCode by File:Contract
        bytes memory constructorData = abi.encode(123);
        address proxy = UpgradeableProxyUtils.deployTransparentProxy("NoInitializer.sol", msg.sender, "", constructorData);

        assertEq(WithConstructor(proxy).a(), 123);
    }

}
