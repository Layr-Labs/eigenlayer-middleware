// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockEigenLayerDeployer} from "./MockDeployer.sol";
import {IAVSRegistrarErrors, IAVSRegistrarEvents} from "src/interfaces/IAVSRegistrarInternal.sol";
import {AVSRegistrar} from "src/middlewareV2/registrar/AVSRegistrar.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IKeyRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {
    OperatorSet,
    OperatorSetLib
} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {ArrayLib} from "eigenlayer-contracts/src/test/utils/ArrayLib.sol";
import "test/utils/Random.sol";

contract AVSRegistrarImplementation is AVSRegistrar {
    constructor(
        IAllocationManager _allocationManager,
        IKeyRegistrar _keyRegistrar
    ) AVSRegistrar(_allocationManager, _keyRegistrar) {
        _disableInitializers();
    }

    function initialize(
        address _owner
    ) external initializer {
        __AVSRegistrar_init(_owner);
    }
}

abstract contract AVSRegistrarBase is
    MockEigenLayerDeployer,
    IAVSRegistrarErrors,
    IAVSRegistrarEvents
{
    AVSRegistrar internal avsRegistrar;
    AVSRegistrar internal avsRegistrarImplementation;

    address internal constant defaultOperator = address(0x123);
    address internal constant AVS = address(0x456);
    uint32 internal constant defaultOperatorSetId = 0;

    function setUp() public virtual {
        _deployMockEigenLayer();
    }

    function _registerKey(address operator, uint32[] memory operatorSetIds) internal {
        for (uint32 i; i < operatorSetIds.length; ++i) {
            keyRegistrarMock.setIsRegistered(
                operator, OperatorSet({avs: AVS, id: operatorSetIds[i]}), true
            );
        }
    }
}
