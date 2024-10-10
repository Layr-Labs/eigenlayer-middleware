// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "../../src/unaudited/ECDSAServiceManagerBase.sol";
import {IAllocationManagerTypes} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

contract ECDSAServiceManagerMock is ECDSAServiceManagerBase {
    constructor(
        address _avsDirectory,
        address _stakeRegistry,
        address _rewardsCoordinator,
        address _delegationManager
    )
        ECDSAServiceManagerBase(
            _avsDirectory,
            _stakeRegistry,
            _rewardsCoordinator,
            _delegationManager
        )
    {}

    function initialize(
        address initialOwner,
        address rewardsInitiator
    ) public virtual initializer {
        __ServiceManagerBase_init(initialOwner, rewardsInitiator);
    }

    function createOperatorSets(uint32[] memory) external {}

    function registerOperatorToOperatorSets(
        address operator,
        uint32[] calldata operatorSetIds,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external {}

    function deregisterOperatorFromOperatorSets(address operator, uint32[] calldata operatorSetIds) external{}

    function slashOperator(IAllocationManagerTypes.SlashingParams memory params) external override {
        // Mock implementation - no actual slashing occurs
    }
}
