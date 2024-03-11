// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";
import "eigenlayer-contracts/script/utils/ExistingDeploymentParser.sol";

import {Utils} from "../../utils/Utils.s.sol";

// OpenZeppelin
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// EigenLayer contracts
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/core/DelegationManager.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";
import {EmptyContract} from "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";
import {PauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

// Middleware contracts
import {
    EORegistryCoordinator,
    IEORegistryCoordinator,
    IEOBLSApkRegistry,
    IEOIndexRegistry,
    IEOStakeRegistry,
    IServiceManager
} from "../../../src/EORegistryCoordinator.sol";
import {EOBLSApkRegistry} from "../../../src/EOBLSApkRegistry.sol";
import {EOIndexRegistry} from "../../../src/EOIndexRegistry.sol";
import {EOStakeRegistry} from "../../../src/EOStakeRegistry.sol";
import {EOServiceManager} from "../../../src/EOServiceManager.sol";
import {OperatorStateRetriever} from "src/OperatorStateRetriever.sol";

// # To deploy and verify our contract
// forge script script/DeployEOMiddlewareContracts.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv
contract Goerli_DeployEOMiddlewareContracts is Utils, ExistingDeploymentParser {
    
    string public existingDeploymentInfoPath  = string(bytes("./script/deploy/goerli/config/eigenlayer_deployment_goerli.json"));
    string public deployConfigPath = string(bytes("./script/deploy/goerli/config/middleware_config.json"));
    string public outputPath = string.concat("script/deploy/goerli/output/eoracle_middleware_deployment_data.json");

    ProxyAdmin public proxyAdmin;
    PauserRegistry pauserRegistry;
    address public eoracleOwner;
    address public eoracleUpgrader;
    address public pauser;
    uint256 public initalPausedStatus;
    
    // Middleware contracts to deploy
    EORegistryCoordinator public registryCoordinator;
    EOServiceManager serviceManager;
    EOBLSApkRegistry blsApkRegistry;
    EOStakeRegistry stakeRegistry;
    EOIndexRegistry indexRegistry;
    OperatorStateRetriever operatorStateRetriever;

    EORegistryCoordinator registryCoordinatorImplementation;
    EOStakeRegistry stakeRegistryImplementation;
    EOBLSApkRegistry blsApkRegistryImplementation;
    EOIndexRegistry indexRegistryImplementation;
    EOServiceManager serviceManagerImplementation;

    uint256 numStrategies = deployedStrategyArray.length;

    function run()
        external
        returns (
            EORegistryCoordinator,
            EOServiceManager,
            EOStakeRegistry,
            EOBLSApkRegistry,
            EOIndexRegistry,
            OperatorStateRetriever,
            ProxyAdmin
        )
    {
        // get info on all the already-deployed contracts
        _parseDeployedContracts(existingDeploymentInfoPath);

        // READ JSON CONFIG DATA
        string memory config_data = vm.readFile(deployConfigPath);

        // check that the chainID matches the one in the config
        uint256 currentChainId = block.chainid;
        uint256 configChainId = stdJson.readUint(config_data, ".chainInfo.chainId");
        emit log_named_uint("You are deploying on ChainID", currentChainId);
        require(configChainId == currentChainId, "You are on the wrong chain for this config");

        // parse the addresses of permissioned roles
        eoracleOwner = stdJson.readAddress(config_data, ".permissions.owner");
        eoracleUpgrader = stdJson.readAddress(config_data, ".permissions.upgrader");
        pauser = stdJson.readAddress(config_data, ".permissions.pauser");
        initalPausedStatus = stdJson.readUint(config_data, ".permissions.initalPausedStatus");

        vm.startBroadcast();
        (
            registryCoordinator,
            serviceManager,
            stakeRegistry,
            blsApkRegistry,
            indexRegistry,
            operatorStateRetriever,
            proxyAdmin
        ) = _deployEOMiddlewareContracts(delegation, avsDirectory, config_data);

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
        IAVSDirectory _avsDirectory,
        string memory config_data
    )
        internal
        returns (
            EORegistryCoordinator,
            EOServiceManager,
            EOStakeRegistry,
            EOBLSApkRegistry,
            EOIndexRegistry,
            OperatorStateRetriever,
            ProxyAdmin
        )
    {

        // Deploy proxy admin for ability to upgrade proxy contracts
        proxyAdmin = new ProxyAdmin();

        if(pauser == address(0)) {
            // Deploy PauserRegistry with msg.sender as the initial pauser
            address[] memory pausers = new address[](1);
            pausers[0] = eoracleOwner;
            address unpauser = eoracleOwner;
            pauserRegistry = new PauserRegistry(pausers, unpauser);
        } else {
            pauserRegistry = PauserRegistry(pauser);
        }

        /**
         * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
         * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
         */
        registryCoordinator = EORegistryCoordinator(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        stakeRegistry = EOStakeRegistry(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        indexRegistry = EOIndexRegistry(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        blsApkRegistry = EOBLSApkRegistry(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        serviceManager = EOServiceManager(
            address(
                new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")
            )
        );

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        stakeRegistryImplementation =
            new EOStakeRegistry(IEORegistryCoordinator(registryCoordinator), delegationManager);
        blsApkRegistryImplementation =
            new EOBLSApkRegistry(IEORegistryCoordinator(registryCoordinator));
        indexRegistryImplementation =
            new EOIndexRegistry(IEORegistryCoordinator(registryCoordinator));
        serviceManagerImplementation = new EOServiceManager(
            IAVSDirectory(_avsDirectory), IEORegistryCoordinator(registryCoordinator), stakeRegistry
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

        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(serviceManager))),
            address(serviceManagerImplementation),
            abi.encodeWithSelector(
                EOServiceManager.initialize.selector,
                eoracleOwner // _initialOwner
            )
        );

        registryCoordinatorImplementation =
            new EORegistryCoordinator(serviceManager, stakeRegistry, blsApkRegistry, indexRegistry);
        
        _initEORegistryCoordinator(proxyAdmin, registryCoordinator, registryCoordinatorImplementation, pauserRegistry, config_data);

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

    function _initEORegistryCoordinator(ProxyAdmin _proxyAdmin, IEORegistryCoordinator _registryCoordinator, EORegistryCoordinator _registryCoordinatorImplementation, PauserRegistry _pauserRegistry, string memory config_data) internal{
        // parse initalization params and permissions from config data
        (
            uint96[] memory minimumStakeForQuourm, 
            IEOStakeRegistry.StrategyParams[][] memory strategyAndWeightingMultipliers
        ) = _parseStakeRegistryParams(config_data);
        (
            IEORegistryCoordinator.OperatorSetParam[] memory operatorSetParams, 
            address churner, 
            address ejector
        ) = _parseRegistryCoordinatorParams(config_data);

        _proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(_registryCoordinator))),
            address(_registryCoordinatorImplementation),
            abi.encodeWithSelector(
                EORegistryCoordinator.initialize.selector,
                eoracleOwner,
                churner,
                ejector,
                _pauserRegistry,
                initalPausedStatus,
                operatorSetParams,
                minimumStakeForQuourm,
                strategyAndWeightingMultipliers
            )
        );
    }

    function _parseStakeRegistryParams(string memory config_data) internal pure returns (uint96[] memory minimumStakeForQuourm, IEOStakeRegistry.StrategyParams[][] memory strategyAndWeightingMultipliers) {
        bytes memory stakesConfigsRaw = stdJson.parseRaw(config_data, ".minimumStakes");
        minimumStakeForQuourm = abi.decode(stakesConfigsRaw, (uint96[]));
        
        bytes memory strategyConfigsRaw = stdJson.parseRaw(config_data, ".strategyWeights");
        strategyAndWeightingMultipliers = abi.decode(strategyConfigsRaw, (IEOStakeRegistry.StrategyParams[][]));
    }

    function _parseRegistryCoordinatorParams(string memory config_data) internal pure returns (IEORegistryCoordinator.OperatorSetParam[] memory operatorSetParams, address churner, address ejector) {
        bytes memory operatorConfigsRaw = stdJson.parseRaw(config_data, ".operatorSetParams");
        operatorSetParams = abi.decode(operatorConfigsRaw, (IEORegistryCoordinator.OperatorSetParam[]));

        churner = stdJson.readAddress(config_data, ".permissions.churner");
        ejector = stdJson.readAddress(config_data, ".permissions.ejector");
    }
}
