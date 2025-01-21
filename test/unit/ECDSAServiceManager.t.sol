// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {ECDSAServiceManagerMock} from "../mocks/ECDSAServiceManagerMock.sol";
import {ECDSAStakeRegistryMock} from "../mocks/ECDSAStakeRegistryMock.sol";
import {Quorum, StrategyParams} from "../../src/interfaces/IECDSAStakeRegistryEventsAndErrors.sol";

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
        ISignatureUtils.SignatureWithSaltAndExpiry memory
    ) external pure {}

    function deregisterOperatorFromAVS(address) external pure {}

    function updateAVSMetadataURI(string memory) external pure {}
}

contract MockRewardsCoordinator {
    function createAVSRewardsSubmission(
        IRewardsCoordinator.RewardsSubmission[] calldata
    ) external pure {}
}

contract ECDSAServiceManagerSetup is Test {
    MockDelegationManager public mockDelegationManager;
    MockAVSDirectory public mockAVSDirectory;
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
        mockStakeRegistry = new ECDSAStakeRegistryMock(
            IDelegationManager(address(mockDelegationManager))
        );
        mockRewardsCoordinator = new MockRewardsCoordinator();

        serviceManager = new ECDSAServiceManagerMock(
            address(mockAVSDirectory),
            address(mockStakeRegistry),
            address(mockRewardsCoordinator),
            address(mockDelegationManager)
        );

        operator1Pk = 1;
        operator2Pk = 2;
        operator1 = vm.addr(operator1Pk);
        operator2 = vm.addr(operator2Pk);

        // Create a quorum
        Quorum memory quorum = Quorum({strategies: new StrategyParams[](2)});
        quorum.strategies[0] = StrategyParams({
            strategy: IStrategy(address(420)),
            multiplier: 5000
        });
        quorum.strategies[1] = StrategyParams({
            strategy: IStrategy(address(421)),
            multiplier: 5000
        });
        address[] memory operators = new address[](0);

        vm.prank(mockStakeRegistry.owner());
        mockStakeRegistry.initialize(
            address(serviceManager),
            10_000, // Assuming a threshold weight of 10000 basis points
            quorum
        );
        ISignatureUtils.SignatureWithSaltAndExpiry memory dummySignature;

        vm.prank(operator1);
        mockStakeRegistry.registerOperatorWithSignature(
            dummySignature,
            operator1
        );

        vm.prank(operator2);
        mockStakeRegistry.registerOperatorWithSignature(
            dummySignature,
            operator2
        );
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
        address[] memory strategies = serviceManager
            .getOperatorRestakedStrategies(operator);
    }

    function test_Regression_GetOperatorRestakedStrategies_NoShares() public {
        address operator = operator1;
        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = IStrategy(address(420));
        strategies[1] = IStrategy(address(421));

        uint256[] memory shares = new uint256[](2);
        shares[0] = 0;
        shares[1] = 1;

        vm.mockCall(
            address(mockDelegationManager),
            abi.encodeCall(
                IDelegationManager.getOperatorShares,
                (operator, strategies)
            ),
            abi.encode(shares)
        );

        address[] memory restakedStrategies = serviceManager
            .getOperatorRestakedStrategies(operator);
        assertEq(
            restakedStrategies.length,
            1,
            "Expected no restaked strategies"
        );
    }

    function testUpdateAVSMetadataURI() public {
        string memory newURI = "https://new-metadata-uri.com";

        vm.prank(mockStakeRegistry.owner());
        serviceManager.updateAVSMetadataURI(newURI);
    }

    function testCreateAVSRewardsSubmission() public {
        IRewardsCoordinator.RewardsSubmission[] memory submissions;

        vm.prank(serviceManager.rewardsInitiator());
        serviceManager.createAVSRewardsSubmission(submissions);
    }

    function testSetRewardsInitiator() public {
        address newInitiator = address(0x123);

        vm.prank(mockStakeRegistry.owner());
        serviceManager.setRewardsInitiator(newInitiator);
    }
}
