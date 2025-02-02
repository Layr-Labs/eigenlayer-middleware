// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {InstantSlasher} from "../../src/slashers/InstantSlasher.sol";
import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISlasher, ISlasherTypes, ISlasherErrors} from "../../src/interfaces/ISlasher.sol";
import {ISlashingRegistryCoordinator} from "../../src/interfaces/ISlashingRegistryCoordinator.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {EmptyContract} from "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";
import {AllocationManager} from "eigenlayer-contracts/src/contracts/core/AllocationManager.sol";
import {PermissionController} from "eigenlayer-contracts/src/contracts/permissions/PermissionController.sol";
import {PauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {DelegationMock} from "../mocks/DelegationMock.sol";
import {SlashingRegistryCoordinator} from "../../src/SlashingRegistryCoordinator.sol";
import {IBLSApkRegistry} from "../../src/interfaces/IBLSApkRegistry.sol";
import {IStakeRegistry} from "../../src/interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "../../src/interfaces/IIndexRegistry.sol";
import {ISocketRegistry} from "../../src/interfaces/ISocketRegistry.sol";

contract InstantSlasherTest is Test {
    InstantSlasher public instantSlasher;
    InstantSlasher public instantSlasherImplementation;
    ProxyAdmin public proxyAdmin;
    EmptyContract public emptyContract;
    AllocationManager public allocationManager;
    AllocationManager public allocationManagerImplementation;
    PermissionController public permissionController;
    PauserRegistry public pauserRegistry;
    DelegationMock public delegationMock;
    SlashingRegistryCoordinator public slashingRegistryCoordinator;
    SlashingRegistryCoordinator public slashingRegistryCoordinatorImplementation;

    address public slasher;
    address public serviceManager;
    address public operator;
    IStrategy public mockStrategy;
    address public proxyAdminOwner = address(uint160(uint256(keccak256("proxyAdminOwner"))));
    address public pauser = address(uint160(uint256(keccak256("pauser"))));
    address public unpauser = address(uint160(uint256(keccak256("unpauser"))));
    address public churnApprover = address(uint160(uint256(keccak256("churnApprover"))));
    address public ejector = address(uint160(uint256(keccak256("ejector"))));

    uint32 constant DEALLOCATION_DELAY = 7 days;
    uint32 constant ALLOCATION_CONFIGURATION_DELAY = 1 days;

    function setUp() public {
        serviceManager = address(0x2);
        slasher = address(0x3);
        operator = address(0x4);
        mockStrategy = IStrategy(address(0x5));

        vm.startPrank(proxyAdminOwner);
        proxyAdmin = new ProxyAdmin();
        emptyContract = new EmptyContract();

        address[] memory pausers = new address[](1);
        pausers[0] = pauser;
        pauserRegistry = new PauserRegistry(pausers, unpauser);

        delegationMock = new DelegationMock();

        permissionController = new PermissionController();

        allocationManagerImplementation = new AllocationManager(
            delegationMock,
            pauserRegistry,
            permissionController,
            DEALLOCATION_DELAY,
            ALLOCATION_CONFIGURATION_DELAY
        );

        allocationManager = AllocationManager(
            address(
                new TransparentUpgradeableProxy(
                    address(allocationManagerImplementation),
                    address(proxyAdmin),
                    ""
                )
            )
        );

        allocationManager.initialize(proxyAdminOwner, 0);

        // Deploy and set up SlashingRegistryCoordinator
        slashingRegistryCoordinatorImplementation = new SlashingRegistryCoordinator(
            IStakeRegistry(address(0)), // Mock stake registry
            IBLSApkRegistry(address(0)), // Mock BLS APK registry
            IIndexRegistry(address(0)), // Mock index registry
            ISocketRegistry(address(0)), // Mock socket registry
            allocationManager,
            pauserRegistry
        );

        slashingRegistryCoordinator = SlashingRegistryCoordinator(
            address(
                new TransparentUpgradeableProxy(
                    address(slashingRegistryCoordinatorImplementation),
                    address(proxyAdmin),
                    ""
                )
            )
        );

        slashingRegistryCoordinator.initialize(
            proxyAdminOwner,
            churnApprover,
            ejector,
            0, // Initial paused status
            serviceManager
        );

        vm.stopPrank();

        instantSlasherImplementation = new InstantSlasher(
            allocationManager,
            ISlashingRegistryCoordinator(slashingRegistryCoordinator),
            slasher
        );

        instantSlasher = InstantSlasher(
            address(
                new TransparentUpgradeableProxy(
                    address(emptyContract),
                    address(proxyAdmin),
                    ""
                )
            )
        );

        vm.startPrank(proxyAdminOwner);
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(instantSlasher))),
            address(instantSlasherImplementation)
        );
        vm.stopPrank();


        instantSlasher.initialize(slasher);

        vm.prank(serviceManager);
        permissionController.setAppointee(
            address(serviceManager),
            address(instantSlasher),
            address(allocationManager),
            AllocationManager.slashOperator.selector
        );
    }

    function test_initialization() public {
        assertEq(instantSlasher.slasher(), slasher);
    }

    function _createMockSlashingParams() internal view returns (IAllocationManagerTypes.SlashingParams memory) {
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = mockStrategy;

        uint256[] memory wadsToSlash = new uint256[](1);
        wadsToSlash[0] = 0.5e18; // 50% slash

        return IAllocationManagerTypes.SlashingParams({
            operator: operator,
            operatorSetId: 1,
            strategies: strategies,
            wadsToSlash: wadsToSlash,
            description: "Test slashing"
        });
    }

    function test_fulfillSlashingRequest_revert_notSlasher() public {
        IAllocationManagerTypes.SlashingParams memory params = _createMockSlashingParams();
        vm.expectRevert(ISlasherErrors.OnlySlasher.selector);
        instantSlasher.fulfillSlashingRequest(params);
    }

    function test_fulfillSlashingRequest() public {
        vm.skip(true); /// TODO:
        IAllocationManagerTypes.SlashingParams memory params = _createMockSlashingParams();
        vm.prank(slasher);
        instantSlasher.fulfillSlashingRequest(params);
    }
}
