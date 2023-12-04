// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "eigenlayer-contracts/script/utils/ExistingDeploymentParser.sol";

import "src/BLSPublicKeyCompendium.sol";
import "src/BLSRegistryCoordinatorWithIndices.sol";
import "src/BLSPubkeyRegistry.sol";
import "src/IndexRegistry.sol";
import "src/StakeRegistry.sol";
import "src/BLSOperatorStateRetriever.sol";

import "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {ServiceManagerMock} from "test/mocks/ServiceManagerMock.sol";
import {BLSPublicKeyCompendiumMock} from "test/mocks/BLSPublicKeyCompendiumMock.sol";
import {BLSPubkeyRegistryMock} from "test/mocks/BLSPubkeyRegistryMock.sol";
import {DelegationManagerMock} from "eigenlayer-contracts/src/test/mocks/DelegationManagerMock.sol";
import {StrategyManagerMock} from "eigenlayer-contracts/src/test/mocks/StrategyManagerMock.sol";

//forge script script/test/M2_DeployTesting.s.sol:Deployer_M2 --rpc-url $RPC_URL  --private-key $PRIVATE_KEY --broadcast -vvvv
//forge script script/test/M2_DeployTesting.s.sol:Deployer_M2 --rpc-url http://127.0.0.1:8545  --private-key $PRIVATE_KEY --broadcast -vvvv
contract Deployer_M2 is ExistingDeploymentParser {
    string internal constant TEST_MNEMONIC = "test test test test test test test test test test test junk";


    string public existingDeploymentInfoPath  = string(bytes("./script/configs/M1_deployment_goerli_2023_3_23.json"));
    string public deployConfigPath = string(bytes("./script/configs/M2_deploy.config.json"));
    string public outputPath = "./script/configs/M2_deployment_data.json";

    //permissioned addresses
    ProxyAdmin public eigenDAProxyAdmin;
    address public eigenDAOwner;
    address public eigenDAUpgrader;

    //non-upgradeable contracts
    BLSOperatorStateRetriever public blsOperatorStateRetriever;

    // mocks
    BLSPubkeyRegistryMock public blsPubkeyRegistryMock;
    BLSPublicKeyCompendiumMock public pubkeyCompendiumMock;
    DelegationManagerMock public delegationMock;
    StrategyManagerMock public strategyManagerMock;
    
    //upgradeable contracts
    IServiceManager public eigenDAServiceManager;
    BLSRegistryCoordinatorWithIndices public registryCoordinator;
    IndexRegistry public indexRegistry;
    StakeRegistry public stakeRegistry;

    //upgradeable contract implementations
    IServiceManager public eigenDAServiceManagerImplementation;
    BLSRegistryCoordinatorWithIndices public registryCoordinatorImplementation;
    IndexRegistry public indexRegistryImplementation;
    StakeRegistry public stakeRegistryImplementation;


    function run() external {
        // get info on all the already-deployed contracts
        _parseDeployedContracts(existingDeploymentInfoPath);

        // READ JSON CONFIG DATA
        string memory config_data = vm.readFile(deployConfigPath);

        // check that the chainID matches the one in the config
        uint256 currentChainId = block.chainid;
        uint256 configChainId = stdJson.readUint(config_data, ".chainInfo.chainId");
        emit log_named_uint("You are deploying on ChainID", currentChainId);
        require(configChainId == currentChainId, "You are on the wrong chain for this config");

        // parse initalization params and permissions from config data
        (uint96[] memory minimumStakes, IStakeRegistry.StrategyParams[][] memory strategyParams) = _parseStakeRegistryParams(config_data);
        (IBLSRegistryCoordinatorWithIndices.OperatorSetParam[] memory operatorSetParams, address churner, address ejector) = _parseRegistryCoordinatorParams(config_data);

        eigenDAOwner = stdJson.readAddress(config_data, ".permissions.owner");
        eigenDAUpgrader = stdJson.readAddress(config_data, ".permissions.upgrader");

        // begin deployment
        vm.startBroadcast();

        // deploy proxy admin for ability to upgrade proxy contracts
        eigenDAProxyAdmin = new ProxyAdmin();

        //deploy non-upgradeable contracts
        pubkeyCompendiumMock = new BLSPublicKeyCompendiumMock();
        blsOperatorStateRetriever = new BLSOperatorStateRetriever();
        delegationMock = new DelegationManagerMock();
        strategyManagerMock = new StrategyManagerMock();
        strategyManagerMock.setAddresses(
            delegationMock,
            eigenPodManager,
            slasher
        );

        // deploy mocks
        blsPubkeyRegistryMock = new BLSPubkeyRegistryMock(registryCoordinator, pubkeyCompendiumMock);
        pubkeyCompendiumMock = new BLSPublicKeyCompendiumMock();

        //Deploy upgradeable proxy contracts that point to empty contract implementations
        eigenDAServiceManager = new ServiceManagerMock(slasher);
        registryCoordinator = BLSRegistryCoordinatorWithIndices(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenDAProxyAdmin), ""))
        );
        indexRegistry = IndexRegistry(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenDAProxyAdmin), ""))
        );
        // stakeRegistry = StakeRegistry(
        //     address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenDAProxyAdmin), ""))
        // );

        // deploy StakeRegistry
        stakeRegistry = new StakeRegistry(
            registryCoordinator,
            delegationMock,
            IServiceManager(address(eigenDAServiceManager))
        );

        // // upgrade stake registry proxy to implementation and initialbize
        // eigenDAProxyAdmin.upgradeAndCall(
        //     TransparentUpgradeableProxy(payable(address(stakeRegistry))),
        //     address(stakeRegistryImplementation),
        //     abi.encodeWithSelector(
        //         StakeRegistry.initialize.selector,
        //         minimumStakes,
        //         strategyParams
        //     )
        // );

        //deploy IndexRegistry
        indexRegistryImplementation = new IndexRegistry(
            registryCoordinator
        );

        // upgrade index registry proxy to implementation
        eigenDAProxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(indexRegistry))),
            address(indexRegistryImplementation)
        );

        // deploy RegistryCoordinator
        registryCoordinatorImplementation = new BLSRegistryCoordinatorWithIndices(
            slasher,
            IServiceManager(address(eigenDAServiceManager)),
            stakeRegistry,
            blsPubkeyRegistryMock,
            indexRegistry
        );

        // upgrade registry coordinator proxy to implementation and initialize
        eigenDAProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(registryCoordinator))),
            address(registryCoordinatorImplementation),
            abi.encodeWithSelector(
                BLSRegistryCoordinatorWithIndices.initialize.selector,
                churner,
                ejector,
                eigenLayerPauserReg,
                0, /* initialPausedStatus */
                operatorSetParams,
                minimumStakes,
                strategyParams
            )
        );

        // transfer ownership of proxy admin to upgrader
        eigenDAProxyAdmin.transferOwnership(eigenDAUpgrader);

        // end deployment
        vm.stopBroadcast();

        // sanity checks
        _verifyContractPointers(
            eigenDAServiceManager,
            registryCoordinator,
            indexRegistry,
            stakeRegistry
        );

        _verifyContractPointers(
            eigenDAServiceManagerImplementation,
            registryCoordinatorImplementation,
            indexRegistryImplementation,
            stakeRegistryImplementation
        );

        _verifyImplementations();
        _verifyInitalizations(churner, ejector, operatorSetParams, minimumStakes, strategyParams);

        //write output
        _writeOutput(churner, ejector);

        // testing for gas estimations
        // 10 quorums, 50 operators per quorum for quorums1-9
        _testUpdateOperatorsForQuorums(10, 60, false);
        // 10 quorums, 50 operators per quorum for quorums1-9 w/ all operators being below minimum stake
        // _testUpdateOperatorsForQuorums(10, 50, true);

        // 10 quorums, 30 operators per quorum for quorums1-9
        // _testUpdateOperatorsForQuorums(10, 30, false);
        // 10 quorums, 30 operators per quorum for quorums1-9 w/ all operators being below minimum stake
        // _testUpdateOperatorsForQuorums(10, 30, true);
    }

    function _parseStakeRegistryParams(string memory config_data) internal returns (uint96[] memory minimumStakes, IStakeRegistry.StrategyParams[][] memory strategyParams) {
        bytes memory stakesConfigsRaw = stdJson.parseRaw(config_data, ".minimumStakes");
        minimumStakes = abi.decode(stakesConfigsRaw, (uint96[]));
        
        bytes memory strategyConfigsRaw = stdJson.parseRaw(config_data, ".strategyWeights");
        strategyParams = abi.decode(strategyConfigsRaw, (IStakeRegistry.StrategyParams[][]));
    }

    function _parseRegistryCoordinatorParams(string memory config_data) internal returns (IBLSRegistryCoordinatorWithIndices.OperatorSetParam[] memory operatorSetParams, address churner, address ejector) {
        bytes memory operatorConfigsRaw = stdJson.parseRaw(config_data, ".operatorSetParams");
        operatorSetParams = abi.decode(operatorConfigsRaw, (IBLSRegistryCoordinatorWithIndices.OperatorSetParam[]));

        churner = stdJson.readAddress(config_data, ".permissions.churner");
        ejector = stdJson.readAddress(config_data, ".permissions.ejector");
    }

    function _verifyContractPointers(
        IServiceManager _eigenDAServiceManager,
        BLSRegistryCoordinatorWithIndices _registryCoordinator,
        IndexRegistry _indexRegistry,
        StakeRegistry _stakeRegistry
    ) internal view {
        require(_registryCoordinator.slasher() == slasher, "registryCoordinator.slasher() != slasher");
        require(address(_registryCoordinator.serviceManager()) == address(eigenDAServiceManager), "registryCoordinator.eigenDAServiceManager() != eigenDAServiceManager");
        require(_registryCoordinator.stakeRegistry() == stakeRegistry, "registryCoordinator.stakeRegistry() != stakeRegistry");
        require(_registryCoordinator.blsPubkeyRegistry() == blsPubkeyRegistryMock, "registryCoordinator.blsPubkeyRegistry() != blsPubkeyRegistry");
        require(_registryCoordinator.indexRegistry() == indexRegistry, "registryCoordinator.indexRegistry() != indexRegistry");
        require(_indexRegistry.registryCoordinator() == registryCoordinator, "indexRegistry.registryCoordinator() != registryCoordinator");
    }

    function _verifyImplementations() internal view {
        require(eigenDAProxyAdmin.getProxyImplementation(
            TransparentUpgradeableProxy(payable(address(registryCoordinator)))) == address(registryCoordinatorImplementation),
            "registryCoordinator: implementation set incorrectly");
        require(eigenDAProxyAdmin.getProxyImplementation(
            TransparentUpgradeableProxy(payable(address(indexRegistry)))) == address(indexRegistryImplementation),
            "indexRegistry: implementation set incorrectly");
    }

    function _verifyInitalizations(
        address churner, 
        address ejector, 
        IBLSRegistryCoordinatorWithIndices.OperatorSetParam[] memory operatorSetParams,
        uint96[] memory minimumStakes, 
        IStakeRegistry.StrategyParams[][] memory strategyParams
    ) internal view {
        // require(eigenDAServiceManager.owner() == eigenDAOwner, "eigenDAServiceManager.owner() != eigenDAOwner");
        // require(eigenDAServiceManager.pauserRegistry() == eigenLayerPauserReg, "eigenDAServiceManager: pauser registry not set correctly");
        // require(strategyManager.paused() == 0, "eigenDAServiceManager: init paused status set incorrectly");

        require(registryCoordinator.churnApprover() == churner, "registryCoordinator.churner() != churner");
        require(registryCoordinator.ejector() == ejector, "registryCoordinator.ejector() != ejector");
        require(registryCoordinator.pauserRegistry() == eigenLayerPauserReg, "registryCoordinator: pauser registry not set correctly");
        require(registryCoordinator.paused() == 0, "registryCoordinator: init paused status set incorrectly");
        
        for (uint8 i = 0; i < operatorSetParams.length; ++i) {
            require(keccak256(abi.encode(registryCoordinator.getOperatorSetParams(i))) == keccak256(abi.encode(operatorSetParams[i])), "registryCoordinator.operatorSetParams != operatorSetParams");
        }

        for (uint256 i = 0; i < minimumStakes.length; ++i) {
            require(stakeRegistry.minimumStakeForQuorum(i) == minimumStakes[i], "stakeRegistry.minimumStakes != minimumStakes");
        }

        for (uint8 i = 0; i < strategyParams.length; ++i) {
            for(uint8 j = 0; j < strategyParams[i].length; ++j) {
                (IStrategy strategy, uint96 multiplier) = stakeRegistry.strategyParams(i, j);
                require(address(strategy) == address(strategyParams[i][j].strategy), "stakeRegistry.strategyParams != strategyParams");
                require(multiplier == strategyParams[i][j].multiplier, "stakeRegistry.strategyParams != strategyParams");
            }
        }

        require(operatorSetParams.length == strategyParams.length && operatorSetParams.length == minimumStakes.length, "operatorSetParams, strategyParams, and minimumStakes must be the same length");
    }

    function _writeOutput(address churner, address ejector) internal {
        string memory parent_object = "parent object";

        string memory deployed_addresses = "addresses";
        vm.serializeAddress(deployed_addresses, "eigenDAProxyAdmin", address(eigenDAProxyAdmin));
        vm.serializeAddress(deployed_addresses, "blsPubKeyCompendium", address(pubkeyCompendiumMock));
        vm.serializeAddress(deployed_addresses, "blsOperatorStateRetriever", address(blsOperatorStateRetriever));
        vm.serializeAddress(deployed_addresses, "eigenDAServiceManager", address(eigenDAServiceManager));
        // vm.serializeAddress(deployed_addresses, "eigenDAServiceManagerImplementation", address(eigenDAServiceManagerImplementation));
        vm.serializeAddress(deployed_addresses, "registryCoordinator", address(registryCoordinator));
        vm.serializeAddress(deployed_addresses, "registryCoordinatorImplementation", address(registryCoordinatorImplementation));
        vm.serializeAddress(deployed_addresses, "indexRegistry", address(indexRegistry));
        vm.serializeAddress(deployed_addresses, "indexRegistryImplementation", address(indexRegistryImplementation));
        vm.serializeAddress(deployed_addresses, "stakeRegistry", address(stakeRegistry));
        string memory deployed_addresses_output = vm.serializeAddress(deployed_addresses, "stakeRegistryImplementation", address(stakeRegistryImplementation));

        string memory chain_info = "chainInfo";
        vm.serializeUint(chain_info, "deploymentBlock", block.number);
        string memory chain_info_output = vm.serializeUint(chain_info, "chainId", block.chainid);

        string memory permissions = "permissions";
        vm.serializeAddress(permissions, "eigenDAOwner", eigenDAOwner);
        vm.serializeAddress(permissions, "eigenDAUpgrader", eigenDAUpgrader);
        vm.serializeAddress(permissions, "eigenDAChurner", churner);
        string memory permissions_output = vm.serializeAddress(permissions, "eigenDAEjector", ejector);
        
        vm.serializeString(parent_object, chain_info, chain_info_output);
        vm.serializeString(parent_object, deployed_addresses, deployed_addresses_output);
        string memory finalJson = vm.serializeString(parent_object, permissions, permissions_output);
        vm.writeJson(finalJson, outputPath);
    } 

    /**
     * @notice calls updateOperatorsForQuorums for quorum 0 in one tx and then for remaining quorums in second tx 
     * Creates `maxQuorumsToRegisterFor` number of quorums with quorum0 having 200 operators and remaining quorums
     * having `operatorCap` number of operators
     */
    function _testUpdateOperatorsForQuorums(
        uint256 maxQuorumsToRegisterFor,
        uint256 operatorCap,
        bool belowMinStake
    ) internal {
        require(maxQuorumsToRegisterFor > 1, "maxQuorumsToRegisterFor must be greater than 1");
        // Set 200 operator addresses
        address[] memory updateOperatorsQuorum0 = new address[](200);

        // The operators that will be registered for quorums 1-9 as well as quorum0
        address[] memory updateOperatorsRemainingQuorums = new address[](operatorCap);

        // Register operator with all quorums if one of the first `operatorCap` operators, o/w just quorum 0
        for (uint256 i = 0; i < 200; ++i) {
            uint256 bitmap;
            bytes memory quorumNumbers;
            
            (address operator, /*privateKey*/) = deriveRememberKey(TEST_MNEMONIC, uint32(i));
            // Set operator stake to at least min stake
            vm.broadcast(operator);
            delegationMock.setOperatorShares(operator, IStrategy(address(1)), 100e18);
            if (i < operatorCap) {
                updateOperatorsRemainingQuorums[i] = operator;
                bitmap = (1<<maxQuorumsToRegisterFor)-1;
                quorumNumbers = BitmapUtils.bitmapToBytesArray(bitmap);
            } else {
                bitmap = 1;
                quorumNumbers = BitmapUtils.bitmapToBytesArray(bitmap);
            }
            vm.broadcast(operator);
            registryCoordinator.registerOperator(quorumNumbers, "");

            updateOperatorsQuorum0[i] = operator;
        }
        // Sort operators array inputs per function requirement
        updateOperatorsQuorum0 = _sortArray(updateOperatorsQuorum0);
        updateOperatorsRemainingQuorums = _sortArray(updateOperatorsRemainingQuorums);
        // Ensure total quorum counts and operators per quorum Count
        require(registryCoordinator.quorumCount() == maxQuorumsToRegisterFor);
        require(indexRegistry.totalOperatorsForQuorum(0) == 200);
        for (uint8 i = 1; i < maxQuorumsToRegisterFor; i++) {
            require(indexRegistry.totalOperatorsForQuorum(i) == operatorCap);
        }

        // Set operator stakes to below min stake if belowMinStake is true to test deregistering of operators
        if (belowMinStake) {
            for (uint256 i = 0; i < 200; ++i) {
                require(
                    registryCoordinator.getCurrentQuorumBitmap(bytes32(abi.encode(updateOperatorsQuorum0[i]))) > 0,
                    "Operator should be registered for at least 1 quorum"
                );
                delegationMock.setOperatorShares(updateOperatorsQuorum0[i], IStrategy(address(1)), 0);
            }
        }

        // Update operators for just Quorum 0
        (address callingOperator, /*privateKey*/) = deriveRememberKey(TEST_MNEMONIC, uint32(0));
        bytes memory quorum0 = BitmapUtils.bitmapToBytesArray(1);
        address[][] memory operatorsForQuorum0 = new address[][](1);
        operatorsForQuorum0[0] = updateOperatorsQuorum0;
        vm.broadcast(callingOperator);
        registryCoordinator.updateOperatorsForQuorum(operatorsForQuorum0, quorum0);
        // Update operators for Quorums 1-9
        uint256 allQuorumBitmap = (1 << maxQuorumsToRegisterFor) - 1;
        bytes memory quorums = BitmapUtils.bitmapToBytesArray(allQuorumBitmap - 1);
        address[][] memory operatorsForQuorums = new address[][](maxQuorumsToRegisterFor - 1);
        for (uint256 i = 0; i < maxQuorumsToRegisterFor - 1; i++) {
            operatorsForQuorums[i] = updateOperatorsRemainingQuorums;
        }
        vm.broadcast(callingOperator);
        registryCoordinator.updateOperatorsForQuorum(operatorsForQuorums, quorums);

        // if belowMinStake is true, check bitmaps have been updated correctly
        if (belowMinStake) {
            for (uint256 i = 0; i < 200; ++i) {
                require(
                    registryCoordinator.getCurrentQuorumBitmap(bytes32(abi.encode(updateOperatorsQuorum0[i]))) == 0,
                    "Operator should be deregistered"
                );
            }
        }
    }

    function _sortArray(address[] memory arr) internal pure returns (address[] memory) {
        uint256 l = arr.length;
        for(uint i = 0; i < l; i++) {
            for(uint j = i+1; j < l ;j++) {
                if(arr[i] > arr[j]) {
                    address temp = arr[i];
                    arr[i] = arr[j];
                    arr[j] = temp;
                }
            }
        }
        return arr;
    }
}