// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import {EjectionManager} from "../../src/EjectionManager.sol";
import {IEjectionManager} from "../../src/interfaces/IEjectionManager.sol";

import "../utils/MockAVSDeployer.sol";

contract EjectionManagerUnitTests is MockAVSDeployer {

    event EjectorUpdated(address ejector, bool status);
    event QuorumEjectionParamsSet(uint8 quorumNumber, uint32 rateLimitWindow, uint16 ejectableStakePercent);
    event OperatorEjected(bytes32 operatorId, uint8 quorumNumber);
    event FailedOperatorEjection(bytes32 operatorId, uint8 quorumNumber, bytes err);

    EjectionManager public ejectionManager;
    IEjectionManager public ejectionManagerImplementation;

    IEjectionManager.QuorumEjectionParams[] public quorumEjectionParams;

    uint32 public ratelimitWindow = 1 days;
    uint16 public ejectableStakePercent = 1000;

    function setUp() virtual public {
        for(uint8 i = 0; i < numQuorums; i++) {
            quorumEjectionParams.push(IEjectionManager.QuorumEjectionParams({
                rateLimitWindow: ratelimitWindow,
                ejectableStakePercent: ejectableStakePercent
            }));
        }

        defaultMaxOperatorCount = 200;
        _deployMockEigenLayerAndAVS();

        ejectionManager = EjectionManager(address(
            new TransparentUpgradeableProxy(
                address(emptyContract),
                address(proxyAdmin),
                ""
            )
        ));

        ejectionManagerImplementation = new EjectionManager(registryCoordinator, stakeRegistry);

        address[] memory ejectors = new address[](1);
        ejectors[0] = ejector;

        cheats.prank(proxyAdminOwner);
        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(ejectionManager))),
            address(ejectionManagerImplementation),
            abi.encodeWithSelector(
                EjectionManager.initialize.selector,
                registryCoordinatorOwner,
                ejectors,
                quorumEjectionParams
            )
        );

        cheats.prank(registryCoordinatorOwner);
        registryCoordinator.setEjector(address(ejectionManager));

        cheats.warp(block.timestamp + ratelimitWindow);
    }

    function testEjectOperators_OneOperatorInsideRatelimit() public {
        uint8 operatorsToEject = 1;
        uint8 numOperators = 10;
        uint96 stake = 1 ether;
        _registerOperaters(numOperators, stake);

        bytes32[][] memory operatorIds = new bytes32[][](numQuorums);
        for (uint8 i = 0; i < numQuorums; i++) {
            operatorIds[i] = new bytes32[](operatorsToEject);
            for (uint j = 0; j < operatorsToEject; j++) {
                operatorIds[i][j] = registryCoordinator.getOperatorId(_incrementAddress(defaultOperator, j));
            }
        }

        assertEq(uint8(registryCoordinator.getOperatorStatus(defaultOperator)), uint8(IRegistryCoordinator.OperatorStatus.REGISTERED));

        for(uint8 i = 0; i < numQuorums; i++) {
            for(uint8 j = 0; j < operatorsToEject; j++) {
                cheats.expectEmit(true, true, true, true, address(ejectionManager));
                emit OperatorEjected(operatorIds[i][j], i);
            }
        }

        cheats.prank(ejector);
        ejectionManager.ejectOperators(operatorIds);

        assertEq(uint8(registryCoordinator.getOperatorStatus(defaultOperator)), uint8(IRegistryCoordinator.OperatorStatus.DEREGISTERED));
    }

    function testEjectOperators_MultipleOperatorInsideRatelimit() public {
        uint8 operatorsToEject = 10;
        uint8 numOperators = 100;
        uint96 stake = 1 ether;
        _registerOperaters(numOperators, stake);

        bytes32[][] memory operatorIds = new bytes32[][](numQuorums);
        for (uint8 i = 0; i < numQuorums; i++) {
            operatorIds[i] = new bytes32[](operatorsToEject);
            for (uint j = 0; j < operatorsToEject; j++) {
                operatorIds[i][j] = registryCoordinator.getOperatorId(_incrementAddress(defaultOperator, j));
            }
        }

        for(uint8 i = 0; i < operatorsToEject; i++) {
            assertEq(uint8(registryCoordinator.getOperatorStatus(_incrementAddress(defaultOperator, i))), uint8(IRegistryCoordinator.OperatorStatus.REGISTERED));
        }

        for(uint8 i = 0; i < numQuorums; i++) {
            for(uint8 j = 0; j < operatorsToEject; j++) {
                cheats.expectEmit(true, true, true, true, address(ejectionManager));
                emit OperatorEjected(operatorIds[i][j], i);
            }
        }

        cheats.prank(ejector);
        ejectionManager.ejectOperators(operatorIds);

        for(uint8 i = 0; i < operatorsToEject; i++) {
            assertEq(uint8(registryCoordinator.getOperatorStatus(_incrementAddress(defaultOperator, i))), uint8(IRegistryCoordinator.OperatorStatus.DEREGISTERED));
        }
    }

    function testEjectOperators_MultipleOperatorOutsideRatelimit() public {
        uint8 operatorsCanEject = 1;
        uint8 operatorsToEject = 10;
        uint8 numOperators = 10;
        uint96 stake = 1 ether;
        _registerOperaters(numOperators, stake);

        bytes32[][] memory operatorIds = new bytes32[][](numQuorums);
        for (uint8 i = 0; i < numQuorums; i++) {
            operatorIds[i] = new bytes32[](operatorsToEject);
            for (uint j = 0; j < operatorsToEject; j++) {
                operatorIds[i][j] = registryCoordinator.getOperatorId(_incrementAddress(defaultOperator, j));
            }
        }

        for(uint8 i = 0; i < operatorsToEject; i++) {
            assertEq(uint8(registryCoordinator.getOperatorStatus(_incrementAddress(defaultOperator, i))), uint8(IRegistryCoordinator.OperatorStatus.REGISTERED));
        }

        for(uint8 i = 0; i < numQuorums; i++) {
            for(uint8 j = 0; j < operatorsCanEject; j++) {
                cheats.expectEmit(true, true, true, true, address(ejectionManager));
                emit OperatorEjected(operatorIds[i][j], i);
            }
        }

        cheats.prank(ejector);
        ejectionManager.ejectOperators(operatorIds);

        for(uint8 i = 0; i < operatorsCanEject; i++) {
            assertEq(uint8(registryCoordinator.getOperatorStatus(_incrementAddress(defaultOperator, i))), uint8(IRegistryCoordinator.OperatorStatus.DEREGISTERED));
        }

        for(uint8 i = operatorsCanEject; i < operatorsToEject; i++) {
            assertEq(uint8(registryCoordinator.getOperatorStatus(_incrementAddress(defaultOperator, i))), uint8(IRegistryCoordinator.OperatorStatus.REGISTERED));
        }
    }

    function testEjectOperators_MultipleOperatorMultipleTimesInsideRatelimit() public {
        uint8 operatorsToEject = 4;
        uint8 numOperators = 100;
        uint96 stake = 1 ether;
        _registerOperaters(numOperators, stake);

        bytes32[][] memory operatorIds = new bytes32[][](numQuorums);
        for (uint8 i = 0; i < numQuorums; i++) {
            operatorIds[i] = new bytes32[](operatorsToEject);
            for (uint j = 0; j < operatorsToEject; j++) {
                operatorIds[i][j] = registryCoordinator.getOperatorId(_incrementAddress(defaultOperator, j));
            }
        }

        for(uint8 i = 0; i < operatorsToEject; i++) {
            assertEq(uint8(registryCoordinator.getOperatorStatus(_incrementAddress(defaultOperator, i))), uint8(IRegistryCoordinator.OperatorStatus.REGISTERED));
        }

        for(uint8 i = 0; i < numQuorums; i++) {
            for(uint8 j = 0; j < operatorsToEject; j++) {
                cheats.expectEmit(true, true, true, true, address(ejectionManager));
                emit OperatorEjected(operatorIds[i][j], i);
            }
        }

        cheats.prank(ejector);
        ejectionManager.ejectOperators(operatorIds);

        for(uint8 i = 0; i < operatorsToEject; i++) {
            assertEq(uint8(registryCoordinator.getOperatorStatus(_incrementAddress(defaultOperator, i))), uint8(IRegistryCoordinator.OperatorStatus.DEREGISTERED));
        }

        cheats.warp(block.timestamp + (ratelimitWindow / 2));

        operatorIds = new bytes32[][](numQuorums);
        for (uint8 i = 0; i < numQuorums; i++) {
            operatorIds[i] = new bytes32[](operatorsToEject);
            for (uint j = 0; j < operatorsToEject; j++) {
                operatorIds[i][j] = registryCoordinator.getOperatorId(_incrementAddress(defaultOperator, operatorsToEject + j));
            }
        }

        for(uint8 i = 0; i < operatorsToEject; i++) {
            assertEq(uint8(registryCoordinator.getOperatorStatus(_incrementAddress(defaultOperator, operatorsToEject + i))), uint8(IRegistryCoordinator.OperatorStatus.REGISTERED));
        }

        for(uint8 i = 0; i < numQuorums; i++) {
            for(uint8 j = 0; j < operatorsToEject; j++) {
                cheats.expectEmit(true, true, true, true, address(ejectionManager));
                emit OperatorEjected(operatorIds[i][j], i);
            }
        }

        cheats.prank(ejector);
        ejectionManager.ejectOperators(operatorIds);

        for(uint8 i = 0; i < operatorsToEject; i++) {
            assertEq(uint8(registryCoordinator.getOperatorStatus(_incrementAddress(defaultOperator, operatorsToEject + i))), uint8(IRegistryCoordinator.OperatorStatus.DEREGISTERED));
        }
    }

    function testEjectOperators_MultipleOperatorAfterRatelimitReset() public {
        uint8 operatorsToEject = 10;
        uint8 numOperators = 100;
        uint96 stake = 1 ether;

        testEjectOperators_MultipleOperatorInsideRatelimit();

        vm.warp(block.timestamp + 1);

        _registerOperaters(operatorsToEject, stake);

        vm.warp(block.timestamp + ratelimitWindow);

        bytes32[][] memory operatorIds = new bytes32[][](numQuorums);
        for (uint8 i = 0; i < numQuorums; i++) {
            operatorIds[i] = new bytes32[](operatorsToEject);
            for (uint j = 0; j < operatorsToEject; j++) {
                operatorIds[i][j] = registryCoordinator.getOperatorId(_incrementAddress(defaultOperator, j));
            }
        }

        for(uint8 i = 0; i < operatorsToEject; i++) {
            assertEq(uint8(registryCoordinator.getOperatorStatus(_incrementAddress(defaultOperator, i))), uint8(IRegistryCoordinator.OperatorStatus.REGISTERED));
        }

        for(uint8 i = 0; i < numQuorums; i++) {
            for(uint8 j = 0; j < operatorsToEject; j++) {
                cheats.expectEmit(true, true, true, true, address(ejectionManager));
                emit OperatorEjected(operatorIds[i][j], i);
            }
        }

        cheats.prank(ejector);
        ejectionManager.ejectOperators(operatorIds);

        for(uint8 i = 0; i < operatorsToEject; i++) {
            assertEq(uint8(registryCoordinator.getOperatorStatus(_incrementAddress(defaultOperator, i))), uint8(IRegistryCoordinator.OperatorStatus.DEREGISTERED));
        }
    }

    function testEjectOperators_NoRatelimitForOwner() public {
        uint8 operatorsToEject = 100;
        uint8 numOperators = 100;
        uint96 stake = 1 ether;
        _registerOperaters(numOperators, stake);

        bytes32[][] memory operatorIds = new bytes32[][](numQuorums);
        for (uint8 i = 0; i < numQuorums; i++) {
            operatorIds[i] = new bytes32[](operatorsToEject);
            for (uint j = 0; j < operatorsToEject; j++) {
                operatorIds[i][j] = registryCoordinator.getOperatorId(_incrementAddress(defaultOperator, j));
            }
        }

        for(uint8 i = 0; i < operatorsToEject; i++) {
            assertEq(uint8(registryCoordinator.getOperatorStatus(_incrementAddress(defaultOperator, i))), uint8(IRegistryCoordinator.OperatorStatus.REGISTERED));
        }

        for(uint8 i = 0; i < numQuorums; i++) {
            for(uint8 j = 0; j < operatorsToEject; j++) {
                cheats.expectEmit(true, true, true, true, address(ejectionManager));
                emit OperatorEjected(operatorIds[i][j], i);
            }
        }

        cheats.prank(registryCoordinatorOwner);
        ejectionManager.ejectOperators(operatorIds);

        for(uint8 i = 0; i < operatorsToEject; i++) {
            assertEq(uint8(registryCoordinator.getOperatorStatus(_incrementAddress(defaultOperator, i))), uint8(IRegistryCoordinator.OperatorStatus.DEREGISTERED));
        }
    }

    function testEjectOperators_NoRevertOnMissedEjection() public {
        uint8 operatorsToEject = 10;
        uint8 numOperators = 100;
        uint96 stake = 1 ether;
        _registerOperaters(numOperators, stake);

        bytes32[][] memory operatorIds = new bytes32[][](numQuorums);
        for (uint8 i = 0; i < numQuorums; i++) {
            operatorIds[i] = new bytes32[](operatorsToEject);
            for (uint j = 0; j < operatorsToEject; j++) {
                operatorIds[i][j] = registryCoordinator.getOperatorId(_incrementAddress(defaultOperator, j));
            }
        }

        cheats.prank(defaultOperator);
        registryCoordinator.deregisterOperator(BitmapUtils.bitmapToBytesArray(MAX_QUORUM_BITMAP));

        for(uint8 i = 1; i < operatorsToEject; i++) {
            assertEq(uint8(registryCoordinator.getOperatorStatus(_incrementAddress(defaultOperator, i))), uint8(IRegistryCoordinator.OperatorStatus.REGISTERED));
        }

        for(uint8 i = 0; i < numQuorums; i++) {
            for(uint8 j = 1; j < operatorsToEject; j++) {
                cheats.expectEmit(true, true, true, true, address(ejectionManager));
                emit OperatorEjected(operatorIds[i][j], i);
            }
        }

        cheats.prank(ejector);
        ejectionManager.ejectOperators(operatorIds);

        for(uint8 i = 0; i < operatorsToEject; i++) {
            assertEq(uint8(registryCoordinator.getOperatorStatus(_incrementAddress(defaultOperator, i))), uint8(IRegistryCoordinator.OperatorStatus.DEREGISTERED));
        }
    }

    function testSetQuorumEjectionParams() public {
        uint8 quorumNumber = 0;
        ratelimitWindow = 2 days;
        ejectableStakePercent = 2000;
        IEjectionManager.QuorumEjectionParams memory _quorumEjectionParams = IEjectionManager.QuorumEjectionParams({
            rateLimitWindow: ratelimitWindow,
            ejectableStakePercent: ejectableStakePercent
        });

        cheats.expectEmit(true, true, true, true, address(ejectionManager));
        emit QuorumEjectionParamsSet(quorumNumber, ratelimitWindow, ejectableStakePercent);

        cheats.prank(registryCoordinatorOwner);
        ejectionManager.setQuorumEjectionParams(quorumNumber, _quorumEjectionParams);

        (uint32 setRatelimitWindow, uint16 setEjectableStakePercent) = ejectionManager.quorumEjectionParams(quorumNumber);
        assertEq(setRatelimitWindow, _quorumEjectionParams.rateLimitWindow);
        assertEq(setEjectableStakePercent, _quorumEjectionParams.ejectableStakePercent);
    }

    function testSetEjector() public {
        cheats.expectEmit(true, true, true, true, address(ejectionManager));
        emit EjectorUpdated(address(0), true);

        cheats.prank(registryCoordinatorOwner);
        ejectionManager.setEjector(address(0), true);

        assertEq(ejectionManager.isEjector(address(0)), true);
    }

    function test_Revert_NotPermissioned() public {
        bytes32[][] memory operatorIds;
        cheats.expectRevert("Ejector: Only owner or ejector can eject");
        ejectionManager.ejectOperators(operatorIds);

        EjectionManager.QuorumEjectionParams memory _quorumEjectionParams;
        cheats.expectRevert("Ownable: caller is not the owner");
        ejectionManager.setQuorumEjectionParams(0, _quorumEjectionParams);

        cheats.expectRevert("Ownable: caller is not the owner");
        ejectionManager.setEjector(address(0), true);
    }

    function test_Overflow_Regression() public {
        cheats.prank(registryCoordinatorOwner);
        ejectionManager.setQuorumEjectionParams(0, IEjectionManager.QuorumEjectionParams({
            rateLimitWindow: 7 days,
            ejectableStakePercent: 9999
        }));

        stakeRegistry.recordTotalStakeUpdate(1, 2_000_000_000 * 1 ether);

        ejectionManager.amountEjectableForQuorum(1);
    }

    function _registerOperaters(uint8 numOperators, uint96 stake) internal {
        for (uint i = 0; i < numOperators; i++) {
            BN254.G1Point memory pubKey = BN254.hashToG1(keccak256(abi.encodePacked(i)));
            address operator = _incrementAddress(defaultOperator, i);
            _registerOperatorWithCoordinator(operator, MAX_QUORUM_BITMAP, pubKey, stake);
        }
    }
}
