// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "eigenlayer-contracts/src/contracts/interfaces/IStakeRootCompendium.sol";
import "../../src/unaudited/ECDSAServiceManagerBase.sol";

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

    function createOperatorSets(
        uint32[] memory operatorSetIds, 
        uint256[] memory amountToFund, 
        IStakeRootCompendium.StrategyAndMultiplier[][] memory strategiesAndMultipliers
    ) external {}

    function migrationFinalized() external view returns (bool) {}

    function registerOperatorToOperatorSets(
        address operator,
        uint32[] calldata operatorSetIds,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external {}

    function deregisterOperatorFromOperatorSets(address operator, uint32[] calldata operatorSetIds) external{}
}
