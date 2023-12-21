// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "../src/RegistryCoordinator.sol";
import "../src/ServiceManagerBase.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "forge-std/Script.sol";
import "forge-std/Test.sol";

contract Upgrade_Reg_SM is Script, Test {
    RegistryCoordinator public newRegCoordinator;
    ServiceManagerBase public newServiceManager;
    ProxyAdmin public proxyAdmin;

    function run() external {
        vm.startBroadcast();

        // Deploy New RegistryCoordinator
        newRegCoordinator = new RegistryCoordinator(
            IServiceManager(0x787f666893F3EB6bF5D7A6AA9297784671A3312D),
            IStakeRegistry(0x2e1145ea892EDebe0a6337208774dd70E8F05b04),
            IBLSApkRegistry(0x442664e4b59A8264457981d2Fee459f20a6FBeC4),
            IIndexRegistry(0xf88f3927264bb5fcCf900440DF6493963afce6F4)
        );

        // Deploy New ServiceManager
        newServiceManager = new ServiceManagerBase(
            IDelegationManager(0x45b4c4DAE69393f62e1d14C5fe375792DF4E6332),
            IRegistryCoordinator(0x31462912a0ABFB59cA03fFd6f10c416A8Bb7FD45),
            IStakeRegistry(0x2e1145ea892EDebe0a6337208774dd70E8F05b04)
        );

        // Upgrade Proxy Contract
        proxyAdmin = ProxyAdmin(payable(0x4893704E387Ab56A73B456e833879EBA8cd82718));
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(0x31462912a0ABFB59cA03fFd6f10c416A8Bb7FD45)),
            address(newRegCoordinator)
        );
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(0x787f666893F3EB6bF5D7A6AA9297784671A3312D)),
            address(newServiceManager)
        );

        vm.stopBroadcast();
    }
}