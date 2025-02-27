// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IRewardsCoordinator} from
    "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";

import {ECDSAServiceManagerMock} from "../mocks/ECDSAServiceManagerMock.sol";
import {ECDSAStakeRegistryMock} from "../mocks/ECDSAStakeRegistryMock.sol";
import {AVSDirectoryMock} from "../mocks/AVSDirectoryMock.sol";
import {IECDSAStakeRegistryTypes} from "../../src/interfaces/IECDSAStakeRegistry.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IAVSDirectory, IAVSDirectoryTypes} from "../../src/unaudited/ECDSAStakeRegistry.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

contract MockPermissionController {
    function addPendingAdmin(address account, address admin) external  {}
    function removePendingAdmin(address account, address admin) external  {}
    function removeAdmin(address account, address admin) external  {}
    function setAppointee(address account, address appointee, address target, bytes4 selector) external  {}
    function removeAppointee(address account, address appointee, address target, bytes4 selector) external  {}
}

contract MockDelegationManager {
    function operatorShares(address, address) external pure returns (uint256) {
        return 1000; // Return a dummy value for simplicity
    }

    function getOperatorShares(
        address,
        IStrategy[] memory strategies
    ) external pure returns (uint256[] memory) {
        uint256[] memory response = new uint256[](strategies.length);
        for (uint256 i; i < strategies.length; i++) {
            response[i] = 1000;
        }
        return response; // Return a dummy value for simplicity
    }
}

contract MockAllocationManager {
    function setAVSRegistrar(address avs, address registrar) external {}
    
    function isOperatorSet(OperatorSet memory operatorSet) external pure returns (bool) {
        return true;
    }
    
    function getStrategiesInOperatorSet(OperatorSet memory operatorSet) external pure returns (IStrategy[] memory) {
        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = IStrategy(address(900));
        strategies[1] = IStrategy(address(901));
        return strategies;
    }
}

contract MockRewardsCoordinator {
    function createAVSRewardsSubmission(
        address avs,
        IRewardsCoordinator.RewardsSubmission[] calldata
    ) external pure {}

    function createOperatorDirectedAVSRewardsSubmission(
        address avs,
        IRewardsCoordinator.OperatorDirectedRewardsSubmission[] calldata
    ) external pure {}

    function setClaimerFor(
        address claimer
    ) external pure {}
}

contract MockAVSDirectory {
    // 使用 mapping 存储每个 operator 的状态
    mapping(address => mapping(address => IAVSDirectoryTypes.OperatorAVSRegistrationStatus)) 
        private operatorStatus;

    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory
    ) external {
        // 设置特定 operator 的状态为 REGISTERED
        operatorStatus[msg.sender][operator] = IAVSDirectoryTypes.OperatorAVSRegistrationStatus.REGISTERED;
    }

    function deregisterOperatorFromAVS(
        address operator
    ) external {
        // 设置特定 operator 的状态为 UNREGISTERED
        operatorStatus[msg.sender][operator] = IAVSDirectoryTypes.OperatorAVSRegistrationStatus.UNREGISTERED;
    }

    function updateAVSMetadataURI(
        string memory
    ) external pure {}

    function setAvsOperatorStatus(
        address avs, 
        address operator, 
        IAVSDirectoryTypes.OperatorAVSRegistrationStatus status
    ) external {
        operatorStatus[avs][operator] = status;
    }
    
    function avsOperatorStatus(
        address avs,
        address operator
    ) external view returns (IAVSDirectoryTypes.OperatorAVSRegistrationStatus) {
        return operatorStatus[avs][operator];
    }
}

contract ECDSAServiceManagerSetup is Test {
    MockDelegationManager public mockDelegationManager;
    AVSDirectoryMock public mockAVSDirectory;
    MockAllocationManager public mockAllocationManager;
    ECDSAStakeRegistryMock public mockStakeRegistry;
    MockRewardsCoordinator public mockRewardsCoordinator;
    ECDSAServiceManagerMock public serviceManager;
    MockPermissionController public mockPermissionController;
    address public mockAVSRegistrarAddr;
    address public owner = makeAddr("owner");
    address public rewardsInitiator = makeAddr("rewardsInitiator");
    address internal operator1;
    address internal operator2;
    uint256 internal operator1Pk;
    uint256 internal operator2Pk;

    function setUp() public {
        mockDelegationManager = new MockDelegationManager();
        mockAVSDirectory = new AVSDirectoryMock();
        mockAllocationManager = new MockAllocationManager();
        mockAVSRegistrarAddr = makeAddr("mockAVSRegistrar");
        mockStakeRegistry =
            new ECDSAStakeRegistryMock(
                IDelegationManager(address(mockDelegationManager)),
                IAllocationManager(address(mockAllocationManager)),
                mockAVSRegistrarAddr,
                IAVSDirectory(address(mockAVSDirectory))
            );
        mockRewardsCoordinator = new MockRewardsCoordinator();

        mockPermissionController = new MockPermissionController();

        serviceManager = new ECDSAServiceManagerMock(
            address(mockAVSDirectory),
            address(mockStakeRegistry),
            address(mockRewardsCoordinator),
            address(mockDelegationManager),
            address(mockAllocationManager),
            address(mockPermissionController),
            owner,
            rewardsInitiator
        );

        operator1Pk = 1;
        operator2Pk = 2;
        operator1 = vm.addr(operator1Pk);
        operator2 = vm.addr(operator2Pk);

        // Create a quorum
        IECDSAStakeRegistryTypes.Quorum memory quorum = IECDSAStakeRegistryTypes.Quorum({
            strategies: new IECDSAStakeRegistryTypes.StrategyParams[](2)
        });
        quorum.strategies[0] = IECDSAStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(420)),
            multiplier: 5000
        });
        quorum.strategies[1] = IECDSAStakeRegistryTypes.StrategyParams({
            strategy: IStrategy(address(421)),
            multiplier: 5000
        });
        address[] memory operators = new address[](0);

        vm.prank(owner);
        mockStakeRegistry.initialize(
            address(serviceManager),
            10000, // Assuming a threshold weight of 10000 basis points
            quorum
        );
        ISignatureUtils.SignatureWithSaltAndExpiry memory dummySignature;

        vm.prank(operator1);
        mockStakeRegistry.registerOperatorM2Quorum(dummySignature, operator1);

        vm.prank(operator2);
        mockStakeRegistry.registerOperatorM2Quorum(dummySignature, operator2);
    }

    function testRegisterOperatorToAVS() public {
        address operator = operator1;
        ISignatureUtils.SignatureWithSaltAndExpiry memory signature;

        vm.prank(address(mockStakeRegistry));
        serviceManager.registerOperatorToAVS(operator, signature);
    }

    function testDeregisterOperatorFromAVS() public {
        address operator = operator1;

        vm.prank(address(mockStakeRegistry));
        serviceManager.deregisterOperatorFromAVS(operator);
    }

    function testGetRestakeableStrategies() public {
        address[] memory strategies = serviceManager.getRestakeableStrategies();
    }

    function testGetOperatorRestakedStrategies() public {
        address operator = operator1;
        address[] memory strategies = serviceManager.getOperatorRestakedStrategies(operator);
    }

    function test_Regression_GetOperatorRestakedStrategies_NoShares() public {
        address operator = operator1;
        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = IStrategy(address(420));
        strategies[1] = IStrategy(address(421));

        uint96[] memory shares = new uint96[](2);
        shares[0] = 0;
        shares[1] = 1;

        vm.mockCall(
            address(mockDelegationManager),
            abi.encodeCall(IDelegationManager.getOperatorShares, (operator, strategies)),
            abi.encode(shares)
        );

        address[] memory restakedStrategies = serviceManager.getOperatorRestakedStrategies(operator);
        assertEq(restakedStrategies.length, 1, "Expected no restaked strategies");
    }

    function testUpdateAVSMetadataURI() public {
        string memory newURI = "https://new-metadata-uri.com";

        vm.prank(mockStakeRegistry.owner());
        serviceManager.updateAVSMetadataURI(newURI);
    }

    // function testCreateAVSRewardsSubmission() public {
    //     IRewardsCoordinator.RewardsSubmission[] memory submissions;

    //     vm.prank(serviceManager.rewardsInitiator());
    //     serviceManager.createAVSRewardsSubmission(submissions);
    // }

    function testSetRewardsInitiator() public {
        address newInitiator = address(0x123);

        vm.prank(mockStakeRegistry.owner());
        serviceManager.setRewardsInitiator(newInitiator);
    }

    function testCreateOperatorDirectedAVSRewardsSubmission() public {
        IRewardsCoordinator.OperatorDirectedRewardsSubmission[] memory submissions;

        vm.prank(serviceManager.rewardsInitiator());
        serviceManager.createOperatorDirectedAVSRewardsSubmission(submissions);
    }

    function testSetClaimerFor() public {
        address claimer = address(0x123);

        vm.prank(owner);
        serviceManager.setClaimerFor(claimer);
    }

    function testSetAVSRegistrar() public {
        address registrar = address(0x123);

        vm.prank(mockStakeRegistry.owner());
        serviceManager.setAVSRegistrar(IAVSRegistrar(registrar));
    }

    function testGetOperatorSetStrategies() public {
        uint32 operatorSetId = 1;
        
        address[] memory strategies = serviceManager.getOperatorSetStrategies(operatorSetId);
        
        assertEq(strategies.length, 2, "Should return 2 strategies");
        assertEq(strategies[0], address(900), "First strategy should match");
        assertEq(strategies[1], address(901), "Second strategy should match");
    }
    
    function testAddPendingAdmin() public {
        address admin = makeAddr("admin");
        
        vm.prank(owner);
        serviceManager.addPendingAdmin(admin);
    }
    
    function testRemovePendingAdmin() public {
        address pendingAdmin = makeAddr("pendingAdmin");
        
        vm.prank(owner);
        serviceManager.removePendingAdmin(pendingAdmin);
    }
    
    function testRemoveAdmin() public {
        address admin = makeAddr("admin");
        
        vm.prank(owner);
        serviceManager.removeAdmin(admin);
    }
    
    function testSetAppointee() public {
        address appointee = makeAddr("appointee");
        address target = makeAddr("target");
        bytes4 selector = bytes4(keccak256("someFunction()"));
        
        vm.prank(owner);
        serviceManager.setAppointee(appointee, target, selector);
    }
    
    function testRemoveAppointee() public {
        address appointee = makeAddr("appointee");
        address target = makeAddr("target");
        bytes4 selector = bytes4(keccak256("someFunction()"));
        
        vm.prank(owner);
        serviceManager.removeAppointee(appointee, target, selector);
    }
}
