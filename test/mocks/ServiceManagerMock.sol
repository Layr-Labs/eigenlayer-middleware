// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "../../src/ServiceManagerBase.sol";

contract ServiceManagerMock is ServiceManagerBase {
    constructor(
        IAVSDirectory _avsDirectory,
        IRewardsCoordinator _rewardsCoordinator,
        IRegistryCoordinator _registryCoordinator,
        IStakeRegistry _stakeRegistry
    )
        ServiceManagerBase(
            _avsDirectory,
            _rewardsCoordinator,
            _registryCoordinator,
            _stakeRegistry
        )
    {}

    function initialize(
        address initialOwner,
        address rewardsInitiator
    ) public virtual initializer {
        __ServiceManagerBase_init(initialOwner, rewardsInitiator);
    }

    function deregisterOperatorFromOperatorSets(
        address operator,
        uint32[] calldata operatorSetIds
    ) external override {}

    function registerOperatorToOperatorSets(
        address operator,
        uint32[] calldata operatorSetIds,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external override {}

    function updateStandbyParams(
        address operator,
        IAVSDirectory.StandbyParam[] calldata standbyParams,
        ISignatureUtils.SignatureWithSaltAndExpiry calldata operatorSignature
    ) external {}
}
