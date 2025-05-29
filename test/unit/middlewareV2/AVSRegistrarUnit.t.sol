// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockEigenLayerDeployer} from "./MockDeployer.sol";
import {IAVSRegistrarErrors, IAVSRegistrarEvents} from "src/interfaces/IAVSRegistrarInternal.sol";
import {AVSRegistrar} from "src/middlewareV2/registrar/AVSRegistrar.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IKeyRegistrar} from "src/interfaces/IKeyRegistrar.sol";
import {
    OperatorSet,
    OperatorSetLib
} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {ArrayLib} from "eigenlayer-contracts/src/test/utils/ArrayLib.sol";
import "test/utils/Random.sol";

contract AVSRegistrarUnitTests is
    MockEigenLayerDeployer,
    IAVSRegistrarErrors,
    IAVSRegistrarEvents
{
    AVSRegistrar internal avsRegistrarImplementation;
    AVSRegistrar internal avsRegistrar;

    address internal constant defaultOperator = address(0x123);
    address internal constant AVS = address(0x456);
    uint32 internal constant defaultOperatorSetId = 0;

    function setUp() public {
        _deployMockEigenLayer();

        // Deploy the AVSRegistrar
        avsRegistrarImplementation = new AVSRegistrar(
            AVS,
            IAllocationManager(address(allocationManagerMock)),
            IKeyRegistrar(address(keyRegistrarMock))
        );

        avsRegistrar = AVSRegistrar(
            address(
                new TransparentUpgradeableProxy(
                    address(avsRegistrarImplementation), address(proxyAdmin), ""
                )
            )
        );
    }

    function _registerKey(address operator, uint32[] memory operatorSetIds) internal {
        for (uint32 i; i < operatorSetIds.length; ++i) {
            keyRegistrarMock.setIsRegistered(
                operator, OperatorSet({avs: AVS, id: operatorSetIds[i]}), true
            );
        }
    }
}

contract AVSRegistrarUnitTests_RegisterOperator is AVSRegistrarUnitTests {
    using ArrayLib for *;

    function testFuzz_revert_notAllocationManager(
        address notAllocationManager
    ) public {
        cheats.assume(notAllocationManager != address(allocationManagerMock));

        cheats.prank(notAllocationManager);
        cheats.expectRevert(NotAllocationManager.selector);
        avsRegistrar.registerOperator(defaultOperator, AVS, defaultOperatorSetId.toArrayU32(), "0x");
    }

    function test_revert_keyNotRegistered() public {
        cheats.expectRevert(KeyNotRegistered.selector);
        cheats.prank(address(allocationManagerMock));
        avsRegistrar.registerOperator(defaultOperator, AVS, defaultOperatorSetId.toArrayU32(), "0x");
    }

    function testFuzz_correctness(
        Randomness r
    ) public rand(r) {
        // Generate random operator set ids & register keys
        uint32 numOperatorSetIds = r.Uint32(1, 50);
        uint32[] memory operatorSetIds = r.Uint32Array(numOperatorSetIds, 0, type(uint32).max);
        _registerKey(defaultOperator, operatorSetIds);

        // Register operator
        cheats.expectEmit(true, true, true, true);
        emit OperatorRegistered(defaultOperator, operatorSetIds);
        cheats.prank(address(allocationManagerMock));
        avsRegistrar.registerOperator(defaultOperator, AVS, operatorSetIds, "0x");
    }
}

contract AVSRegistrarUnitTests_DeregisterOperator is AVSRegistrarUnitTests {
    using ArrayLib for *;

    function testFuzz_revert_notAllocationManager(
        address notAllocationManager
    ) public {
        cheats.assume(notAllocationManager != address(allocationManagerMock));

        cheats.prank(notAllocationManager);
        cheats.expectRevert(NotAllocationManager.selector);
        avsRegistrar.deregisterOperator(defaultOperator, AVS, defaultOperatorSetId.toArrayU32());
    }

    function testFuzz_correctness(
        Randomness r
    ) public rand(r) {
        // Generate random operator set ids
        uint32 numOperatorSetIds = r.Uint32(1, 50);
        uint32[] memory operatorSetIds = r.Uint32Array(numOperatorSetIds, 0, type(uint32).max);

        // Deregister operator
        cheats.expectEmit(true, true, true, true);
        emit OperatorDeregistered(defaultOperator, operatorSetIds);
        cheats.prank(address(allocationManagerMock));
        avsRegistrar.deregisterOperator(defaultOperator, AVS, operatorSetIds);
    }
}
