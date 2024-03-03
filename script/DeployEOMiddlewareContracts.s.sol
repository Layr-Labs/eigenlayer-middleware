// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";

import {Utils} from "./utils/Utils.s.sol";

// OpenZeppelin
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// EigenLayer contracts
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/core/DelegationManager.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";
import {EmptyContract} from "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";
import {PauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";

// Middleware contracts
import {
    EORegistryCoordinator,
    IEORegistryCoordinator,
    IBLSApkRegistry,
    IIndexRegistry,
    IStakeRegistry,
    IServiceManager
} from "../src/EORegistryCoordinator.sol";
import {BLSApkRegistry} from "../src/BLSApkRegistry.sol";
import {IndexRegistry} from "../src/IndexRegistry.sol";
import {StakeRegistry} from "../src/StakeRegistry.sol";
//import {EOServiceManager} from "../src/EOServiceManager.sol";
// Remove mock when EOServiceManager is implemented
import {ServiceManagerMock} from "../test/mocks/ServiceManagerMock.sol";
import {OperatorStateRetriever} from "src/OperatorStateRetriever.sol";

// # To deploy and verify our contract
// forge script script/DeployEOMiddlewareContracts.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv
contract DeployEOMiddlewareContracts is Script, Utils {
    // Middleware contracts to deploy
    EORegistryCoordinator public registryCoordinator;
    ServiceManagerMock serviceManager;
    BLSApkRegistry blsApkRegistry;
    StakeRegistry stakeRegistry;
    IndexRegistry indexRegistry;
    OperatorStateRetriever operatorStateRetriever;

    // ProxyAdmin
    ProxyAdmin proxyAdmin;

    // PauserRegistry
    PauserRegistry pauserRegistry;

    function run()
        external
        returns (
            EORegistryCoordinator,
            ServiceManagerMock,
            StakeRegistry,
            BLSApkRegistry,
            IndexRegistry,
            OperatorStateRetriever,
            ProxyAdmin
        )
    {
        // get eigenlayer deployment data
        string memory eigenlayerDeployedContracts;
        if(block.chainid == 5){ // Goerli
            eigenlayerDeployedContracts = readOutput(
                "eigenlayer_deployment_output"
            );
        } else {
            revert("Unsupported chain ID");
        }

        IDelegationManager delegationManager = IDelegationManager(
            stdJson.readAddress(eigenlayerDeployedContracts, ".addresses.delegation")
        );

        IAVSDirectory avsDirectory = IAVSDirectory(
            stdJson.readAddress(eigenlayerDeployedContracts, ".addresses.avsDirectory")
        );

        vm.startBroadcast();
        (
            registryCoordinator,
            serviceManager,
            stakeRegistry,
            blsApkRegistry,
            indexRegistry,
            operatorStateRetriever,
            proxyAdmin
        ) = _deployEOMiddlewareContracts(delegationManager, avsDirectory);

        vm.stopBroadcast();

        // WRITE JSON DATA
        string memory deployed_addresses = "addresses";
        vm.serializeAddress(deployed_addresses, "EORegistryCoordinator", address(registryCoordinator));
        vm.serializeAddress(deployed_addresses, "EOServiceManager", address(serviceManager));
        vm.serializeAddress(deployed_addresses, "EOStakeRegistry", address(stakeRegistry));
        vm.serializeAddress(deployed_addresses, "EOBLSApkRegistry", address(blsApkRegistry));
        vm.serializeAddress(deployed_addresses, "EOIndexRegistry", address(indexRegistry));
        vm.serializeAddress(deployed_addresses, "operatorStateRetriever", address(operatorStateRetriever));
        vm.serializeAddress(deployed_addresses, "proxyAdmin", address(proxyAdmin));
        string memory finalJson = vm.serializeAddress(deployed_addresses, "deployer", msg.sender);
        vm.writeJson(finalJson, outputFileName());

        return (
            registryCoordinator,
            serviceManager,
            stakeRegistry,
            blsApkRegistry,
            indexRegistry,
            operatorStateRetriever,
            proxyAdmin
        );
    }

    /**
     * @notice Deploy eoracle middleware contracts
     */
    function _deployEOMiddlewareContracts(
        IDelegationManager delegationManager,
        IAVSDirectory avsDirectory
    )
        internal
        returns (
            EORegistryCoordinator,
            ServiceManagerMock,
            StakeRegistry,
            BLSApkRegistry,
            IndexRegistry,
            OperatorStateRetriever,
            ProxyAdmin
        )
    {
        // Deploy empty contract to be used as the initial implementation for the proxy contracts
        EmptyContract emptyContract = new EmptyContract();

        // Deploy proxy admin for ability to upgrade proxy contracts
        proxyAdmin = new ProxyAdmin();

        // Deploy PauserRegistry
        address[] memory pausers = new address[](1);
        pausers[0] = msg.sender;
        address unpauser = msg.sender;
        pauserRegistry = new PauserRegistry(pausers, unpauser);

        /**
         * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
         * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
         */
        registryCoordinator = EORegistryCoordinator(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        stakeRegistry = StakeRegistry(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        indexRegistry = IndexRegistry(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        blsApkRegistry = BLSApkRegistry(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        serviceManager = ServiceManagerMock(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        StakeRegistry stakeRegistryImplementation =
            new StakeRegistry(IEORegistryCoordinator(registryCoordinator), delegationManager);
        BLSApkRegistry blsApkRegistryImplementation =
            new BLSApkRegistry(IEORegistryCoordinator(registryCoordinator));
        IndexRegistry indexRegistryImplementation =
            new IndexRegistry(IEORegistryCoordinator(registryCoordinator));
        ServiceManagerMock serviceManagerImplementation = new ServiceManagerMock(
            IAVSDirectory(avsDirectory), IEORegistryCoordinator(registryCoordinator), stakeRegistry
        );

        // Third, upgrade the proxy contracts to point to the implementations
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(stakeRegistry))),
            address(stakeRegistryImplementation)
        );

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(blsApkRegistry))),
            address(blsApkRegistryImplementation)
        );

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(indexRegistry))),
            address(indexRegistryImplementation)
        );

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(serviceManager))),
            address(serviceManagerImplementation)
        );

        serviceManager.initialize({initialOwner: msg.sender});

        EORegistryCoordinator registryCoordinatorImplementation =
            new EORegistryCoordinator(serviceManager, stakeRegistry, blsApkRegistry, indexRegistry);

        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(registryCoordinator))),
            address(registryCoordinatorImplementation),
            abi.encodeWithSelector(
                EORegistryCoordinator.initialize.selector,
                msg.sender,
                msg.sender,
                msg.sender,
                pauserRegistry,
                0, /*initialPausedStatus*/
                new IEORegistryCoordinator.OperatorSetParam[](0),
                new uint96[](0),
                new IStakeRegistry.StrategyParams[][](0)
            )
        );

        operatorStateRetriever = new OperatorStateRetriever();

        return (
            registryCoordinator,
            serviceManager,
            stakeRegistry,
            blsApkRegistry,
            indexRegistry,
            operatorStateRetriever,
            proxyAdmin
        );
    }

    function outputFileName() internal view returns (string memory) {
        return string.concat(
            vm.projectRoot(),
            "/script/output/",
            vm.toString(block.chainid),
            "/eoracle_middleware_contracts_deployment_data.json"
        );
    }
}
