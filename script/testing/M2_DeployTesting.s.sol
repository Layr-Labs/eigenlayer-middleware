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

//forge script script/testing/M2_DeployTesting.s.sol:Deployer_M2 --rpc-url $RPC_URL  --private-key $PRIVATE_KEY --broadcast -vvvv
//forge script script/testing/M2_DeployTesting.s.sol:Deployer_M2 --rpc-url http://127.0.0.1:8545  --private-key $PRIVATE_KEY --broadcast -vvvv
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
        (uint96[] memory minimumStakeForQuourm, IVoteWeigher.StrategyAndWeightingMultiplier[][] memory strategyAndWeightingMultipliers) = _parseStakeRegistryParams(config_data);
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
        // eigenDAServiceManager = EigenDAServiceManager(
        //     address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenDAProxyAdmin), ""))
        // );
        eigenDAServiceManager = new ServiceManagerMock(slasher);
        registryCoordinator = BLSRegistryCoordinatorWithIndices(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenDAProxyAdmin), ""))
        );
        indexRegistry = IndexRegistry(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenDAProxyAdmin), ""))
        );
        stakeRegistry = StakeRegistry(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenDAProxyAdmin), ""))
        );

        // deploy StakeRegistry
        stakeRegistryImplementation = new StakeRegistry(
            registryCoordinator,
            indexRegistry,
            strategyManagerMock,
            IServiceManager(address(eigenDAServiceManager))
        );

        // upgrade stake registry proxy to implementation and initialbize
        eigenDAProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(stakeRegistry))),
            address(stakeRegistryImplementation),
            abi.encodeWithSelector(
                StakeRegistry.initialize.selector,
                minimumStakeForQuourm,
                strategyAndWeightingMultipliers
            )
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
                operatorSetParams,
                eigenLayerPauserReg,
                0
            )
        );

        //deploy IndexRegistry
        indexRegistryImplementation = new IndexRegistry(
            registryCoordinator
        );

        // upgrade index registry proxy to implementation
        eigenDAProxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(indexRegistry))),
            address(indexRegistryImplementation)
        );

        // transfer ownership of proxy admin to upgrader
        eigenDAProxyAdmin.transferOwnership(eigenDAUpgrader);

        // end deployment
        vm.stopBroadcast();

        // sanity checks
        _verifyContractPointers(
            eigenDAServiceManager,
            registryCoordinator,
            // blsPubkeyRegistryMock,
            indexRegistry,
            stakeRegistry
        );

        _verifyContractPointers(
            eigenDAServiceManagerImplementation,
            registryCoordinatorImplementation,
            // blsPubkeyRegistryImplementation,
            indexRegistryImplementation,
            stakeRegistryImplementation
        );

        _verifyImplementations();
        _verifyInitalizations(churner, ejector, operatorSetParams, minimumStakeForQuourm, strategyAndWeightingMultipliers);

        //write output
        _writeOutput(churner, ejector);

        // test
        _testUpdateStakesAllOperators_200OperatorsValid();
    }

    function _parseStakeRegistryParams(string memory config_data) internal returns (uint96[] memory minimumStakeForQuourm, IVoteWeigher.StrategyAndWeightingMultiplier[][] memory strategyAndWeightingMultipliers) {
        bytes memory stakesConfigsRaw = stdJson.parseRaw(config_data, ".minimumStakes");
        minimumStakeForQuourm = abi.decode(stakesConfigsRaw, (uint96[]));
        
        bytes memory strategyConfigsRaw = stdJson.parseRaw(config_data, ".strategyWeights");
        strategyAndWeightingMultipliers = abi.decode(strategyConfigsRaw, (IVoteWeigher.StrategyAndWeightingMultiplier[][]));
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

        require(_stakeRegistry.registryCoordinator() == registryCoordinator, "stakeRegistry.registryCoordinator() != registryCoordinator");
        require(_stakeRegistry.strategyManager() == strategyManagerMock, "stakeRegistry.strategyManager() != strategyManager");
        require(address(_stakeRegistry.serviceManager()) == address(eigenDAServiceManager), "stakeRegistry.eigenDAServiceManager() != eigenDAServiceManager");
    }

    function _verifyImplementations() internal view {
        // require(eigenDAProxyAdmin.getProxyImplementation(
        //     TransparentUpgradeableProxy(payable(address(eigenDAServiceManager)))) == address(eigenDAServiceManagerImplementation),
        //     "eigenDAServiceManager: implementation set incorrectly");
        require(eigenDAProxyAdmin.getProxyImplementation(
            TransparentUpgradeableProxy(payable(address(registryCoordinator)))) == address(registryCoordinatorImplementation),
            "registryCoordinator: implementation set incorrectly");
        // require(eigenDAProxyAdmin.getProxyImplementation(
        //     TransparentUpgradeableProxy(payable(address(blsPubkeyRegistry)))) == address(blsPubkeyRegistryImplementation),
        //     "blsPubkeyRegistry: implementation set incorrectly");
        require(eigenDAProxyAdmin.getProxyImplementation(
            TransparentUpgradeableProxy(payable(address(indexRegistry)))) == address(indexRegistryImplementation),
            "indexRegistry: implementation set incorrectly");
        require(eigenDAProxyAdmin.getProxyImplementation(
            TransparentUpgradeableProxy(payable(address(stakeRegistry)))) == address(stakeRegistryImplementation),
            "stakeRegistry: implementation set incorrectly");
    }

    function _verifyInitalizations(
        address churner, 
        address ejector, 
        IBLSRegistryCoordinatorWithIndices.OperatorSetParam[] memory operatorSetParams,
        uint96[] memory minimumStakeForQuourm, 
        IVoteWeigher.StrategyAndWeightingMultiplier[][] memory strategyAndWeightingMultipliers
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

        for (uint256 i = 0; i < minimumStakeForQuourm.length; ++i) {
            require(stakeRegistry.minimumStakeForQuorum(i) == minimumStakeForQuourm[i], "stakeRegistry.minimumStakeForQuourm != minimumStakeForQuourm");
        }

        for (uint8 i = 0; i < strategyAndWeightingMultipliers.length; ++i) {
            for(uint8 j = 0; j < strategyAndWeightingMultipliers[i].length; ++j) {
                (IStrategy strategy, uint96 multiplier) = stakeRegistry.strategiesConsideredAndMultipliers(i, j);
                require(address(strategy) == address(strategyAndWeightingMultipliers[i][j].strategy), "stakeRegistry.strategyAndWeightingMultipliers != strategyAndWeightingMultipliers");
                require(multiplier == strategyAndWeightingMultipliers[i][j].multiplier, "stakeRegistry.strategyAndWeightingMultipliers != strategyAndWeightingMultipliers");
            }
        }

        require(operatorSetParams.length == strategyAndWeightingMultipliers.length && operatorSetParams.length == minimumStakeForQuourm.length, "operatorSetParams, strategyAndWeightingMultipliers, and minimumStakeForQuourm must be the same length");
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

    function _updateStakesAllOperatorsTest() internal {
        _testUpdateStakesAllOperators_200OperatorsValid();
    }

    /**
     * @notice Testing gas estimations for 10 quorums, quorum0 has 10 strategies and quorum1-9 have 1 strategy each
     * 200 operators all staked into quorum 0
     * 50 operators are also staked into each of the quorums 1-9
     */
    function _testUpdateStakesAllOperators_200OperatorsValid() internal {
        uint256 maxQuorumsToRegisterFor = 10;
        // Set 200 operator addresses
        // OperatorsPerQuorum input param
        address[][] memory updateOperators = new address[][](maxQuorumsToRegisterFor);
        updateOperators[0] = new address[](200);
        // Register operator with all quorums if first 50 operator, o/w just quorum 0
        for (uint256 i = 0; i < 200; ++i) {
            uint256 bitmap;
            bytes memory quorumNumbers;
            BN254.G1Point memory pubkey;
            pubkey.X = i + 1;
            pubkey.Y = i + 1;
            (address operator, /*privateKey*/) = deriveRememberKey(TEST_MNEMONIC, uint32(i));
            // Set operator stake to at least min stake

            vm.broadcast(operator);
            delegationMock.setOperatorShares(operator, IStrategy(address(1)), 100e18);
            // vm.broadcast(operator);
            // pubkeyCompendiumMock.setBLSPublicKey(operator, pubkey);
            if (i < 50) {
                bitmap = (1<<maxQuorumsToRegisterFor)-1;
                quorumNumbers = BitmapUtils.bitmapToBytesArray(bitmap);
            } else {
                bitmap = 1;
                quorumNumbers = BitmapUtils.bitmapToBytesArray(bitmap);
            }
            vm.broadcast(operator);
            registryCoordinator.registerOperatorWithCoordinator(quorumNumbers, pubkey, "");

            updateOperators[0][i] = operator;
        }

        address[] memory updateOperatorsRemainingQuorums = new address[](50);
        for (uint256 i = 0; i < 50; i++) {
            updateOperatorsRemainingQuorums[i] = updateOperators[0][i];
        }
        for (uint256 i = 1; i < 10; i++) {
            updateOperators[i] = updateOperatorsRemainingQuorums;
        }

        for (uint256 i = 0; i < 10; i++) {
            // Sort each array by operatorId
            updateOperators[i] = _sortArrayByOperatorIds(updateOperators[i]);
        }

        // UpdateStakesAllOperators()
        (address operator, /*privateKey*/) = deriveRememberKey(TEST_MNEMONIC, uint32(0));
        vm.broadcast(operator);
        stakeRegistry.updateStakesAllOperators(updateOperators);

        // // Register 200 operators for quorum0
        // updateOperators[0] = new address[](200);
        // indexRegistryMock.setTotalOperatorsForQuorum(0, 200);
        // for (uint256 i = 0; i < operators.length; ++i) {
        //     defaultOperator = operators[i];
        //     bytes32 operatorId = bytes32(i + 1);

        //     (uint256 quorumBitmap, uint96 stakeForQuorum) = _registerOperatorSpecificQuorum(defaultOperator, operatorId, /*quorumNumber*/ 0);
        //     require(quorumBitmap == 1, "quorumBitmap should be 1");
        //     registryCoordinator.setOperatorId(defaultOperator, operatorId);
        //     registryCoordinator.recordOperatorQuorumBitmapUpdate(operatorId, uint192(quorumBitmap));

        //     bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(quorumBitmap);
        //     _setOperatorQuorumWeight(uint8(quorumNumbers[0]), defaultOperator, stakeForQuorum + 1);
        //     updateOperators[0][i] = operators[i];
        // }
        // // For each of the quorums 1-9, register 50 operators
        // for (uint256 i = 0; i < 50; ++i) {
        //     defaultOperator = operators[i];
        //     bytes32 operatorId = bytes32(i + 1);
        //     // Register operator for each quorum 1-9
        //     uint256 newBitmap;
        //     for (uint256 j = 1; j < 10; j++) {
        //         // stakesForQuorum has 1 element for quorum j
        //         (uint256 quorumBitmap, uint96 stakeForQuorum) = _registerOperatorSpecificQuorum(defaultOperator, operatorId, /*quorumNumber*/ j);
        //         uint256 currentOperatorBitmap = registryCoordinator.getCurrentQuorumBitmapByOperatorId(operatorId);
        //         newBitmap = currentOperatorBitmap | quorumBitmap;
        //         registryCoordinator.recordOperatorQuorumBitmapUpdate(operatorId, uint192(newBitmap));
        //         _setOperatorQuorumWeight(uint8(j), defaultOperator, stakeForQuorum + 1);
        //     }
        //     require(newBitmap == (1<<maxQuorumsToRegisterFor)-1, "Should be registered all quorums");
        // }
        // // Mocking indexRegistry to set total number of operators per quorum
        // for (uint256 i = 1; i < maxQuorumsToRegisterFor; i++) {
        //     updateOperators[i] = new address[](50);
        //     indexRegistryMock.setTotalOperatorsForQuorum(i, 50);
        //     for (uint256 j = 0; j < 50; j++) {
        //         updateOperators[i][j] = operators[j];
        //     }
        // }

        // // Check operators' stakehistory length, should be 1 if they registered
        // for (uint256 i = 0; i < updateOperators.length; ++i) {
        //     uint8 quorumNumber = uint8(i);
        //     for (uint256 j = 0; j < updateOperators[i].length; ++j) {
        //         bytes32 operatorId = registryCoordinator.getOperatorId(updateOperators[i][j]);
        //         assertEq(stakeRegistry.getLengthOfOperatorIdStakeHistoryForQuorum(operatorId, quorumNumber), 1);    
        //     }
        // }
        // stakeRegistry.updateStakesAllOperators(updateOperators);
        // // Check operators' stakehistory length, should be 1 if they registered, 2 if they updated stakes again
        // for (uint256 i = 0; i < updateOperators.length; ++i) {
        //     uint8 quorumNumber = uint8(i);
        //     for (uint256 j = 0; j < updateOperators[i].length; ++j) {
        //         bytes32 operatorId = registryCoordinator.getOperatorId(updateOperators[i][j]);
        //         assertLe(stakeRegistry.getLengthOfOperatorIdStakeHistoryForQuorum(operatorId, quorumNumber), 2);    
        //     }
        // }
    }


    function _sortArrayByOperatorIds(address[] memory arr) internal view returns (address[] memory) {
        uint256 l = arr.length;
        for(uint i = 0; i < l; i++) {
            for(uint j = i+1; j < l ;j++) {
                bytes32 id_i = registryCoordinator.getOperatorId(arr[i]);
                bytes32 id_j = registryCoordinator.getOperatorId(arr[j]);
                if(id_i > id_j) {
                    address temp = arr[i];
                    arr[i] = arr[j];
                    arr[j] = temp;
                }
            }
        }
        return arr;
    }

    function _sortArray(bytes32[] memory arr) private pure returns (bytes32[] memory) {
        uint256 l = arr.length;
        for(uint i = 0; i < l; i++) {
            for(uint j = i+1; j < l ;j++) {
                if(arr[i] > arr[j]) {
                    bytes32 temp = arr[i];
                    arr[i] = arr[j];
                    arr[j] = temp;
                }
            }
        }
        return arr;
    }
}