// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

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
import {MockEigenLayerDeployer} from "./middlewareV2/MockDeployer.sol";
import {IAllowlist} from "../../src/interfaces/IAllowlist.sol";
import {OperatorSet} from
    "../../lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IAllowlistErrors} from "../../src/interfaces/IAllowlist.sol";
import {IAllowlistEvents} from "../../src/interfaces/IAllowlist.sol";
import {IAVSRegistrar} from
    "../../lib/eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IAVSRegistrarInternal} from "../../src/interfaces/IAVSRegistrarInternal.sol";

// Base test contract with common setup
contract TaskAVSRegistrarBaseUnitTests is
    MockEigenLayerDeployer,
    ITaskAVSRegistrarBaseTypes,
    ITaskAVSRegistrarBaseErrors,
    ITaskAVSRegistrarBaseEvents,
    IAllowlistErrors,
    IAllowlistEvents,
    IAVSRegistrarInternal
{
    // Test addresses
    address public avs = address(0x1);
    address public owner = address(0x4);
    address public nonOwner = address(0x5);

    // Test operator set IDs
    uint32 public constant AGGREGATOR_OPERATOR_SET_ID = 1;
    uint32 public constant EXECUTOR_OPERATOR_SET_ID_1 = 2;
    uint32 public constant EXECUTOR_OPERATOR_SET_ID_2 = 3;
    uint32 public constant EXECUTOR_OPERATOR_SET_ID_3 = 4;

    // Contract under test
    MockTaskAVSRegistrar public registrar;

    function setUp() public virtual {
        // Deploy mock EigenLayer contracts
        _deployMockEigenLayer();

        // Create initial valid config
        AvsConfig memory initialConfig = _createValidAvsConfig();

        // Deploy the registrar with proxy pattern
        MockTaskAVSRegistrar registrarImpl = new MockTaskAVSRegistrar(
            IAllocationManager(address(allocationManagerMock)),
            IKeyRegistrar(address(keyRegistrarMock)),
            permissionController
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(registrarImpl),
            address(proxyAdmin),
            abi.encodeWithSelector(
                MockTaskAVSRegistrar.initialize.selector, avs, owner, initialConfig
            )
        );
        registrar = MockTaskAVSRegistrar(address(proxy));

        // Configure the AllocationManagerMock to know about this registrar
        allocationManagerMock.setAVSRegistrar(avs, IAVSRegistrar(address(registrar)));
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
            IAllocationManager(address(allocationManagerMock)),
            IKeyRegistrar(address(keyRegistrarMock)),
            permissionController
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
            IAllocationManager(address(allocationManagerMock)),
            IKeyRegistrar(address(keyRegistrarMock)),
            permissionController
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
            IAllocationManager(address(allocationManagerMock)),
            IKeyRegistrar(address(keyRegistrarMock)),
            permissionController
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
            IAllocationManager(address(allocationManagerMock)),
            IKeyRegistrar(address(keyRegistrarMock)),
            permissionController
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
            IAllocationManager(address(allocationManagerMock)),
            IKeyRegistrar(address(keyRegistrarMock)),
            permissionController
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
            IAllocationManager(address(allocationManagerMock)),
            IKeyRegistrar(address(keyRegistrarMock)),
            permissionController
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
            IAllocationManager(address(allocationManagerMock)),
            IKeyRegistrar(address(keyRegistrarMock)),
            permissionController
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
            IAllocationManager(address(allocationManagerMock)),
            IKeyRegistrar(address(keyRegistrarMock)),
            permissionController
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
            IAllocationManager(address(allocationManagerMock)),
            IKeyRegistrar(address(keyRegistrarMock)),
            permissionController
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
            IAllocationManager(address(allocationManagerMock)),
            IKeyRegistrar(address(keyRegistrarMock)),
            permissionController
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
                    IAllocationManager(address(allocationManagerMock)),
                    IKeyRegistrar(address(keyRegistrarMock)),
                    permissionController
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
            IAllocationManager(address(allocationManagerMock)),
            IKeyRegistrar(address(keyRegistrarMock)),
            permissionController
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

// Test contract for allowlist functionality
contract TaskAVSRegistrarBaseUnitTests_Allowlist is TaskAVSRegistrarBaseUnitTests {
    // Test addresses for allowlist testing
    address public constant ALLOWLISTED_OPERATOR_1 = address(0x100);
    address public constant ALLOWLISTED_OPERATOR_2 = address(0x101);
    address public constant NON_ALLOWLISTED_OPERATOR = address(0x102);
    address public constant ANOTHER_OPERATOR = address(0x103);

    // Test operator sets
    OperatorSet public aggregatorOperatorSet;
    OperatorSet public executorOperatorSet1;
    OperatorSet public executorOperatorSet2;

    function setUp() public override {
        super.setUp();

        // Create operator sets for testing
        aggregatorOperatorSet = OperatorSet({avs: avs, id: AGGREGATOR_OPERATOR_SET_ID});
        executorOperatorSet1 = OperatorSet({avs: avs, id: EXECUTOR_OPERATOR_SET_ID_1});
        executorOperatorSet2 = OperatorSet({avs: avs, id: EXECUTOR_OPERATOR_SET_ID_2});
    }

    // Helper function to add operators to allowlist
    function _addOperatorToAllowlist(OperatorSet memory operatorSet, address operator) internal {
        vm.prank(owner);
        registrar.addOperatorToAllowlist(operatorSet, operator);
    }

    // Helper function to remove operators from allowlist
    function _removeOperatorFromAllowlist(
        OperatorSet memory operatorSet,
        address operator
    ) internal {
        vm.prank(owner);
        registrar.removeOperatorFromAllowlist(operatorSet, operator);
    }

    function test_AllowlistInitialization() public {
        // Verify allowlist is properly initialized
        assertEq(registrar.owner(), owner);

        // Check that no operators are allowlisted initially
        assertFalse(registrar.isOperatorAllowed(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1));
        assertFalse(registrar.isOperatorAllowed(executorOperatorSet1, ALLOWLISTED_OPERATOR_1));
    }

    function test_AddOperatorToAllowlist() public {
        // Add operator to allowlist
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);

        // Verify operator is now allowlisted
        assertTrue(registrar.isOperatorAllowed(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1));
        assertFalse(registrar.isOperatorAllowed(aggregatorOperatorSet, NON_ALLOWLISTED_OPERATOR));
    }

    function test_AddOperatorToAllowlist_EmitsEvent() public {
        // Expect event emission
        vm.expectEmit(true, true, true, true, address(registrar));
        emit OperatorAddedToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);

        // Add operator to allowlist
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);
    }

    function test_AddOperatorToAllowlist_AlreadyInAllowlist() public {
        // Add operator first time
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);

        // Try to add again, should revert
        vm.prank(owner);
        vm.expectRevert(OperatorAlreadyInAllowlist.selector);
        registrar.addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);
    }

    function test_AddOperatorToAllowlist_NotOwner() public {
        // Non-owner tries to add operator
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        registrar.addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);
    }

    function test_RemoveOperatorFromAllowlist() public {
        // Add operator first
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);
        assertTrue(registrar.isOperatorAllowed(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1));

        // Remove operator
        _removeOperatorFromAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);

        // Verify operator is no longer allowlisted
        assertFalse(registrar.isOperatorAllowed(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1));
    }

    function test_RemoveOperatorFromAllowlist_EmitsEvent() public {
        // Add operator first
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);

        // Expect event emission
        vm.expectEmit(true, true, true, true, address(registrar));
        emit OperatorRemovedFromAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);

        // Remove operator
        _removeOperatorFromAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);
    }

    function test_RemoveOperatorFromAllowlist_NotInAllowlist() public {
        // Try to remove operator that's not in allowlist
        vm.prank(owner);
        vm.expectRevert(OperatorNotInAllowlist.selector);
        registrar.removeOperatorFromAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);
    }

    function test_RemoveOperatorFromAllowlist_NotOwner() public {
        // Add operator first
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);

        // Non-owner tries to remove operator
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        registrar.removeOperatorFromAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);
    }

    function test_IsOperatorAllowed() public {
        // Initially not allowlisted
        assertFalse(registrar.isOperatorAllowed(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1));

        // Add to allowlist
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);
        assertTrue(registrar.isOperatorAllowed(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1));

        // Remove from allowlist
        _removeOperatorFromAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);
        assertFalse(registrar.isOperatorAllowed(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1));
    }

    function test_IsOperatorAllowed_DifferentOperatorSets() public {
        // Add operator to one operator set
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);

        // Operator should only be allowlisted for that specific operator set
        assertTrue(registrar.isOperatorAllowed(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1));
        assertFalse(registrar.isOperatorAllowed(executorOperatorSet1, ALLOWLISTED_OPERATOR_1));
        assertFalse(registrar.isOperatorAllowed(executorOperatorSet2, ALLOWLISTED_OPERATOR_1));
    }

    function test_GetAllowedOperators() public {
        // Initially empty
        address[] memory allowedOperators = registrar.getAllowedOperators(aggregatorOperatorSet);
        assertEq(allowedOperators.length, 0);

        // Add operators
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_2);

        // Get allowed operators
        allowedOperators = registrar.getAllowedOperators(aggregatorOperatorSet);
        assertEq(allowedOperators.length, 2);

        // Verify both operators are in the list (order may vary)
        bool found1 = false;
        bool found2 = false;
        for (uint256 i = 0; i < allowedOperators.length; i++) {
            if (allowedOperators[i] == ALLOWLISTED_OPERATOR_1) found1 = true;
            if (allowedOperators[i] == ALLOWLISTED_OPERATOR_2) found2 = true;
        }
        assertTrue(found1);
        assertTrue(found2);
    }

    function test_GetAllowedOperators_AfterRemoval() public {
        // Add operators
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_2);

        // Remove one operator
        _removeOperatorFromAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);

        // Get allowed operators
        address[] memory allowedOperators = registrar.getAllowedOperators(aggregatorOperatorSet);
        assertEq(allowedOperators.length, 1);
        assertEq(allowedOperators[0], ALLOWLISTED_OPERATOR_2);
    }

    function test_GetAllowedOperators_DifferentOperatorSets() public {
        // Add operators to different operator sets
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);
        _addOperatorToAllowlist(executorOperatorSet1, ALLOWLISTED_OPERATOR_2);

        // Check aggregator operator set
        address[] memory allowedOperators = registrar.getAllowedOperators(aggregatorOperatorSet);
        assertEq(allowedOperators.length, 1);
        assertEq(allowedOperators[0], ALLOWLISTED_OPERATOR_1);

        // Check executor operator set
        allowedOperators = registrar.getAllowedOperators(executorOperatorSet1);
        assertEq(allowedOperators.length, 1);
        assertEq(allowedOperators[0], ALLOWLISTED_OPERATOR_2);
    }

    function test_AllowlistIsolation() public {
        // Add operators to different operator sets
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);
        _addOperatorToAllowlist(executorOperatorSet1, ALLOWLISTED_OPERATOR_2);

        // Verify isolation - operators are only allowlisted for their specific sets
        assertTrue(registrar.isOperatorAllowed(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1));
        assertFalse(registrar.isOperatorAllowed(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_2));
        assertFalse(registrar.isOperatorAllowed(executorOperatorSet1, ALLOWLISTED_OPERATOR_1));
        assertTrue(registrar.isOperatorAllowed(executorOperatorSet1, ALLOWLISTED_OPERATOR_2));
    }

    function test_AllowlistMultipleOperators() public {
        // Add multiple operators to same operator set
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_2);
        _addOperatorToAllowlist(aggregatorOperatorSet, ANOTHER_OPERATOR);

        // Verify all are allowlisted
        assertTrue(registrar.isOperatorAllowed(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1));
        assertTrue(registrar.isOperatorAllowed(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_2));
        assertTrue(registrar.isOperatorAllowed(aggregatorOperatorSet, ANOTHER_OPERATOR));

        // Verify non-allowlisted operator is not allowlisted
        assertFalse(registrar.isOperatorAllowed(aggregatorOperatorSet, NON_ALLOWLISTED_OPERATOR));
    }

    function test_AllowlistEdgeCases() public {
        // Test with zero address
        _addOperatorToAllowlist(aggregatorOperatorSet, address(0));
        assertTrue(registrar.isOperatorAllowed(aggregatorOperatorSet, address(0)));

        // Test with contract address
        address contractAddress = address(registrar);
        _addOperatorToAllowlist(aggregatorOperatorSet, contractAddress);
        assertTrue(registrar.isOperatorAllowed(aggregatorOperatorSet, contractAddress));

        // Test with very large address
        address largeAddress = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);
        _addOperatorToAllowlist(aggregatorOperatorSet, largeAddress);
        assertTrue(registrar.isOperatorAllowed(aggregatorOperatorSet, largeAddress));
    }

    function test_AllowlistOwnershipTransfer() public {
        // Add operator as current owner
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);
        assertTrue(registrar.isOperatorAllowed(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1));

        // Transfer ownership
        address newOwner = address(0x999);
        vm.prank(owner);
        registrar.transferOwnership(newOwner);

        // Old owner can no longer manage allowlist
        vm.prank(owner);
        vm.expectRevert("Ownable: caller is not the owner");
        registrar.addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_2);

        // New owner can manage allowlist
        vm.prank(newOwner);
        registrar.addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_2);
        assertTrue(registrar.isOperatorAllowed(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_2));

        // Old allowlist entries still exist
        assertTrue(registrar.isOperatorAllowed(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1));
    }

    function test_AllowlistOwnershipRenounce() public {
        // Add operator
        _addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1);

        // Renounce ownership
        vm.prank(owner);
        registrar.renounceOwnership();

        // No one can manage allowlist anymore
        vm.prank(owner);
        vm.expectRevert("Ownable: caller is not the owner");
        registrar.addOperatorToAllowlist(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_2);

        // Existing allowlist entries still exist
        assertTrue(registrar.isOperatorAllowed(aggregatorOperatorSet, ALLOWLISTED_OPERATOR_1));
    }
}

// Test contract for operator registration with allowlist validation
contract TaskAVSRegistrarBaseUnitTests_OperatorRegistration is TaskAVSRegistrarBaseUnitTests {
    address public constant OPERATOR_1 = address(0x200);
    address public constant OPERATOR_2 = address(0x201);
    address public constant OPERATOR_3 = address(0x202);

    OperatorSet public aggregatorOperatorSet;
    OperatorSet public executorOperatorSet1;
    OperatorSet public executorOperatorSet2;

    function setUp() public override {
        super.setUp();

        aggregatorOperatorSet = OperatorSet({avs: avs, id: AGGREGATOR_OPERATOR_SET_ID});
        executorOperatorSet1 = OperatorSet({avs: avs, id: EXECUTOR_OPERATOR_SET_ID_1});
        executorOperatorSet2 = OperatorSet({avs: avs, id: EXECUTOR_OPERATOR_SET_ID_2});

        // Add operators to allowlist
        vm.prank(owner);
        registrar.addOperatorToAllowlist(aggregatorOperatorSet, OPERATOR_1);
        vm.prank(owner);
        registrar.addOperatorToAllowlist(executorOperatorSet1, OPERATOR_2);
        vm.prank(owner);
        registrar.addOperatorToAllowlist(executorOperatorSet2, OPERATOR_3);
    }

    function test_RegisterOperator_Allowlisted() public {
        // Mock that operator is registered in key registrar
        keyRegistrarMock.setIsRegistered(OPERATOR_1, aggregatorOperatorSet, true);

        // Should not revert when operator is allowlisted
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = AGGREGATOR_OPERATOR_SET_ID;
        bytes memory socketData = abi.encode("http://localhost:8080");
        allocationManagerMock.registerOperator(avs, OPERATOR_1, operatorSetIds, socketData);
    }

    function test_RegisterOperator_NotAllowlisted() public {
        address nonAllowlistedOperator = address(0x300);

        // Mock that operator is registered in key registrar
        keyRegistrarMock.setIsRegistered(nonAllowlistedOperator, aggregatorOperatorSet, true);

        // Should revert when operator is not allowlisted for aggregator operator set
        vm.expectRevert(OperatorNotInAllowlist.selector);
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = AGGREGATOR_OPERATOR_SET_ID;
        bytes memory socketData = abi.encode("http://localhost:8080");
        allocationManagerMock.registerOperator(
            avs, nonAllowlistedOperator, operatorSetIds, socketData
        );
    }

    function test_RegisterOperator_MultipleOperatorSets() public {
        // Mock that operator is registered in both operator sets
        keyRegistrarMock.setIsRegistered(OPERATOR_1, aggregatorOperatorSet, true);
        keyRegistrarMock.setIsRegistered(OPERATOR_1, executorOperatorSet1, true);

        // Only need to add operator to aggregator allowlist (executor sets don't require allowlist)
        // OPERATOR_1 is already in aggregatorOperatorSet allowlist from setup

        // Should not revert when operator is allowlisted for aggregator operator set
        uint32[] memory operatorSetIds = new uint32[](2);
        operatorSetIds[0] = AGGREGATOR_OPERATOR_SET_ID;
        operatorSetIds[1] = EXECUTOR_OPERATOR_SET_ID_1;

        bytes memory socketData = abi.encode("http://localhost:8080");
        allocationManagerMock.registerOperator(avs, OPERATOR_1, operatorSetIds, socketData);
    }

    function test_RegisterOperator_MultipleOperatorSets_PartiallyAllowlisted() public {
        // Mock that operator is registered in both operator sets
        keyRegistrarMock.setIsRegistered(OPERATOR_1, aggregatorOperatorSet, true);
        keyRegistrarMock.setIsRegistered(OPERATOR_1, executorOperatorSet1, true);

        // OPERATOR_1 is already in aggregatorOperatorSet allowlist from setup
        // Note: Executor operator sets don't require allowlist checks

        // Should succeed since aggregator operator set is allowlisted and executor sets don't need allowlist
        uint32[] memory operatorSetIds = new uint32[](2);
        operatorSetIds[0] = AGGREGATOR_OPERATOR_SET_ID;
        operatorSetIds[1] = EXECUTOR_OPERATOR_SET_ID_1;

        bytes memory socketData = abi.encode("http://localhost:8080");
        allocationManagerMock.registerOperator(avs, OPERATOR_1, operatorSetIds, socketData);
    }

    function test_RegisterOperator_AllowlistRemovedAfterRegistration() public {
        // Mock that operator is registered in key registrar
        keyRegistrarMock.setIsRegistered(OPERATOR_1, aggregatorOperatorSet, true);

        // Register operator (should succeed)
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = AGGREGATOR_OPERATOR_SET_ID;
        bytes memory socketData = abi.encode("http://localhost:8080");
        allocationManagerMock.registerOperator(avs, OPERATOR_1, operatorSetIds, socketData);

        // Remove operator from allowlist
        vm.prank(owner);
        registrar.removeOperatorFromAllowlist(aggregatorOperatorSet, OPERATOR_1);

        // Try to register again (should fail)
        vm.expectRevert(OperatorNotInAllowlist.selector);
        uint32[] memory operatorSetIds2 = new uint32[](1);
        operatorSetIds2[0] = AGGREGATOR_OPERATOR_SET_ID;
        bytes memory socketData2 = abi.encode("http://localhost:8080");
        allocationManagerMock.registerOperator(avs, OPERATOR_1, operatorSetIds2, socketData2);
    }

    function test_RegisterOperator_AllowlistAddedAfterFailedRegistration() public {
        address operator = address(0x400);

        // Mock that operator is registered in key registrar
        keyRegistrarMock.setIsRegistered(operator, aggregatorOperatorSet, true);

        // Try to register without being allowlisted (should fail)
        vm.expectRevert(OperatorNotInAllowlist.selector);
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = AGGREGATOR_OPERATOR_SET_ID;
        bytes memory socketData = abi.encode("http://localhost:8080");
        allocationManagerMock.registerOperator(avs, operator, operatorSetIds, socketData);

        // Add operator to allowlist
        vm.prank(owner);
        registrar.addOperatorToAllowlist(aggregatorOperatorSet, operator);

        // Now registration should succeed
        uint32[] memory operatorSetIds3 = new uint32[](1);
        operatorSetIds3[0] = AGGREGATOR_OPERATOR_SET_ID;
        bytes memory socketData3 = abi.encode("http://localhost:8080");
        allocationManagerMock.registerOperator(avs, operator, operatorSetIds3, socketData3);
    }

    function test_RegisterOperator_ZeroAddress() public {
        // Mock that zero address is registered in key registrar
        keyRegistrarMock.setIsRegistered(address(0), aggregatorOperatorSet, true);

        // Add zero address to allowlist
        vm.prank(owner);
        registrar.addOperatorToAllowlist(aggregatorOperatorSet, address(0));

        // Should not revert when zero address is allowlisted
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = AGGREGATOR_OPERATOR_SET_ID;
        bytes memory socketData = abi.encode("http://localhost:8080");
        allocationManagerMock.registerOperator(avs, address(0), operatorSetIds, socketData);
    }

    function test_RegisterOperator_ContractAddress() public {
        address contractAddress = address(registrar);

        // Mock that contract address is registered in key registrar
        keyRegistrarMock.setIsRegistered(contractAddress, aggregatorOperatorSet, true);

        // Add contract address to allowlist
        vm.prank(owner);
        registrar.addOperatorToAllowlist(aggregatorOperatorSet, contractAddress);

        // Should not revert when contract address is allowlisted
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = AGGREGATOR_OPERATOR_SET_ID;
        bytes memory socketData = abi.encode("http://localhost:8080");
        allocationManagerMock.registerOperator(avs, contractAddress, operatorSetIds, socketData);
    }

    function test_RegisterOperator_AllowlistValidationOrder() public {
        // Test that allowlist validation happens before other validations
        address operator = address(0x500);

        // Mock that operator is registered in key registrar
        keyRegistrarMock.setIsRegistered(operator, aggregatorOperatorSet, true);

        // Add operator to allowlist
        vm.prank(owner);
        registrar.addOperatorToAllowlist(aggregatorOperatorSet, operator);

        // Should succeed now that both allowlist and key registrar checks pass
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = AGGREGATOR_OPERATOR_SET_ID;
        bytes memory socketData = abi.encode("http://localhost:8080");
        allocationManagerMock.registerOperator(avs, operator, operatorSetIds, socketData);
    }

    function test_RegisterOperator_ExecutorOperatorSet_NoAllowlistRequired() public {
        // Test that executor operator sets don't require allowlist checks
        address operator = address(0x600);

        // Mock that operator is registered in key registrar for executor operator set
        keyRegistrarMock.setIsRegistered(operator, executorOperatorSet1, true);

        // Operator is NOT in allowlist for executor operator set (and shouldn't need to be)
        // This should succeed since executor operator sets don't require allowlist

        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = EXECUTOR_OPERATOR_SET_ID_1;
        bytes memory socketData = abi.encode("http://localhost:8080");
        allocationManagerMock.registerOperator(avs, operator, operatorSetIds, socketData);
    }

    function test_RegisterOperator_MixedOperatorSets_OnlyAggregatorRequiresAllowlist() public {
        // Test mixed operator sets where only aggregator requires allowlist
        address operator = address(0x700);

        // Mock that operator is registered in key registrar for both operator sets
        keyRegistrarMock.setIsRegistered(operator, aggregatorOperatorSet, true);
        keyRegistrarMock.setIsRegistered(operator, executorOperatorSet1, true);

        // Add operator to aggregator allowlist (required for aggregator operator set)
        vm.prank(owner);
        registrar.addOperatorToAllowlist(aggregatorOperatorSet, operator);

        // Operator is NOT in allowlist for executor operator set (not required)
        // But IS in allowlist for aggregator operator set (required and satisfied)
        // This should succeed since only aggregator requires allowlist

        uint32[] memory operatorSetIds = new uint32[](2);
        operatorSetIds[0] = EXECUTOR_OPERATOR_SET_ID_1; // No allowlist required
        operatorSetIds[1] = AGGREGATOR_OPERATOR_SET_ID; // Allowlist required (and satisfied)

        bytes memory socketData = abi.encode("http://localhost:8080");
        allocationManagerMock.registerOperator(avs, operator, operatorSetIds, socketData);
    }

    function test_RegisterOperator_ExecutorOnly_NoAllowlistCheck() public {
        // Test registration with only executor operator sets (no aggregator)
        address operator = address(0x800);

        // Mock that operator is registered in key registrar for executor operator sets
        keyRegistrarMock.setIsRegistered(operator, executorOperatorSet1, true);
        keyRegistrarMock.setIsRegistered(operator, executorOperatorSet2, true);

        // Operator is NOT in any allowlist (and shouldn't need to be for executor sets)
        // This should succeed since executor operator sets don't require allowlist

        uint32[] memory operatorSetIds = new uint32[](2);
        operatorSetIds[0] = EXECUTOR_OPERATOR_SET_ID_1;
        operatorSetIds[1] = EXECUTOR_OPERATOR_SET_ID_2;
        bytes memory socketData = abi.encode("http://localhost:8080");
        allocationManagerMock.registerOperator(avs, operator, operatorSetIds, socketData);
    }
}
