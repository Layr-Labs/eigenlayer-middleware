// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";

import {TaskAVSRegistrarBase} from "../../src/avs/task/TaskAVSRegistrarBase.sol";
import {ITaskAVSRegistrarBase} from "../../src/interfaces/ITaskAVSRegistrarBase.sol";
import {ITaskAVSRegistrarBaseTypes} from "../../src/interfaces/ITaskAVSRegistrarBase.sol";
import {ITaskAVSRegistrarBaseErrors} from "../../src/interfaces/ITaskAVSRegistrarBase.sol";
import {ITaskAVSRegistrarBaseEvents} from "../../src/interfaces/ITaskAVSRegistrarBase.sol";
import {MockTaskAVSRegistrar} from "../mocks/MockTaskAVSRegistrar.sol";
import {AllocationManagerMock} from "../mocks/AllocationManagerMock.sol";
import {KeyRegistrarMock} from "../mocks/KeyRegistrarMock.sol";

// Base test contract with common setup
contract TaskAVSRegistrarBaseUnitTests is
    Test,
    ITaskAVSRegistrarBaseTypes,
    ITaskAVSRegistrarBaseErrors,
    ITaskAVSRegistrarBaseEvents
{
    // Test addresses
    address public avs = address(0x1);
    address public owner = address(0x4);
    address public nonOwner = address(0x5);

    // Mock contracts
    AllocationManagerMock public allocationManager;
    KeyRegistrarMock public keyRegistrar;

    // Test operator set IDs
    uint32 public constant AGGREGATOR_OPERATOR_SET_ID = 1;
    uint32 public constant EXECUTOR_OPERATOR_SET_ID_1 = 2;
    uint32 public constant EXECUTOR_OPERATOR_SET_ID_2 = 3;
    uint32 public constant EXECUTOR_OPERATOR_SET_ID_3 = 4;

    // Contract under test
    MockTaskAVSRegistrar public registrar;
    ProxyAdmin public proxyAdmin;

    function setUp() public virtual {
        // Deploy mock contracts
        allocationManager = new AllocationManagerMock();
        keyRegistrar = new KeyRegistrarMock();

        // Create initial valid config
        AvsConfig memory initialConfig = _createValidAvsConfig();

        // Deploy the registrar with proxy pattern
        proxyAdmin = new ProxyAdmin();
        MockTaskAVSRegistrar registrarImpl = new MockTaskAVSRegistrar(
            IAllocationManager(address(allocationManager)), IKeyRegistrar(address(keyRegistrar))
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(registrarImpl),
            address(proxyAdmin),
            abi.encodeWithSelector(
                MockTaskAVSRegistrar.initialize.selector, avs, owner, initialConfig
            )
        );
        registrar = MockTaskAVSRegistrar(address(proxy));
    }

    // Helper function to create a valid AVS config
    function _createValidAvsConfig() internal pure returns (AvsConfig memory) {
        uint32[] memory executorOperatorSetIds = new uint32[](2);
        executorOperatorSetIds[0] = EXECUTOR_OPERATOR_SET_ID_1;
        executorOperatorSetIds[1] = EXECUTOR_OPERATOR_SET_ID_2;

        return AvsConfig({
            aggregatorOperatorSetId: AGGREGATOR_OPERATOR_SET_ID,
            executorOperatorSetIds: executorOperatorSetIds
        });
    }

    // Helper function to create config with empty executor set
    function _createEmptyExecutorSetConfig() internal pure returns (AvsConfig memory) {
        uint32[] memory executorOperatorSetIds = new uint32[](0);

        return AvsConfig({
            aggregatorOperatorSetId: AGGREGATOR_OPERATOR_SET_ID,
            executorOperatorSetIds: executorOperatorSetIds
        });
    }

    // Helper function to create config with duplicate executor IDs
    function _createDuplicateExecutorConfig() internal pure returns (AvsConfig memory) {
        uint32[] memory executorOperatorSetIds = new uint32[](3);
        executorOperatorSetIds[0] = EXECUTOR_OPERATOR_SET_ID_1;
        executorOperatorSetIds[1] = EXECUTOR_OPERATOR_SET_ID_2;
        executorOperatorSetIds[2] = EXECUTOR_OPERATOR_SET_ID_2; // Duplicate

        return AvsConfig({
            aggregatorOperatorSetId: AGGREGATOR_OPERATOR_SET_ID,
            executorOperatorSetIds: executorOperatorSetIds
        });
    }

    // Helper function to create config with unsorted executor IDs
    function _createUnsortedExecutorConfig() internal pure returns (AvsConfig memory) {
        uint32[] memory executorOperatorSetIds = new uint32[](3);
        executorOperatorSetIds[0] = EXECUTOR_OPERATOR_SET_ID_2;
        executorOperatorSetIds[1] = EXECUTOR_OPERATOR_SET_ID_1; // Not sorted
        executorOperatorSetIds[2] = EXECUTOR_OPERATOR_SET_ID_3;

        return AvsConfig({
            aggregatorOperatorSetId: AGGREGATOR_OPERATOR_SET_ID,
            executorOperatorSetIds: executorOperatorSetIds
        });
    }

    // Helper function to create config where aggregator ID matches executor ID
    function _createAggregatorMatchingExecutorConfig() internal pure returns (AvsConfig memory) {
        uint32[] memory executorOperatorSetIds = new uint32[](2);
        executorOperatorSetIds[0] = AGGREGATOR_OPERATOR_SET_ID; // Same as aggregator
        executorOperatorSetIds[1] = EXECUTOR_OPERATOR_SET_ID_2;

        return AvsConfig({
            aggregatorOperatorSetId: AGGREGATOR_OPERATOR_SET_ID,
            executorOperatorSetIds: executorOperatorSetIds
        });
    }
}

// Test contract for constructor
contract TaskAVSRegistrarBaseUnitTests_Constructor is TaskAVSRegistrarBaseUnitTests {
    function test_Constructor() public {
        // Create config for new deployment
        AvsConfig memory config = _createValidAvsConfig();

        // Deploy new registrar with proxy pattern
        ProxyAdmin newProxyAdmin = new ProxyAdmin();
        MockTaskAVSRegistrar newRegistrarImpl = new MockTaskAVSRegistrar(
            IAllocationManager(address(allocationManager)), IKeyRegistrar(address(keyRegistrar))
        );
        TransparentUpgradeableProxy newProxy = new TransparentUpgradeableProxy(
            address(newRegistrarImpl),
            address(newProxyAdmin),
            abi.encodeWithSelector(MockTaskAVSRegistrar.initialize.selector, avs, owner, config)
        );
        MockTaskAVSRegistrar newRegistrar = MockTaskAVSRegistrar(address(newProxy));

        // Verify AVS was set
        assertEq(newRegistrar.avs(), avs);

        // Verify owner was set
        assertEq(newRegistrar.owner(), owner);

        // Verify config was set
        AvsConfig memory storedConfig = newRegistrar.getAvsConfig();
        assertEq(storedConfig.aggregatorOperatorSetId, config.aggregatorOperatorSetId);
        assertEq(storedConfig.executorOperatorSetIds.length, config.executorOperatorSetIds.length);
        for (uint256 i = 0; i < config.executorOperatorSetIds.length; i++) {
            assertEq(storedConfig.executorOperatorSetIds[i], config.executorOperatorSetIds[i]);
        }
    }

    function test_Constructor_EmitsAvsConfigSet() public {
        AvsConfig memory config = _createValidAvsConfig();

        // Deploy implementation
        ProxyAdmin newProxyAdmin = new ProxyAdmin();
        MockTaskAVSRegistrar newRegistrarImpl = new MockTaskAVSRegistrar(
            IAllocationManager(address(allocationManager)), IKeyRegistrar(address(keyRegistrar))
        );

        // Expect event during initialization
        vm.expectEmit(true, true, true, true);
        emit AvsConfigSet(config.aggregatorOperatorSetId, config.executorOperatorSetIds);

        // Deploy proxy with initialization
        new TransparentUpgradeableProxy(
            address(newRegistrarImpl),
            address(newProxyAdmin),
            abi.encodeWithSelector(MockTaskAVSRegistrar.initialize.selector, avs, owner, config)
        );
    }

    function test_Revert_Constructor_EmptyExecutorSet() public {
        AvsConfig memory config = _createEmptyExecutorSetConfig();

        // Deploy implementation
        ProxyAdmin newProxyAdmin = new ProxyAdmin();
        MockTaskAVSRegistrar newRegistrarImpl = new MockTaskAVSRegistrar(
            IAllocationManager(address(allocationManager)), IKeyRegistrar(address(keyRegistrar))
        );

        // Expect revert during initialization
        vm.expectRevert(ExecutorOperatorSetIdsEmpty.selector);
        new TransparentUpgradeableProxy(
            address(newRegistrarImpl),
            address(newProxyAdmin),
            abi.encodeWithSelector(MockTaskAVSRegistrar.initialize.selector, avs, owner, config)
        );
    }

    function test_Revert_Constructor_InvalidAggregatorId() public {
        AvsConfig memory config = _createAggregatorMatchingExecutorConfig();

        // Deploy implementation
        ProxyAdmin newProxyAdmin = new ProxyAdmin();
        MockTaskAVSRegistrar newRegistrarImpl = new MockTaskAVSRegistrar(
            IAllocationManager(address(allocationManager)), IKeyRegistrar(address(keyRegistrar))
        );

        // Expect revert during initialization
        vm.expectRevert(InvalidAggregatorOperatorSetId.selector);
        new TransparentUpgradeableProxy(
            address(newRegistrarImpl),
            address(newProxyAdmin),
            abi.encodeWithSelector(MockTaskAVSRegistrar.initialize.selector, avs, owner, config)
        );
    }

    function test_Revert_Constructor_DuplicateExecutorId() public {
        AvsConfig memory config = _createDuplicateExecutorConfig();

        // Deploy implementation
        ProxyAdmin newProxyAdmin = new ProxyAdmin();
        MockTaskAVSRegistrar newRegistrarImpl = new MockTaskAVSRegistrar(
            IAllocationManager(address(allocationManager)), IKeyRegistrar(address(keyRegistrar))
        );

        // Expect revert during initialization
        vm.expectRevert(DuplicateExecutorOperatorSetId.selector);
        new TransparentUpgradeableProxy(
            address(newRegistrarImpl),
            address(newProxyAdmin),
            abi.encodeWithSelector(MockTaskAVSRegistrar.initialize.selector, avs, owner, config)
        );
    }

    function test_Revert_Constructor_UnsortedExecutorIds() public {
        AvsConfig memory config = _createUnsortedExecutorConfig();

        // Deploy implementation
        ProxyAdmin newProxyAdmin = new ProxyAdmin();
        MockTaskAVSRegistrar newRegistrarImpl = new MockTaskAVSRegistrar(
            IAllocationManager(address(allocationManager)), IKeyRegistrar(address(keyRegistrar))
        );

        // Expect revert during initialization
        vm.expectRevert(DuplicateExecutorOperatorSetId.selector);
        new TransparentUpgradeableProxy(
            address(newRegistrarImpl),
            address(newProxyAdmin),
            abi.encodeWithSelector(MockTaskAVSRegistrar.initialize.selector, avs, owner, config)
        );
    }
}

// Test contract for setAvsConfig
contract TaskAVSRegistrarBaseUnitTests_setAvsConfig is TaskAVSRegistrarBaseUnitTests {
    function test_setAvsConfig() public {
        // Create new config
        uint32[] memory newExecutorIds = new uint32[](3);
        newExecutorIds[0] = 10;
        newExecutorIds[1] = 20;
        newExecutorIds[2] = 30;

        AvsConfig memory newConfig =
            AvsConfig({aggregatorOperatorSetId: 5, executorOperatorSetIds: newExecutorIds});

        // Expect event
        vm.expectEmit(true, true, true, true, address(registrar));
        emit AvsConfigSet(newConfig.aggregatorOperatorSetId, newConfig.executorOperatorSetIds);

        // Set config as owner
        vm.prank(owner);
        registrar.setAvsConfig(newConfig);

        // Verify config was updated
        AvsConfig memory storedConfig = registrar.getAvsConfig();
        assertEq(storedConfig.aggregatorOperatorSetId, newConfig.aggregatorOperatorSetId);
        assertEq(
            storedConfig.executorOperatorSetIds.length, newConfig.executorOperatorSetIds.length
        );
        for (uint256 i = 0; i < newConfig.executorOperatorSetIds.length; i++) {
            assertEq(storedConfig.executorOperatorSetIds[i], newConfig.executorOperatorSetIds[i]);
        }
    }

    function test_setAvsConfig_SingleExecutor() public {
        // Create config with single executor
        uint32[] memory executorIds = new uint32[](1);
        executorIds[0] = 10;

        AvsConfig memory config =
            AvsConfig({aggregatorOperatorSetId: 5, executorOperatorSetIds: executorIds});

        vm.prank(owner);
        registrar.setAvsConfig(config);

        // Verify config was updated
        AvsConfig memory storedConfig = registrar.getAvsConfig();
        assertEq(storedConfig.executorOperatorSetIds.length, 1);
        assertEq(storedConfig.executorOperatorSetIds[0], 10);
    }

    function test_Revert_setAvsConfig_NotOwner() public {
        AvsConfig memory config = _createValidAvsConfig();

        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        registrar.setAvsConfig(config);
    }

    function test_Revert_setAvsConfig_EmptyExecutorSet() public {
        AvsConfig memory config = _createEmptyExecutorSetConfig();

        vm.prank(owner);
        vm.expectRevert(ExecutorOperatorSetIdsEmpty.selector);
        registrar.setAvsConfig(config);
    }

    function test_Revert_setAvsConfig_InvalidAggregatorId_FirstElement() public {
        AvsConfig memory config = _createAggregatorMatchingExecutorConfig();

        vm.prank(owner);
        vm.expectRevert(InvalidAggregatorOperatorSetId.selector);
        registrar.setAvsConfig(config);
    }

    function test_Revert_setAvsConfig_InvalidAggregatorId_MiddleElement() public {
        uint32[] memory executorIds = new uint32[](3);
        executorIds[0] = 10;
        executorIds[1] = 20; // This will be the aggregator ID
        executorIds[2] = 30;

        AvsConfig memory config = AvsConfig({
            aggregatorOperatorSetId: 20, // Matches middle executor
            executorOperatorSetIds: executorIds
        });

        vm.prank(owner);
        vm.expectRevert(InvalidAggregatorOperatorSetId.selector);
        registrar.setAvsConfig(config);
    }

    function test_Revert_setAvsConfig_InvalidAggregatorId_LastElement() public {
        uint32[] memory executorIds = new uint32[](3);
        executorIds[0] = 10;
        executorIds[1] = 20;
        executorIds[2] = 30; // This will be the aggregator ID

        AvsConfig memory config = AvsConfig({
            aggregatorOperatorSetId: 30, // Matches last executor
            executorOperatorSetIds: executorIds
        });

        vm.prank(owner);
        vm.expectRevert(InvalidAggregatorOperatorSetId.selector);
        registrar.setAvsConfig(config);
    }

    function test_Revert_setAvsConfig_DuplicateExecutorId() public {
        AvsConfig memory config = _createDuplicateExecutorConfig();

        vm.prank(owner);
        vm.expectRevert(DuplicateExecutorOperatorSetId.selector);
        registrar.setAvsConfig(config);
    }

    function test_Revert_setAvsConfig_UnsortedExecutorIds() public {
        AvsConfig memory config = _createUnsortedExecutorConfig();

        vm.prank(owner);
        vm.expectRevert(DuplicateExecutorOperatorSetId.selector);
        registrar.setAvsConfig(config);
    }

    function testFuzz_setAvsConfig(uint32 aggregatorId, uint8 numExecutors) public {
        // Bound inputs
        vm.assume(numExecutors > 0 && numExecutors <= 10);
        vm.assume(aggregatorId > 0);
        // Ensure we have room for executor IDs without overflow
        vm.assume(aggregatorId < type(uint32).max - (uint32(numExecutors) * 10));

        // Create executor IDs that don't conflict with aggregator
        uint32[] memory executorIds = new uint32[](numExecutors);
        uint32 currentId = aggregatorId + 1;
        for (uint8 i = 0; i < numExecutors; i++) {
            executorIds[i] = currentId;
            currentId += 10; // Ensure monotonic increase
        }

        AvsConfig memory config =
            AvsConfig({aggregatorOperatorSetId: aggregatorId, executorOperatorSetIds: executorIds});

        vm.prank(owner);
        registrar.setAvsConfig(config);

        // Verify
        AvsConfig memory storedConfig = registrar.getAvsConfig();
        assertEq(storedConfig.aggregatorOperatorSetId, aggregatorId);
        assertEq(storedConfig.executorOperatorSetIds.length, numExecutors);
    }
}

// Test contract for upgradeable functionality
contract TaskAVSRegistrarBaseUnitTests_Upgradeable is TaskAVSRegistrarBaseUnitTests {
    function test_Initialize_OnlyOnce() public {
        // Try to initialize again, should revert
        vm.expectRevert("Initializable: contract is already initialized");
        registrar.initialize(avs, address(0x9999), _createValidAvsConfig());
    }

    function test_Implementation_CannotBeInitialized() public {
        // Deploy a new implementation
        MockTaskAVSRegistrar newImpl = new MockTaskAVSRegistrar(
            IAllocationManager(address(allocationManager)), IKeyRegistrar(address(keyRegistrar))
        );

        // Try to initialize the implementation directly, should revert
        vm.expectRevert("Initializable: contract is already initialized");
        newImpl.initialize(avs, owner, _createValidAvsConfig());
    }

    function test_ProxyUpgrade() public {
        address newOwner = address(0x1234);

        // First, make some state changes
        AvsConfig memory newConfig =
            AvsConfig({aggregatorOperatorSetId: 5, executorOperatorSetIds: new uint32[](2)});
        newConfig.executorOperatorSetIds[0] = 6;
        newConfig.executorOperatorSetIds[1] = 7;

        vm.prank(owner);
        registrar.setAvsConfig(newConfig);

        // Deploy new implementation (could have new functions/logic)
        MockTaskAVSRegistrar newImpl = new MockTaskAVSRegistrar(
            IAllocationManager(address(allocationManager)), IKeyRegistrar(address(keyRegistrar))
        );

        // Upgrade proxy to new implementation
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(registrar)), address(newImpl));

        // Verify state is preserved (config should still be the same)
        AvsConfig memory storedConfig = registrar.getAvsConfig();
        assertEq(storedConfig.aggregatorOperatorSetId, newConfig.aggregatorOperatorSetId);
        assertEq(
            storedConfig.executorOperatorSetIds.length, newConfig.executorOperatorSetIds.length
        );
        for (uint256 i = 0; i < newConfig.executorOperatorSetIds.length; i++) {
            assertEq(storedConfig.executorOperatorSetIds[i], newConfig.executorOperatorSetIds[i]);
        }

        // Verify owner is still the same
        assertEq(registrar.owner(), owner);
    }

    function test_ProxyAdmin_OnlyOwnerCanUpgrade() public {
        address attacker = address(0x9999);

        // Deploy new implementation
        MockTaskAVSRegistrar newImpl = new MockTaskAVSRegistrar(
            IAllocationManager(address(allocationManager)), IKeyRegistrar(address(keyRegistrar))
        );

        // Try to upgrade from non-owner, should revert
        vm.prank(attacker);
        vm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(registrar)), address(newImpl));
    }

    function test_Initialization_SetsCorrectValues() public {
        // Already tested in setUp, but let's verify again explicitly
        assertEq(registrar.owner(), owner);

        // Verify initial config
        AvsConfig memory config = registrar.getAvsConfig();
        assertEq(config.aggregatorOperatorSetId, AGGREGATOR_OPERATOR_SET_ID);
        assertEq(config.executorOperatorSetIds.length, 2);
        assertEq(config.executorOperatorSetIds[0], EXECUTOR_OPERATOR_SET_ID_1);
        assertEq(config.executorOperatorSetIds[1], EXECUTOR_OPERATOR_SET_ID_2);
    }

    function test_ProxyAdmin_CannotCallImplementation() public {
        // ProxyAdmin should not be able to call implementation functions
        vm.prank(address(proxyAdmin));
        vm.expectRevert("TransparentUpgradeableProxy: admin cannot fallback to proxy target");
        MockTaskAVSRegistrar(payable(address(registrar))).owner();
    }

    function test_StorageSlotConsistency_AfterUpgrade() public {
        address newOwner = address(0x1234);

        // First, transfer ownership to track a state change
        vm.prank(owner);
        registrar.transferOwnership(newOwner);
        assertEq(registrar.owner(), newOwner);

        // Set a different config
        AvsConfig memory newConfig =
            AvsConfig({aggregatorOperatorSetId: 10, executorOperatorSetIds: new uint32[](3)});
        newConfig.executorOperatorSetIds[0] = 11;
        newConfig.executorOperatorSetIds[1] = 12;
        newConfig.executorOperatorSetIds[2] = 13;

        vm.prank(newOwner);
        registrar.setAvsConfig(newConfig);

        // Deploy new implementation
        MockTaskAVSRegistrar newImpl = new MockTaskAVSRegistrar(
            IAllocationManager(address(allocationManager)), IKeyRegistrar(address(keyRegistrar))
        );

        // Upgrade
        vm.prank(address(this)); // proxyAdmin owner
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(registrar)), address(newImpl));

        // Verify all state is preserved after upgrade
        assertEq(registrar.owner(), newOwner);

        // Verify the config is still there
        AvsConfig memory configAfterUpgrade = registrar.getAvsConfig();
        assertEq(configAfterUpgrade.aggregatorOperatorSetId, newConfig.aggregatorOperatorSetId);
        assertEq(
            configAfterUpgrade.executorOperatorSetIds.length,
            newConfig.executorOperatorSetIds.length
        );
        for (uint256 i = 0; i < newConfig.executorOperatorSetIds.length; i++) {
            assertEq(
                configAfterUpgrade.executorOperatorSetIds[i], newConfig.executorOperatorSetIds[i]
            );
        }
    }

    function test_InitializerModifier_PreventsReinitialization() public {
        // Deploy a new proxy without initialization data
        TransparentUpgradeableProxy uninitializedProxy = new TransparentUpgradeableProxy(
            address(
                new MockTaskAVSRegistrar(
                    IAllocationManager(address(allocationManager)),
                    IKeyRegistrar(address(keyRegistrar))
                )
            ),
            address(new ProxyAdmin()),
            ""
        );

        MockTaskAVSRegistrar uninitializedRegistrar =
            MockTaskAVSRegistrar(address(uninitializedProxy));

        // Initialize it once
        AvsConfig memory config = _createValidAvsConfig();
        uninitializedRegistrar.initialize(avs, owner, config);
        assertEq(uninitializedRegistrar.owner(), owner);

        // Try to initialize again, should fail
        vm.expectRevert("Initializable: contract is already initialized");
        uninitializedRegistrar.initialize(avs, address(0x9999), config);
    }

    function test_DisableInitializers_InImplementation() public {
        // This test verifies that the implementation contract has initializers disabled
        MockTaskAVSRegistrar impl = new MockTaskAVSRegistrar(
            IAllocationManager(address(allocationManager)), IKeyRegistrar(address(keyRegistrar))
        );

        // Try to initialize the implementation, should revert
        vm.expectRevert("Initializable: contract is already initialized");
        impl.initialize(avs, owner, _createValidAvsConfig());
    }
}

// Test contract for getAvsConfig
contract TaskAVSRegistrarBaseUnitTests_getAvsConfig is TaskAVSRegistrarBaseUnitTests {
    function test_getAvsConfig() public {
        // Get initial config
        AvsConfig memory config = registrar.getAvsConfig();

        // Verify it matches what was set in constructor
        assertEq(config.aggregatorOperatorSetId, AGGREGATOR_OPERATOR_SET_ID);
        assertEq(config.executorOperatorSetIds.length, 2);
        assertEq(config.executorOperatorSetIds[0], EXECUTOR_OPERATOR_SET_ID_1);
        assertEq(config.executorOperatorSetIds[1], EXECUTOR_OPERATOR_SET_ID_2);
    }

    function test_getAvsConfig_AfterUpdate() public {
        // Update config
        uint32[] memory newExecutorIds = new uint32[](1);
        newExecutorIds[0] = 100;

        AvsConfig memory newConfig =
            AvsConfig({aggregatorOperatorSetId: 50, executorOperatorSetIds: newExecutorIds});

        vm.prank(owner);
        registrar.setAvsConfig(newConfig);

        // Get updated config
        AvsConfig memory config = registrar.getAvsConfig();

        // Verify it matches the update
        assertEq(config.aggregatorOperatorSetId, 50);
        assertEq(config.executorOperatorSetIds.length, 1);
        assertEq(config.executorOperatorSetIds[0], 100);
    }

    function test_getAvsConfig_CalledByNonOwner() public {
        // Anyone should be able to read the config
        vm.prank(nonOwner);
        AvsConfig memory config = registrar.getAvsConfig();

        // Verify it returns correct data
        assertEq(config.aggregatorOperatorSetId, AGGREGATOR_OPERATOR_SET_ID);
        assertEq(config.executorOperatorSetIds.length, 2);
    }
}

// Test contract for access control
contract TaskAVSRegistrarBaseUnitTests_AccessControl is TaskAVSRegistrarBaseUnitTests {
    function test_Owner() public {
        assertEq(registrar.owner(), owner);
    }

    function test_OnlyOwnerCanSetConfig() public {
        AvsConfig memory config = _createValidAvsConfig();

        // Owner can set config
        vm.prank(owner);
        registrar.setAvsConfig(config);

        // Non-owner cannot
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        registrar.setAvsConfig(config);
    }

    function test_TransferOwnership() public {
        address newOwner = address(0x123);

        // Transfer ownership
        vm.prank(owner);
        registrar.transferOwnership(newOwner);

        // Verify new owner
        assertEq(registrar.owner(), newOwner);

        // Old owner can no longer set config
        AvsConfig memory config = _createValidAvsConfig();
        vm.prank(owner);
        vm.expectRevert("Ownable: caller is not the owner");
        registrar.setAvsConfig(config);

        // New owner can set config
        vm.prank(newOwner);
        registrar.setAvsConfig(config);
    }

    function test_RenounceOwnership() public {
        // Renounce ownership
        vm.prank(owner);
        registrar.renounceOwnership();

        // Verify owner is zero address
        assertEq(registrar.owner(), address(0));

        // No one can set config anymore
        AvsConfig memory config = _createValidAvsConfig();
        vm.prank(owner);
        vm.expectRevert("Ownable: caller is not the owner");
        registrar.setAvsConfig(config);
    }
}
