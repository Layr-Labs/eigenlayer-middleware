import "AVSRegistrar.spec";
use builtin rule sanity filtered { f -> f.contract == currentContract }
use rule registerOperatorOnlyAllocationManager; 
use rule registerOperatorOnlyValidKeys;
use rule deregisterOperatorOnlyAllocationManager;


/*
 * _initialized > 0 => revert
 *
 * What it means: The initialize function must revert if the contract has already been initialized (_initialized > 0)
 *
 * Why it should hold: The initializer modifier should prevent re-initialization to maintain contract integrity and prevent ownership takeover after deployment
 *
 * Possible consequences: Ownership takeover, allowlist manipulation, complete compromise of access control system
 */
rule initialize_already_initialized_reverts(env e) {
    address admin;
    address avs;

    // assign all the 'before' variables
    uint8 _initialized_before = currentContract._initialized;

    // call function under test
    initialize@withrevert(e, avs, admin);
    bool initialize_reverted = lastReverted;

    // verify integrity
    assert ((_initialized_before > 0) => initialize_reverted), "_initialized > 0 => revert";
}

/*
 * _initialized@after > _initialized@before
 *
 * What it means: After successful initialization, the _initialized state variable must increase from its previous value
 *
 * Why it should hold: The initializer modifier must properly mark the contract as initialized to prevent future re-initialization attempts
 *
 * Possible consequences: Re-initialization vulnerability, ownership takeover, state corruption
 */
rule initialize_sets_initialized_state(env e) {
    address admin;
    address avs;

    // assign all the 'before' variables
    uint8 _initialized_before = currentContract._initialized;

    // call function under test
    initialize(e, avs, admin);

    // assign all the 'after' variables
    uint8 _initialized_after = currentContract._initialized;

    // verify integrity
    assert (_initialized_after > _initialized_before), "_initialized@after > _initialized@before";
}

/*
 * _owner@after == admin
 *
 * What it means: When initialize is called with a  admin address, that address must become the contract owner
 *
 * Why it should hold: The purpose of initialization is to establish proper ownership, and the admin parameter should be set as the owner to enable access control
 *
 * Possible consequences: Broken access control, inability to manage allowlists, contract becomes non-functional
 */
rule initialize_admin_becomes_owner(env e) {
    address admin;
    address avs;

    // call function under test
    initialize(e, avs, admin);

    // assign all the 'after' variables
    address _owner_after = currentContract._owner;

    // verify integrity
    assert (_owner_after == admin), "_owner@after == admin";
}

/*
 * _initializing@before == false && _initializing@after == false
 *
 * What it means: The _initializing flag should be false both before and after the initialize function execution
 *
 * Why it should hold: The initializer modifier should properly manage the _initializing flag to prevent reentrancy during initialization and ensure clean state transitions
 *
 * Possible consequences: Reentrancy attacks during initialization, inconsistent initialization state, potential for multiple simultaneous initializations
 */
rule initialize_initializing_flag_during_execution(env e) {
    address admin;
    address avs;

    // assign all the 'before' variables
    bool _initializing_before = currentContract._initializing;

    // call function under test
    initialize(e, avs, admin);

    // assign all the 'after' variables
    bool _initializing_after = currentContract._initializing;

    // verify integrity
    assert ((_initializing_before == false) && (_initializing_after == false)), "_initializing@before == false && _initializing@after == false";
}