// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {EmptyContract} from "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";
import {PauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import "src/BLSApkRegistry.sol";
import "src/BLSSignatureChecker.sol";
import "src/IndexRegistry.sol";
import "src/RegistryCoordinator.sol";
import "src/ServiceManagerBase.sol";
import "src/StakeRegistry.sol";

import "forge-std/Script.sol";
import "forge-std/Test.sol";

contract MiddlewareDeploy is Script, Test {
    EmptyContract public emptyContract;

    // Main Contracts
    BLSApkRegistry public blsApkRegistry;
    BLSSignatureChecker public signatureChecker;
    IndexRegistry public indexRegistry;
    RegistryCoordinator public registryCoordinator;
    ServiceManagerBase public serviceManager;
    StakeRegistry public stakeRegistry;

    // Implementation Contracts
    BLSApkRegistry public blsApkRegistryImpl;
    IndexRegistry public indexRegistryImpl;
    RegistryCoordinator public registryCoordinatorImpl;
    ServiceManagerBase public serviceManagerImpl;
    StakeRegistry public stakeRegistryImpl;

    // Util contracts
    PauserRegistry public pauserRegistry;

    // Util data structures
    IRegistryCoordinator.OperatorSetParam[] operatorSetParams;

    address godAddress = 0x0D4dfc2d8afAf30c919296E4610c890Dc90e83Fb;

    function run() external {
        // Store Deployed Addresses
        IDelegationManager delegationManager = IDelegationManager(0x45b4c4DAE69393f62e1d14C5fe375792DF4E6332);
        
        vm.startBroadcast();    

        // Deploy empty contract
        emptyContract = new EmptyContract();

        // Deploy pauserRegistry
        address[] memory pausers = new address[](1);
        pausers[0] = godAddress;
        pauserRegistry = new PauserRegistry(pausers, godAddress); // pausers, unpauser

        // Deploy ProxyAdmin
        ProxyAdmin proxyAdmin = new ProxyAdmin();

       /**
         * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
         * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
         */
        registryCoordinator = RegistryCoordinator(address(
            new TransparentUpgradeableProxy(
                address(emptyContract),
                address(proxyAdmin),
                ""
            )
        ));

        stakeRegistry = StakeRegistry(
            address(
                new TransparentUpgradeableProxy(
                    address(emptyContract),
                    address(proxyAdmin),
                    ""
                )
            )
        );

        indexRegistry = IndexRegistry(
            address(
                new TransparentUpgradeableProxy(
                    address(emptyContract),
                    address(proxyAdmin),
                    ""
                )
            )
        );

        blsApkRegistry = BLSApkRegistry(
            address(
                new TransparentUpgradeableProxy(
                    address(emptyContract),
                    address(proxyAdmin),
                    ""
                )
            )
        );

        serviceManager = ServiceManagerBase(
            address(
                new TransparentUpgradeableProxy(
                    address(emptyContract),
                    address(proxyAdmin),
                    ""
                )
            )
        );

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        registryCoordinatorImpl = new RegistryCoordinator(serviceManager, stakeRegistry, blsApkRegistry, indexRegistry);
        stakeRegistryImpl = new StakeRegistry(registryCoordinator, delegationManager);
        blsApkRegistryImpl = new BLSApkRegistry(registryCoordinator);
        indexRegistryImpl = new IndexRegistry(registryCoordinator);
        serviceManagerImpl = new ServiceManagerBase(delegationManager, registryCoordinator, stakeRegistry);

        // Third, upgrade the proxy contracts to point to the implementation contracts
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(stakeRegistry))),
            address(stakeRegistryImpl)
        );

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(blsApkRegistry))),
            address(blsApkRegistryImpl)
        );

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(indexRegistry))),
            address(indexRegistryImpl)
        );

        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(serviceManager))),
            address(serviceManagerImpl),
            abi.encodeWithSelector(
                ServiceManagerBase.initialize.selector,
                godAddress // owner
            )
        );

        // Set up registry coordinator params
        operatorSetParams.push(IRegistryCoordinator.OperatorSetParam({
            maxOperatorCount: 100,
            kickBIPsOfOperatorStake: 15000,
            kickBIPsOfTotalStake: 150
        }));

        uint96[] memory minimumStakeForQuorum = new uint96[](1);
        minimumStakeForQuorum[0] = 0;

        IStakeRegistry.StrategyParams[][] memory quorumStrategiesConsideredAndMultipliers =
            new IStakeRegistry.StrategyParams[][](1);
        quorumStrategiesConsideredAndMultipliers[0] = new IStakeRegistry.StrategyParams[](1);
        quorumStrategiesConsideredAndMultipliers[0][0] = IStakeRegistry.StrategyParams({
            strategy: IStrategy(0xd421b2a340497545dA68AE53089d99b9Fe0493cD),
            multiplier: 1e18
        });

        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(registryCoordinator))),
            address(registryCoordinatorImpl),
            abi.encodeWithSelector(
                RegistryCoordinator.initialize.selector,
                godAddress, // owner
                godAddress, // churn approver
                godAddress, // pauserRegistry
                pauserRegistry,
                0, // Initial paused status
                operatorSetParams,
                minimumStakeForQuorum,
                quorumStrategiesConsideredAndMultipliers
            )
        );

        vm.stopBroadcast();

        // Write JSON Data
        string memory deployed_addresses = "avsAddresses";
        vm.serializeAddress(deployed_addresses, "pauserRegistry", address(pauserRegistry));
        vm.serializeAddress(deployed_addresses, "proxyAdmin", address(proxyAdmin));
        vm.serializeAddress(deployed_addresses, "registryCoordinator", address(registryCoordinator));
        vm.serializeAddress(deployed_addresses, "stakeRegistry", address(stakeRegistry));
        vm.serializeAddress(deployed_addresses, "indexRegistry", address(indexRegistry));
        vm.serializeAddress(deployed_addresses, "blsApkRegistry", address(blsApkRegistry));
        vm.serializeAddress(deployed_addresses, "serviceManager", address(serviceManager));

        string memory finalJson = vm.serializeString(deployed_addresses, "object", deployed_addresses);
        vm.createDir("./script/output", true);
        vm.writeJson(finalJson, "./script/output/avsAddresses_1.json");
    }
}