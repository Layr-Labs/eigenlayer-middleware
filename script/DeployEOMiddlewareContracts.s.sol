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
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

// Middleware contracts
import {
    EORegistryCoordinator,
    IEORegistryCoordinator,
    IEOBLSApkRegistry,
    IEOIndexRegistry,
    IEOStakeRegistry,
    IServiceManager
} from "../src/EORegistryCoordinator.sol";
import {EOBLSApkRegistry} from "../src/EOBLSApkRegistry.sol";
import {EOIndexRegistry} from "../src/EOIndexRegistry.sol";
import {EOStakeRegistry} from "../src/EOStakeRegistry.sol";
import {EOServiceManager} from "../src/EOServiceManager.sol";
import {OperatorStateRetriever} from "src/OperatorStateRetriever.sol";

// # To deploy and verify our contract
// forge script script/DeployEOMiddlewareContracts.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv
contract DeployEOMiddlewareContracts is Script, Utils {
    
    IStrategy constant STRATEGY_BASE_TVL_LIMITS = IStrategy(0x879944A8cB437a5f8061361f82A6d4EED59070b5);
    IStrategy[1] private deployedStrategyArray = [STRATEGY_BASE_TVL_LIMITS];

    // Middleware contracts to deploy
    EORegistryCoordinator public registryCoordinator;
    EOServiceManager serviceManager;
    EOBLSApkRegistry blsApkRegistry;
    EOStakeRegistry stakeRegistry;
    EOIndexRegistry indexRegistry;
    OperatorStateRetriever operatorStateRetriever;

    // ProxyAdmin
    ProxyAdmin proxyAdmin;

    // PauserRegistry
    PauserRegistry pauserRegistry;

    uint numQuorums = 1;
    uint numStrategies = deployedStrategyArray.length;

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
            EOServiceManager,
            EOStakeRegistry,
            EOBLSApkRegistry,
            EOIndexRegistry,
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
        EOStakeRegistry stakeRegistryImplementation =
            new EOStakeRegistry(IEORegistryCoordinator(registryCoordinator), delegationManager);
        EOBLSApkRegistry blsApkRegistryImplementation =
            new EOBLSApkRegistry(IEORegistryCoordinator(registryCoordinator));
        EOIndexRegistry indexRegistryImplementation =
            new EOIndexRegistry(IEORegistryCoordinator(registryCoordinator));
        EOServiceManager serviceManagerImplementation = new EOServiceManager(
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
        
        _initEORegistryCoordinator(proxyAdmin, registryCoordinator, registryCoordinatorImplementation, pauserRegistry);

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

    function _initEORegistryCoordinator(ProxyAdmin _proxyAdmin, IEORegistryCoordinator _registryCoordinator, EORegistryCoordinator _registryCoordinatorImplementation, PauserRegistry _pauserRegistry) internal{
        IEORegistryCoordinator.OperatorSetParam[]
            memory quorumsOperatorSetParams = new IEORegistryCoordinator.OperatorSetParam[](
                numQuorums
            );
        uint96[] memory quorumsMinimumStake = new uint96[](numQuorums);
        IEOStakeRegistry.StrategyParams[][]
        memory quorumsStrategyParams = new IEOStakeRegistry.StrategyParams[][](
            numQuorums
        );
        
        // for each quorum to setup, we need to define
        // QuorumOperatorSetParam, minimumStakeForQuorum, and strategyParams
        for (uint i = 0; i < numQuorums; i++) {
            // hard code these for now
            quorumsOperatorSetParams[i] = IEORegistryCoordinator
                .OperatorSetParam({
                    maxOperatorCount: 10000,
                    kickBIPsOfOperatorStake: 15000,
                    kickBIPsOfTotalStake: 100
                });
            quorumsStrategyParams[i] = new IEOStakeRegistry.StrategyParams[](
                numStrategies
            );
            for (uint j = 0; j < numStrategies; j++) {
                quorumsStrategyParams[i][j] = IEOStakeRegistry
                    .StrategyParams({
                        strategy: deployedStrategyArray[j],
                        // setting this to 1 ether since the divisor is also 1 ether
                        // therefore this allows an operator to register with even just 1 token
                        // see https://github.com/Layr-Labs/eigenlayer-middleware/blob/m2-mainnet/src/StakeRegistry.sol#L484
                        //    weight += uint96(sharesAmount * strategyAndMultiplier.multiplier / WEIGHTING_DIVISOR);
                        multiplier: 1 ether
                    });
            }
        }

        _proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(_registryCoordinator))),
            address(_registryCoordinatorImplementation),
            abi.encodeWithSelector(
                EORegistryCoordinator.initialize.selector,
                msg.sender, // _initialOwner
                msg.sender, // _churnApprover
                msg.sender, // _ejector
                _pauserRegistry,
                0, /*initialPausedStatus*/
                quorumsOperatorSetParams,
                quorumsMinimumStake,
                quorumsStrategyParams
            )
        );
    }
}
