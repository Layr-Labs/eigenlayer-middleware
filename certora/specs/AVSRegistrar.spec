use builtin rule sanity filtered { f -> f.contract == currentContract }

methods{
    // function _.getBN254Key(KeyRegistrar.OperatorSet, address) external => DISPATCHER(true);
    // function _.merkleizeKeccak(bytes32[] memory) internal => NONDET;
    // function _getOperatorWeights(BN254TableCalculator.OperatorSet calldata) internal returns (address[] memory, uint256[][] memory) => returnEmptyWeights();

}

/*
 * msg.sender != address(allocationManager) => revert
 *
 * What it means: 
 * The registerOperator function can only be called by the AllocationManager contract address, and any call from a different address must revert.
 * 
 * Why it should hold: The function has the onlyAllocationManager modifier which enforces this access control. This is a critical security boundary that ensures only the authorized AllocationManager can register operators for the AVS. 
 *
 * Possible consequences: Unauthorized operator registration, bypassing of allocation management logic, potential manipulation of operator sets, and violation of the intended protocol governance structure. 
 */
rule registerOperatorOnlyAllocationManager(env e) {
    address operator;
    uint32[] operatorSetIds;
    bytes data;

    // call function under test
    registerOperator@withrevert(e, operator, _, operatorSetIds, data);
    bool registerOperator_reverted = lastReverted;

    // verify integrity
    assert ((e.msg.sender != currentContract.allocationManager) => registerOperator_reverted), "msg.sender != address(allocationManager) => revert";
}

rule registerOperatorOnlyValidKeys(env e) {
    address operator;
    uint32[] operatorSetIds;
    bytes data;

    KeyRegistrar.OperatorSet operatorSet;
    require operatorSetIds.length > 0, "assume non empty operator set list, an empty list does not cause a revert";
    require operatorSet.avs == currentContract.avs;
    require operatorSet.id == operatorSetIds[0];

    bool keyRegistered = currentContract.keyRegistrar.isRegistered(e, operatorSet, operator);

    // call function under test
    registerOperator@withrevert(e, operator, _, operatorSetIds, data);
    bool registerOperator_reverted = lastReverted;

    // verify integrity
    assert (!keyRegistered => registerOperator_reverted), "operator key not valid";
}

/*
 * msg.sender != address(allocationManager) => revert
 *
 * What it means: Only the allocation manager contract can call the deregisterOperator function, any other caller should cause a revert
 *
 * Why it should hold: The function has the onlyAllocationManager modifier which enforces access control. This is a critical security boundary that ensures only the authorized allocation manager can deregister operators. The zero address is not a valid operator address and deregistering it would be a meaningless operation. This prevents invalid input and follows standard Ethereum patterns of rejecting zero addresses
 *
 * Possible consequences: Unauthorized deregistration of operators, disruption of AVS operations, potential griefing attacks where malicious actors can remove legitimate operators. Invalid state transitions, confusion in operator tracking, potential issues with downstream systems that assume valid operator addresses
 */
rule deregisterOperatorOnlyAllocationManager(env e) {
    address operator;
    uint32[] operatorSetIds;

    // call function under test
    deregisterOperator@withrevert(e, operator, _, operatorSetIds);
    bool deregisterOperator_reverted = lastReverted;

    // verify integrity
    assert ((e.msg.sender != currentContract.allocationManager) => deregisterOperator_reverted), "msg.sender != address(allocationManager) => revert";
}
