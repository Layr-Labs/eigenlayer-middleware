// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./AVSRegistrarBase.t.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {IPermissionController} from
    "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {PermissionController} from
    "eigenlayer-contracts/src/contracts/permissions/PermissionController.sol";
import {AVSRegistrarAsIdentifier} from
    "src/middlewareV2/registrar/presets/AVSRegistrarAsIdentifier.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract AVSRegistrarAsIdentifierUnitTests is AVSRegistrarBase {
    AVSRegistrarAsIdentifier public avsRegistrarAsIdentifier;
    address public admin = address(0xAD);
    string public constant METADATA_URI = "https://example.com/metadata";

    function setUp() public virtual override {
        super.setUp();

        // Deploy the implementation
        avsRegistrarImplementation = new AVSRegistrarAsIdentifier(
            IAllocationManager(address(allocationManagerMock)),
            permissionController,
            IKeyRegistrar(address(keyRegistrarMock))
        );

        // Deploy the proxy
        avsRegistrarAsIdentifier = AVSRegistrarAsIdentifier(
            address(
                new TransparentUpgradeableProxy(
                    address(avsRegistrarImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        AVSRegistrarAsIdentifier.initialize.selector, AVS, METADATA_URI
                    )
                )
            )
        );
    }
}

contract AVSRegistrarAsIdentifierUnitTests_constructor is AVSRegistrarAsIdentifierUnitTests {
    function test_constructor() public {
        // Deploy a new implementation to test constructor
        AVSRegistrarAsIdentifier impl = new AVSRegistrarAsIdentifier(
            IAllocationManager(address(allocationManagerMock)),
            permissionController,
            IKeyRegistrar(address(keyRegistrarMock))
        );

        // Check that the immutable variables are set correctly
        assertEq(
            address(impl.permissionController()),
            address(permissionController),
            "Constructor: permission controller incorrect"
        );
        assertEq(
            address(impl.allocationManager()),
            address(allocationManagerMock),
            "Constructor: allocation manager incorrect"
        );
        assertEq(
            address(impl.keyRegistrar()),
            address(keyRegistrarMock),
            "Constructor: key registrar incorrect"
        );
    }
}

contract AVSRegistrarAsIdentifierUnitTests_initialize is AVSRegistrarAsIdentifierUnitTests {
    function test_initialize() public {
        avsRegistrarAsIdentifier = AVSRegistrarAsIdentifier(
            address(
                new TransparentUpgradeableProxy(
                    address(avsRegistrarImplementation), address(proxyAdmin), ""
                )
            )
        );

        // Mock the allocationManager calls
        vm.mockCall(
            address(allocationManagerMock),
            abi.encodeWithSelector(
                IAllocationManager.updateAVSMetadataURI.selector,
                address(avsRegistrarAsIdentifier),
                METADATA_URI
            ),
            ""
        );
        vm.mockCall(
            address(allocationManagerMock),
            abi.encodeWithSelector(
                IAllocationManager.setAVSRegistrar.selector,
                address(avsRegistrarAsIdentifier),
                avsRegistrarAsIdentifier
            ),
            ""
        );

        // Mock the permissionController call
        vm.mockCall(
            address(permissionController),
            abi.encodeWithSelector(
                IPermissionController.addPendingAdmin.selector,
                address(avsRegistrarAsIdentifier),
                admin
            ),
            ""
        );

        // Expect the calls to be made
        vm.expectCall(
            address(allocationManagerMock),
            abi.encodeWithSelector(
                IAllocationManager.updateAVSMetadataURI.selector,
                address(avsRegistrarAsIdentifier),
                METADATA_URI
            )
        );
        vm.expectCall(
            address(allocationManagerMock),
            abi.encodeWithSelector(
                IAllocationManager.setAVSRegistrar.selector,
                address(avsRegistrarAsIdentifier),
                avsRegistrarAsIdentifier
            )
        );
        vm.expectCall(
            address(permissionController),
            abi.encodeWithSelector(
                IPermissionController.addPendingAdmin.selector,
                address(avsRegistrarAsIdentifier),
                admin
            )
        );

        // Initialize
        avsRegistrarAsIdentifier.initialize(admin, METADATA_URI);
    }

    function test_revert_alreadyInitialized() public {
        // Initialize first
        vm.mockCall(
            address(allocationManagerMock),
            abi.encodeWithSelector(IAllocationManager.updateAVSMetadataURI.selector),
            ""
        );
        vm.mockCall(
            address(allocationManagerMock),
            abi.encodeWithSelector(IAllocationManager.setAVSRegistrar.selector),
            ""
        );
        vm.mockCall(
            address(permissionController),
            abi.encodeWithSelector(IPermissionController.addPendingAdmin.selector),
            ""
        );

        // avsRegistrarAsIdentifier.initialize(admin, METADATA_URI);

        // Try to initialize again
        vm.expectRevert("Initializable: contract is already initialized");
        avsRegistrarAsIdentifier.initialize(admin, METADATA_URI);
    }
}

contract AVSRegistrarAsIdentifierUnitTests_supportsAVS is AVSRegistrarAsIdentifierUnitTests {
    function test_supportsAVS_true() public {
        // Should return true when checking against itself
        assertTrue(
            avsRegistrarAsIdentifier.supportsAVS(address(avsRegistrarAsIdentifier)),
            "supportsAVS: should return true for self"
        );
    }

    function test_supportsAVS_false() public {
        // Should return false for any other address
        assertFalse(
            avsRegistrarAsIdentifier.supportsAVS(AVS),
            "supportsAVS: should return false for original AVS"
        );
        assertFalse(
            avsRegistrarAsIdentifier.supportsAVS(address(0)),
            "supportsAVS: should return false for zero address"
        );
        assertFalse(
            avsRegistrarAsIdentifier.supportsAVS(address(1)),
            "supportsAVS: should return false for random address"
        );
        assertFalse(
            avsRegistrarAsIdentifier.supportsAVS(admin),
            "supportsAVS: should return false for admin"
        );
    }

    function testFuzz_supportsAVS(
        address randomAddress
    ) public {
        if (randomAddress == address(avsRegistrarAsIdentifier)) {
            assertTrue(
                avsRegistrarAsIdentifier.supportsAVS(randomAddress),
                "supportsAVS: should return true for self"
            );
        } else {
            assertFalse(
                avsRegistrarAsIdentifier.supportsAVS(randomAddress),
                "supportsAVS: should return false for non-self"
            );
        }
    }
}

contract AVSRegistrarAsIdentifierUnitTests_registerOperator is AVSRegistrarAsIdentifierUnitTests {
    using ArrayLib for *;

    function testFuzz_revert_notAllocationManager(
        address notAllocationManager
    ) public filterFuzzedAddressInputs(notAllocationManager) {
        cheats.assume(notAllocationManager != address(allocationManagerMock));

        vm.prank(notAllocationManager);
        vm.expectRevert(NotAllocationManager.selector);
        avsRegistrarAsIdentifier.registerOperator(
            defaultOperator,
            address(avsRegistrarAsIdentifier),
            defaultOperatorSetId.toArrayU32(),
            "0x"
        );
    }

    function test_revert_keyNotRegistered() public {
        // Register operator without key registration
        vm.expectRevert(KeyNotRegistered.selector);
        vm.prank(address(allocationManagerMock));
        avsRegistrarAsIdentifier.registerOperator(
            defaultOperator,
            address(avsRegistrarAsIdentifier),
            defaultOperatorSetId.toArrayU32(),
            "0x"
        );
    }

    function testFuzz_correctness(
        Randomness r
    ) public rand(r) {
        // Generate random operator set ids & register keys
        uint32 numOperatorSetIds = r.Uint32(1, 50);
        uint32[] memory operatorSetIds = r.Uint32Array(numOperatorSetIds, 0, type(uint32).max);

        // Register keys for the operator - Note: using AVS as the avs address in the OperatorSet
        for (uint32 i; i < operatorSetIds.length; ++i) {
            keyRegistrarMock.setIsRegistered(
                defaultOperator,
                OperatorSet({avs: address(avsRegistrarAsIdentifier), id: operatorSetIds[i]}),
                true
            );
        }

        // Register operator
        vm.prank(address(allocationManagerMock));
        vm.expectEmit(true, true, true, true);
        emit OperatorRegistered(defaultOperator, operatorSetIds);
        avsRegistrarAsIdentifier.registerOperator(
            defaultOperator, address(avsRegistrarAsIdentifier), operatorSetIds, "0x"
        );
    }
}

contract AVSRegistrarAsIdentifierUnitTests_deregisterOperator is
    AVSRegistrarAsIdentifierUnitTests
{
    using ArrayLib for *;

    function testFuzz_revert_notAllocationManager(
        address notAllocationManager
    ) public filterFuzzedAddressInputs(notAllocationManager) {
        cheats.assume(notAllocationManager != address(allocationManagerMock));

        vm.prank(notAllocationManager);
        vm.expectRevert(NotAllocationManager.selector);
        avsRegistrarAsIdentifier.deregisterOperator(
            defaultOperator, address(avsRegistrarAsIdentifier), defaultOperatorSetId.toArrayU32()
        );
    }

    function testFuzz_correctness(
        Randomness r
    ) public rand(r) {
        // Generate random operator set ids
        uint32 numOperatorSetIds = r.Uint32(1, 50);
        uint32[] memory operatorSetIds = r.Uint32Array(numOperatorSetIds, 0, type(uint32).max);

        // Deregister operator
        vm.expectEmit(true, true, true, true);
        emit OperatorDeregistered(defaultOperator, operatorSetIds);
        vm.prank(address(allocationManagerMock));
        avsRegistrarAsIdentifier.deregisterOperator(
            defaultOperator, address(avsRegistrarAsIdentifier), operatorSetIds
        );
    }
}
