// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";

import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IRewardsCoordinator} from
    "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";

import {ECDSAServiceManagerMock} from "../mocks/ECDSAServiceManagerMock.sol";
import {ECDSAStakeRegistryMock} from "../mocks/ECDSAStakeRegistryMock.sol";
import {IECDSAStakeRegistryTypes} from "../../src/interfaces/IECDSAStakeRegistry.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

contract MockAVSDirectory {
    function registerOperatorToAVS(
        address,
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory
    ) external pure {}

    function deregisterOperatorFromAVS(
        address
    ) external pure {}

    function updateAVSMetadataURI(
        string memory
    ) external pure {}
}

contract MockAllocationManager {
    function setAVSRegistrar(address avs, address registrar) external {}
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

contract ECDSAServiceManagerSetup is Test {
    MockDelegationManager public mockDelegationManager;
    MockAVSDirectory public mockAVSDirectory;
    MockAllocationManager public mockAllocationManager;
    ECDSAStakeRegistryMock public mockStakeRegistry;
    MockRewardsCoordinator public mockRewardsCoordinator;
    ECDSAServiceManagerMock public serviceManager;
    address internal operator1;
    address internal operator2;
    uint256 internal operator1Pk;
    uint256 internal operator2Pk;

    function setUp() public {
        mockDelegationManager = new MockDelegationManager();
        mockAVSDirectory = new MockAVSDirectory();
        mockAllocationManager = new MockAllocationManager();
        mockStakeRegistry =
            new ECDSAStakeRegistryMock(IDelegationManager(address(mockDelegationManager)));
        mockRewardsCoordinator = new MockRewardsCoordinator();

        serviceManager = new ECDSAServiceManagerMock(
            address(mockAVSDirectory),
            address(mockStakeRegistry),
            address(mockRewardsCoordinator),
            address(mockDelegationManager),
            address(mockAllocationManager)
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

        vm.prank(mockStakeRegistry.owner());
        mockStakeRegistry.initialize(
            address(serviceManager),
            10000, // Assuming a threshold weight of 10000 basis points
            quorum
        );
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory dummySignature;

        vm.prank(operator1);
        mockStakeRegistry.registerOperatorWithSignature(dummySignature, operator1);

        vm.prank(operator2);
        mockStakeRegistry.registerOperatorWithSignature(dummySignature, operator2);
    }

    function testRegisterOperatorToAVS() public {
        address operator = operator1;
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory signature;

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

        vm.prank(mockStakeRegistry.owner());
        serviceManager.setClaimerFor(claimer);
    }

    function testSetAVSRegistrar() public {
        address registrar = address(0x123);

        vm.prank(mockStakeRegistry.owner());
        serviceManager.setAVSRegistrar(IAVSRegistrar(registrar));
    }
}

contract ECDSAServiceManagerAccessControlTests is ECDSAServiceManagerSetup {
    function test_RevertWhen_NotOwner_UpdateAVSMetadataURI() public {
        address notOwner = address(0x456);
        string memory newURI = "https://new-metadata-uri.com";

        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        serviceManager.updateAVSMetadataURI(newURI);
    }

    function test_RevertWhen_NotStakeRegistry_RegisterOperatorToAVS() public {
        address notStakeRegistry = address(0x456);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory signature;

        vm.prank(notStakeRegistry);
        vm.expectRevert(abi.encodeWithSignature("OnlyStakeRegistry()"));
        serviceManager.registerOperatorToAVS(operator1, signature);
    }

    function test_RevertWhen_NotStakeRegistry_DeregisterOperatorFromAVS() public {
        address notStakeRegistry = address(0x456);

        vm.prank(notStakeRegistry);
        vm.expectRevert(abi.encodeWithSignature("OnlyStakeRegistry()"));
        serviceManager.deregisterOperatorFromAVS(operator1);
    }

    function test_RevertWhen_NotRewardsInitiator_CreateAVSRewardsSubmission() public {
        address notRewardsInitiator = address(0x456);
        IRewardsCoordinator.RewardsSubmission[] memory submissions;

        vm.prank(notRewardsInitiator);
        vm.expectRevert(abi.encodeWithSignature("OnlyRewardsInitiator()"));
        serviceManager.createAVSRewardsSubmission(submissions);
    }

    function test_RevertWhen_NotRewardsInitiator_CreateOperatorDirectedAVSRewardsSubmission()
        public
    {
        address notRewardsInitiator = address(0x456);
        IRewardsCoordinator.OperatorDirectedRewardsSubmission[] memory submissions;

        vm.prank(notRewardsInitiator);
        vm.expectRevert(abi.encodeWithSignature("OnlyRewardsInitiator()"));
        serviceManager.createOperatorDirectedAVSRewardsSubmission(submissions);
    }

    function test_RevertWhen_NotOwner_SetClaimerFor() public {
        address notOwner = address(0x456);
        address claimer = address(0x789);

        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        serviceManager.setClaimerFor(claimer);
    }

    function test_RevertWhen_NotOwner_SetRewardsInitiator() public {
        address notOwner = address(0x456);
        address newInitiator = address(0x789);

        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        serviceManager.setRewardsInitiator(newInitiator);
    }

    function test_RevertWhen_NotOwner_SetAVSRegistrar() public {
        address notOwner = address(0x456);
        address registrar = address(0x789);

        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        serviceManager.setAVSRegistrar(IAVSRegistrar(registrar));
    }
}

contract ECDSAServiceManagerEventsTests is ECDSAServiceManagerSetup {
    event RewardsInitiatorUpdated(address prevRewardsInitiator, address newRewardsInitiator);

    function test_SetRewardsInitiator_EmitsEvent() public {
        address currentInitiator = serviceManager.rewardsInitiator();
        address newInitiator = address(0x888);

        vm.expectEmit(true, true, false, true);
        emit RewardsInitiatorUpdated(currentInitiator, newInitiator);

        vm.prank(serviceManager.owner());
        serviceManager.setRewardsInitiator(newInitiator);

        assertEq(serviceManager.rewardsInitiator(), newInitiator, "Rewards initiator not updated");
    }
}

contract ECDSAServiceManagerIntegrationTests is ECDSAServiceManagerSetup {
    function test_GetRestakeableStrategies_AfterQuorumUpdate() public {
        // Update quorum with new strategies
        IStrategy newStrategy1 = IStrategy(address(0x1111));
        IStrategy newStrategy2 = IStrategy(address(0x2222));

        IECDSAStakeRegistryTypes.Quorum memory newQuorum = IECDSAStakeRegistryTypes.Quorum({
            strategies: new IECDSAStakeRegistryTypes.StrategyParams[](2)
        });
        newQuorum.strategies[0] =
            IECDSAStakeRegistryTypes.StrategyParams({strategy: newStrategy1, multiplier: 6000});
        newQuorum.strategies[1] =
            IECDSAStakeRegistryTypes.StrategyParams({strategy: newStrategy2, multiplier: 4000});

        address[] memory operators = new address[](0);
        vm.prank(mockStakeRegistry.owner());
        mockStakeRegistry.updateQuorumConfig(newQuorum, operators);

        // Check restakeable strategies
        address[] memory strategies = serviceManager.getRestakeableStrategies();
        assertEq(strategies.length, 2, "Should have 2 strategies");
        assertEq(strategies[0], address(newStrategy1), "First strategy mismatch");
        assertEq(strategies[1], address(newStrategy2), "Second strategy mismatch");
    }

    function test_GetOperatorRestakedStrategies_AllStrategiesWithShares() public {
        // Mock all strategies to have shares
        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = IStrategy(address(420));
        strategies[1] = IStrategy(address(421));

        uint256[] memory shares = new uint256[](2);
        shares[0] = 1000;
        shares[1] = 2000;

        vm.mockCall(
            address(mockDelegationManager),
            abi.encodeCall(IDelegationManager.getOperatorShares, (operator1, strategies)),
            abi.encode(shares)
        );

        address[] memory restakedStrategies =
            serviceManager.getOperatorRestakedStrategies(operator1);
        assertEq(restakedStrategies.length, 2, "Should have 2 restaked strategies");
        assertEq(restakedStrategies[0], address(strategies[0]), "First strategy mismatch");
        assertEq(restakedStrategies[1], address(strategies[1]), "Second strategy mismatch");
    }

    function test_GetOperatorRestakedStrategies_NoStrategiesWithShares() public {
        // Mock all strategies to have zero shares
        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = IStrategy(address(420));
        strategies[1] = IStrategy(address(421));

        uint256[] memory shares = new uint256[](2);
        shares[0] = 0;
        shares[1] = 0;

        vm.mockCall(
            address(mockDelegationManager),
            abi.encodeCall(IDelegationManager.getOperatorShares, (operator1, strategies)),
            abi.encode(shares)
        );

        address[] memory restakedStrategies =
            serviceManager.getOperatorRestakedStrategies(operator1);
        assertEq(restakedStrategies.length, 0, "Should have no restaked strategies");
    }

    function test_SetAVSRegistrar_CallsAllocationManager() public {
        address newRegistrar = address(0xABC);

        // Expect call to allocation manager
        vm.expectCall(
            address(mockAllocationManager),
            abi.encodeCall(
                MockAllocationManager.setAVSRegistrar, (address(serviceManager), newRegistrar)
            )
        );

        vm.prank(serviceManager.owner());
        serviceManager.setAVSRegistrar(IAVSRegistrar(newRegistrar));
    }

    function test_UpdateAVSMetadataURI_CallsAVSDirectory() public {
        string memory newURI = "https://new-metadata-uri.com";

        // Expect call to AVS directory
        vm.expectCall(
            address(mockAVSDirectory),
            abi.encodeCall(MockAVSDirectory.updateAVSMetadataURI, (newURI))
        );

        vm.prank(serviceManager.owner());
        serviceManager.updateAVSMetadataURI(newURI);
    }

    function test_RegisterOperatorToAVS_CallsAVSDirectory() public {
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory signature;

        // Expect call to AVS directory
        vm.expectCall(
            address(mockAVSDirectory),
            abi.encodeCall(MockAVSDirectory.registerOperatorToAVS, (operator1, signature))
        );

        vm.prank(address(mockStakeRegistry));
        serviceManager.registerOperatorToAVS(operator1, signature);
    }

    function test_DeregisterOperatorFromAVS_CallsAVSDirectory() public {
        // Expect call to AVS directory
        vm.expectCall(
            address(mockAVSDirectory),
            abi.encodeCall(MockAVSDirectory.deregisterOperatorFromAVS, (operator1))
        );

        vm.prank(address(mockStakeRegistry));
        serviceManager.deregisterOperatorFromAVS(operator1);
    }

    function test_SetClaimerFor_CallsRewardsCoordinator() public {
        address claimer = address(0x123);

        // Expect call to rewards coordinator
        vm.expectCall(
            address(mockRewardsCoordinator),
            abi.encodeCall(MockRewardsCoordinator.setClaimerFor, (claimer))
        );

        vm.prank(serviceManager.owner());
        serviceManager.setClaimerFor(claimer);
    }
}

contract ECDSAServiceManagerFuzzTests is ECDSAServiceManagerSetup {
    function testFuzz_SetRewardsInitiator(
        address newInitiator
    ) public {
        vm.assume(newInitiator != address(0));

        vm.prank(serviceManager.owner());
        serviceManager.setRewardsInitiator(newInitiator);

        assertEq(
            serviceManager.rewardsInitiator(), newInitiator, "Rewards initiator not set correctly"
        );
    }

    function testFuzz_UpdateAVSMetadataURI(
        string memory newURI
    ) public {
        vm.prank(serviceManager.owner());
        serviceManager.updateAVSMetadataURI(newURI);
        // Test passes if no revert
    }
}
