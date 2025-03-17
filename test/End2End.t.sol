// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Test, console2 as console} from "forge-std/Test.sol";
import {OperatorLib} from "./utils/OperatorLib.sol";
import {CoreDeployLib} from "./utils/CoreDeployLib.sol";
import {UpgradeableProxyLib} from "./unit/UpgradeableProxyLib.sol";
import {MiddlewareDeployLib} from "./utils/MiddlewareDeployLib.sol";
import {BN254} from "../src/libraries/BN254.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IAllocationManagerTypes} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IServiceManager} from "../src/interfaces/IServiceManager.sol";
import {IStakeRegistry, IStakeRegistryTypes} from "../src/interfaces/IStakeRegistry.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {RegistryCoordinator} from "../src/RegistryCoordinator.sol";
import {IRegistryCoordinator} from "../src/interfaces/IRegistryCoordinator.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {AllocationManager} from "eigenlayer-contracts/src/contracts/core/AllocationManager.sol";
import {PermissionController} from
    "eigenlayer-contracts/src/contracts/permissions/PermissionController.sol";
import {ServiceManagerMock} from "./mocks/ServiceManagerMock.sol";
import {
    ISlashingRegistryCoordinator,
    ISlashingRegistryCoordinatorTypes
} from "../src/interfaces/ISlashingRegistryCoordinator.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {IStrategyFactory} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract End2EndForkTest is Test {
    using OperatorLib for *;

    struct ConfigData {
        address admin;
        uint256 numQuorums;
        uint256[] operatorParams;
    }

    address internal proxyAdmin;

    function testCreateOperator() public {
        OperatorLib.Operator memory operator = OperatorLib.createOperator("operator-1");

        assertTrue(operator.key.addr != address(0), "VM wallet address should be non-zero");

        assertTrue(operator.signingKey.privateKey != 0, "BLS private key should be non-zero");

        assertTrue(
            operator.signingKey.publicKeyG1.X != 0 || operator.signingKey.publicKeyG1.X != 0,
            "BLS public key G1 X should be non-zero"
        );
        assertTrue(
            operator.signingKey.publicKeyG1.Y != 0 || operator.signingKey.publicKeyG1.Y != 0,
            "BLS public key G1 Y should be non-zero"
        );

        assertTrue(
            operator.signingKey.publicKeyG2.X[0] != 0 || operator.signingKey.publicKeyG2.X[1] != 0,
            "BLS public key G2 X should be non-zero"
        );
        assertTrue(
            operator.signingKey.publicKeyG2.Y[0] != 0 || operator.signingKey.publicKeyG2.Y[1] != 0,
            "BLS public key G2 Y should be non-zero"
        );
    }

    function testSignAndVerifyMessage() public {
        OperatorLib.Operator memory operator = OperatorLib.createOperator("operator-1");

        bytes32 messageHash = keccak256(abi.encodePacked("Test message"));
        BN254.G1Point memory signature = OperatorLib.signMessageWithOperator(operator, messageHash);
        BN254.G1Point memory messagePoint = BN254.hashToG1(messageHash);

        bool isValid = BN254.pairing(
            BN254.negate(signature),
            BN254.generatorG2(),
            messagePoint,
            operator.signingKey.publicKeyG2
        );
        assertTrue(isValid, "Signature should be valid");
    }

    function testEndToEndSetup_M2Migration() public {
        (
            OperatorLib.Operator[] memory operators,
            CoreDeployLib.DeploymentData memory coreDeployment,
            MiddlewareDeployLib.MiddlewareDeployData memory middlewareDeployment,
            ConfigData memory middlewareConfig
        ) = _setupInitialState();
        (address token, address strategy) = _deployTokenAndStrategy(coreDeployment.strategyFactory);

        _setupOperatorsAndTokens(operators, coreDeployment, token, strategy);

        _setupFirstQuorumAndOperatorSet(
            operators, middlewareConfig, coreDeployment, middlewareDeployment, strategy
        );

        _setupSecondQuorumAndOperatorSet(
            operators, middlewareConfig, coreDeployment, middlewareDeployment, strategy
        );

        _executeSlashing(operators, middlewareConfig, middlewareDeployment, strategy);
    }

    function _setupInitialState()
        internal
        returns (
            OperatorLib.Operator[] memory operators,
            CoreDeployLib.DeploymentData memory coreDeployment,
            MiddlewareDeployLib.MiddlewareDeployData memory middlewareDeployment,
            ConfigData memory middlewareConfig
        )
    {
        // Fork Holesky testnet
        string memory rpcUrl = vm.envString("HOLESKY_RPC_URL");
        vm.createSelectFork(rpcUrl);
        // Read core deployment data from json
        coreDeployment = CoreDeployLib.readCoreDeploymentJson("./script/config", 17000, "preprod");

        // // Create 5 operators using helper function
        operators = _createOperators(5, 100);

        // Setup middleware deployment data
        proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();
        middlewareConfig.admin = address(this);
        middlewareConfig.numQuorums = 1;
        middlewareConfig.operatorParams = new uint256[](3);
        middlewareConfig.operatorParams[0] = 10;
        middlewareConfig.operatorParams[1] = 100;
        middlewareConfig.operatorParams[2] = 100;

        middlewareDeployment = MiddlewareDeployLib.deployMiddlewareWithCore(
            proxyAdmin, middlewareConfig.admin, coreDeployment
        );

        vm.startPrank(middlewareDeployment.serviceManager);
        AllocationManager(coreDeployment.allocationManager).updateAVSMetadataURI(
            middlewareDeployment.serviceManager, "metadata"
        );
        AllocationManager(coreDeployment.allocationManager).setAVSRegistrar(
            middlewareDeployment.serviceManager,
            IAVSRegistrar(middlewareDeployment.registryCoordinator)
        );
        PermissionController(coreDeployment.permissionController).setAppointee(
            address(middlewareDeployment.serviceManager),
            address(middlewareDeployment.registryCoordinator),
            coreDeployment.allocationManager,
            AllocationManager.createOperatorSets.selector
        );
        vm.stopPrank();
    }

    function _deployTokenAndStrategy(
        address strategyFactory
    ) private returns (address token, address strategy) {
        ERC20Mock tokenContract = new ERC20Mock();
        token = address(tokenContract);
        strategy = address(IStrategyFactory(strategyFactory).deployNewStrategy(IERC20(token)));
    }

    function _createOperators(
        uint256 numOperators,
        uint256 startIndex
    ) internal returns (OperatorLib.Operator[] memory) {
        OperatorLib.Operator[] memory operators = new OperatorLib.Operator[](numOperators);
        for (uint256 i = 0; i < numOperators; i++) {
            operators[i] =
                OperatorLib.createOperator(string(abi.encodePacked("operator-", i + startIndex)));
        }
        return operators;
    }

    function _registerOperatorsAsEigenLayerOperators(
        OperatorLib.Operator[] memory operators,
        address delegationManager
    ) internal {
        for (uint256 i = 0; i < operators.length; i++) {
            vm.startPrank(operators[i].key.addr);
            OperatorLib.registerAsOperator(operators[i], delegationManager);
            vm.stopPrank();
        }
    }

    function _setupOperatorsAndTokens(
        OperatorLib.Operator[] memory operators,
        CoreDeployLib.DeploymentData memory coreDeployment,
        address token,
        address strategy
    ) internal {
        // Verify and register operators
        for (uint256 i = 0; i < 5; i++) {
            bool isRegistered = IDelegationManager(coreDeployment.delegationManager).isOperator(
                operators[i].key.addr
            );
            assertFalse(isRegistered, "Operator should not be registered");
        }

        _registerOperatorsAsEigenLayerOperators(operators, coreDeployment.delegationManager);

        for (uint256 i = 0; i < 5; i++) {
            bool isRegistered = IDelegationManager(coreDeployment.delegationManager).isOperator(
                operators[i].key.addr
            );
            assertTrue(isRegistered, "Operator should be registered");
        }

        // Setup tokens and verify balances
        uint256 mintAmount = 1000 * 1e18;
        for (uint256 i = 0; i < 5; i++) {
            OperatorLib.mintMockTokens(operators[i], token, mintAmount);
            uint256 balance = IERC20(token).balanceOf(operators[i].key.addr);
            assertEq(balance, mintAmount, "Operator should have correct token balance");
        }

        // Handle deposits
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(operators[i].key.addr);
            uint256 shares = OperatorLib.depositTokenIntoStrategy(
                operators[i], coreDeployment.strategyManager, strategy, token, mintAmount
            );
            assertTrue(shares > 0, "Should have received shares for deposit");
            vm.stopPrank();

            shares = IStrategy(strategy).shares(operators[i].key.addr);
            assertEq(shares, mintAmount, "Operator shares should equal deposit amount");
        }
    }

    function _setupFirstQuorumAndOperatorSet(
        OperatorLib.Operator[] memory operators,
        ConfigData memory middlewareConfig,
        CoreDeployLib.DeploymentData memory coreDeployment,
        MiddlewareDeployLib.MiddlewareDeployData memory middlewareDeployment,
        address strategy
    ) internal {
        vm.startPrank(middlewareConfig.admin);

        // Create first quorum
        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 100,
            kickBIPsOfTotalStake: 100
        });

        IStakeRegistry.StrategyParams[] memory strategyParams =
            new IStakeRegistry.StrategyParams[](1);
        strategyParams[0] =
            IStakeRegistryTypes.StrategyParams({strategy: IStrategy(strategy), multiplier: 1 ether});

        RegistryCoordinator(middlewareDeployment.registryCoordinator)
            .createTotalDelegatedStakeQuorum(operatorSetParams, 100, strategyParams);
        vm.stopPrank();

        // Register operators
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 0;

        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(operators[i].key.addr);
            OperatorLib.registerOperatorFromAVS_OpSet(
                operators[i],
                coreDeployment.allocationManager,
                middlewareDeployment.registryCoordinator,
                middlewareDeployment.serviceManager,
                operatorSetIds
            );
            vm.stopPrank();
        }

        vm.roll(block.number + 10);

        // // Update operators for quorum
        address[][] memory registeredOperators = _getAndSortOperators(operators);
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(uint8(0));

        vm.prank(middlewareConfig.admin);
        RegistryCoordinator(middlewareDeployment.registryCoordinator).updateOperatorsForQuorum(
            registeredOperators, quorumNumbers
        );
    }

    function _setupSecondQuorumAndOperatorSet(
        OperatorLib.Operator[] memory operators,
        ConfigData memory middlewareConfig,
        CoreDeployLib.DeploymentData memory coreDeployment,
        MiddlewareDeployLib.MiddlewareDeployData memory middlewareDeployment,
        address strategy
    ) internal {
        // Create second quorum
        vm.startPrank(middlewareConfig.admin);
        IStakeRegistry.StrategyParams[] memory strategyParams =
            new IStakeRegistry.StrategyParams[](1);
        strategyParams[0] =
            IStakeRegistryTypes.StrategyParams({strategy: IStrategy(strategy), multiplier: 1 ether});

        ISlashingRegistryCoordinatorTypes.OperatorSetParam memory operatorSetParams =
        ISlashingRegistryCoordinatorTypes.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 0,
            kickBIPsOfTotalStake: 0
        });

        RegistryCoordinator(middlewareDeployment.registryCoordinator).createSlashableStakeQuorum(
            operatorSetParams, 100, strategyParams, 10
        );
        vm.stopPrank();

        _setupOperatorAllocations(operators, coreDeployment, middlewareDeployment, strategy);

        // Register and update operators for second quorum
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 1;

        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(operators[i].key.addr);
            OperatorLib.registerOperatorFromAVS_OpSet(
                operators[i],
                coreDeployment.allocationManager,
                middlewareDeployment.registryCoordinator,
                middlewareDeployment.serviceManager,
                operatorSetIds
            );
            vm.stopPrank();
        }

        vm.roll(block.number + 10);

        address[][] memory registeredOperators = _getAndSortOperators(operators);
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(uint8(1));

        vm.prank(middlewareConfig.admin);
        RegistryCoordinator(middlewareDeployment.registryCoordinator).updateOperatorsForQuorum(
            registeredOperators, quorumNumbers
        );
    }

    function _setupOperatorAllocations(
        OperatorLib.Operator[] memory operators,
        CoreDeployLib.DeploymentData memory coreDeployment,
        MiddlewareDeployLib.MiddlewareDeployData memory middlewareDeployment,
        address strategy
    ) internal {
        uint32 minDelay = 1;
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(operators[i].key.addr);
            OperatorLib.setAllocationDelay(
                operators[i], address(coreDeployment.allocationManager), minDelay
            );
            vm.stopPrank();
        }

        vm.roll(block.number + 100);

        IStrategy[] memory allocStrategies = new IStrategy[](1);
        allocStrategies[0] = IStrategy(strategy);

        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = uint64(1 ether);

        OperatorSet memory operatorSet =
            OperatorSet({avs: address(middlewareDeployment.serviceManager), id: 1});

        IAllocationManagerTypes.AllocateParams[] memory allocParams =
            new IAllocationManagerTypes.AllocateParams[](1);
        allocParams[0] = IAllocationManagerTypes.AllocateParams({
            operatorSet: operatorSet,
            strategies: allocStrategies,
            newMagnitudes: magnitudes
        });

        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(operators[i].key.addr);
            OperatorLib.modifyOperatorAllocations(
                operators[i], address(coreDeployment.allocationManager), allocParams
            );
            vm.stopPrank();
        }

        vm.roll(block.number + 100);
    }

    function _executeSlashing(
        OperatorLib.Operator[] memory operators,
        ConfigData memory middlewareConfig,
        MiddlewareDeployLib.MiddlewareDeployData memory middlewareDeployment,
        address strategy
    ) internal {
        IAllocationManagerTypes.SlashingParams memory slashingParams = IAllocationManagerTypes
            .SlashingParams({
            operator: operators[0].key.addr,
            operatorSetId: 1,
            strategies: new IStrategy[](1),
            wadsToSlash: new uint256[](1),
            description: "Test slashing"
        });

        slashingParams.strategies[0] = IStrategy(strategy);
        slashingParams.wadsToSlash[0] = 0.5e18;

        ServiceManagerMock(middlewareDeployment.serviceManager).slashOperator(slashingParams);
    }

    function _getAndSortOperators(
        OperatorLib.Operator[] memory operators
    ) internal pure returns (address[][] memory) {
        address[][] memory registeredOperators = new address[][](1);
        registeredOperators[0] = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            registeredOperators[0][i] = operators[i].key.addr;
        }

        // Sort operator addresses
        for (uint256 i = 0; i < registeredOperators[0].length - 1; i++) {
            for (uint256 j = 0; j < registeredOperators[0].length - i - 1; j++) {
                if (registeredOperators[0][j] > registeredOperators[0][j + 1]) {
                    address temp = registeredOperators[0][j];
                    registeredOperators[0][j] = registeredOperators[0][j + 1];
                    registeredOperators[0][j + 1] = temp;
                }
            }
        }

        return registeredOperators;
    }
}
