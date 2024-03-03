// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";

// OpenZeppelin
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {DeployEOMiddlewareContracts} from "../../../script/DeployEOMiddlewareContracts.s.sol";

// Middleware contracts
import {EORegistryCoordinator, IEORegistryCoordinator, IBLSApkRegistry, IIndexRegistry, IStakeRegistry, IServiceManager} from "../../../src/EORegistryCoordinator.sol";
import {BLSApkRegistry} from "../../../src/BLSApkRegistry.sol";
import {IndexRegistry} from "../../../src/IndexRegistry.sol";
import {StakeRegistry} from "../../../src/StakeRegistry.sol";
//import {EOServiceManager} from "../src/EOServiceManager.sol";
// Remove mock when EOServiceManager is implemented
import {ServiceManagerMock} from "../../mocks/ServiceManagerMock.sol";
import {OperatorStateRetriever} from "../../../src/OperatorStateRetriever.sol";

contract DeployEOMiddlewareContractsTest is Test, Script {
    DeployEOMiddlewareContracts public deployEOMiddlewareContracts;

    EORegistryCoordinator public registryCoordinator;
    ServiceManagerMock public serviceManager;
    StakeRegistry public stakeRegistry;
    BLSApkRegistry public blsApkRegistry;
    IndexRegistry public indexRegistry;
    OperatorStateRetriever public operatorStateRetriever;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl('goerli'), 10619764);
        deployEOMiddlewareContracts = new DeployEOMiddlewareContracts();
    }

    function testDeployEOMiddlewareContracts() public {
        (registryCoordinator, serviceManager, stakeRegistry, blsApkRegistry, indexRegistry, operatorStateRetriever, proxyAdmin) = deployEOMiddlewareContracts.run();
        console.log("registryCoordinator: ", address(registryCoordinator));
        console.log("serviceManager: ", address(serviceManager));
        console.log("stakeRegistry: ", address(stakeRegistry));
        console.log("blsApkRegistry: ", address(blsApkRegistry));
        console.log("indexRegistry: ", address(indexRegistry));
        console.log("operatorStateRetriever: ", address(operatorStateRetriever));
        console.log("blocknumber: ", block.number);

        address owner = serviceManager.owner();
        console.log("serviceManager owner: ", owner);

        address admin = proxyAdmin.getProxyAdmin(TransparentUpgradeableProxy(payable(address(registryCoordinator))));
        console.log("registryCoordinator admin: ", admin);

        address proxyAdminOwner = proxyAdmin.owner();
        console.log("proxyAdmin owner: ", proxyAdminOwner);
        console.log("msg.sender: ", msg.sender);

    }
}