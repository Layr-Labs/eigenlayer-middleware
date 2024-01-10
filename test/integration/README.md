## EigenLayer Middleware Integration Testing

This folder contains the integration framework and tests for Eigenlayer middleware, which orchestrates the deployment of both Eigenlayer core and middleware contracts to fuzz high-level user flows across a variety of user types, asset types, and quorum configurations.

**Contents**:
* [About the Tests](#about-the-tests)
* [About User Objects and Snapshots](#about-user-objects-and-snapshots)
    * [Snapshots](#snapshots)
    * [User_AltMethods](#user_altmethods)
* [Debugging Tests](#debugging-tests)
* [Configuring Fuzzing](#configuring-fuzzing)

#### About the Tests

Tests are in files located in `/tests`. Generally, each contract has one top-level user flow or concept, with individual tests implementing variants on that flow.

Looking at the current tests is a good place to start.

#### About User Objects and Snapshots

In tests, user actions are carried out via instances of the `User` contract, which holds a variety of methods that allow direct interaction with the middleware contracts. When a `User` is generated, a new `User` (or `User_AltMethods`, depending on config) contract is deployed, which can be used to carry out operations like registering/deregistering for quorums, queuing a withdrawal in the core contracts, etc.

When a new `User` is created (via `IntegrationConfig._newRandomOperator`), a few things happen:
* The `User` is given a BLS keypair to sign with
* For every existing strategy, the `User` is minted a random token balance (between `MIN_BALANCE` and `MAX_BALANCE`)
    * These values are guaranteed not to cause overflow, and also to cause the `User` to meet the minimum stake required for all quorums
* The `User` registers as an operator in Eigenlayer core, and deposits all assets into the `StrategyManager`.

*Note*: This framework pregenerates some BLS keypairs for Users, which is a slow process because it uses FFI. If you find yourself needing more keypairs during tests, check out `IntegrationConfig.constructor` and tweak the values there -- but be warned, this will slow your tests!

##### Snapshots

Every time a `User` method is called, the `User.createSnapshot` modifier takes a snapshot of the global chain state before the action is carried out. This is leveraged within specific assertions to easily query and compare chain states before and after a `User` method. For example, a lot of tests look similar to this:

```solidity
function testFuzz_someFlow(uint24 _random) public {
    /// config and other things
    /// ...

    User operator = _newRandomOperator();

    // 1. Register for all quorums
    operator.registerOperator(allQuorums);        // prior state gets snapshotted here
    check_Register_State(operator, allQuorums);   // this method will check current vs prior state
}
```

Within `check_Register_State`, you'll see certain methods containing the word "Snap" that compare prior states to current states. For example:

```solidity
function check_Register_State(
    User operator,
    bytes memory quorums
) internal {
    _log("check_Register_State", operator);

    /// other checks
    /// ...

    // This method:
    // - fetches the operator's current quorum bitmap
    // - uses the most recent snapshot to fetch their prior quorum bitmap
    // - compares these against each other to validate that all quorums were added
    assert_Snap_Registered_ForQuorums(operator, quorums,
        "operator did not register for all quorums");
```

##### User_AltMethods

`User_AltMethods` is an alternative variant of `User` with a few minor differences:
* `User_AltMethods.createSnapshot`: in addition to taking a global state snapshot before each method, `User_AltMethods` ALSO rolls the current block number forward by 1 block. 
* `User_AltMethods.deregisterOperator(quorums)`: rather than calling `registryCoordinator.deregisterOperator`, this pranks a call from the ejector and calls `registryCoordinator.ejectOperator` instead, since these methods should be pretty much equivalent.
* `User_AltMethods.updateStakes`: rather than calling `registryCoordinator.updateOperators`, `User_AltMethods` will call `registryCoordinator.updateOperatorsForQuorum`.

#### Debugging Tests

Foundry's test failures leave much to be desired -- I've noticed especially with complex tests that it can be hard to figure out what triggered a test failure. The culprit appears to be a weird Foundry behavior that allows a test to continue running even after assertions are triggered. I'm not sure what causes this, but: *don't blindly trust Foundry's output for failing tests*!

To help with debugging tests, I've implemented a ton of human-readable logging that should help you quickly walk through the events of a test and figure out where the first assertion was triggered. The easiest thing to do is to re-run any failing tests with verbose logging turned on, and inspect the output. 

All `User` methods are automatically logged, and many of the more complex internal functions / important state changes are logged for clarity.

Here's an example of what that looks like:

```
alex-pc$ forge test --match-test testFuzz_churnAll_deregisterAll_reregisterAll -vvvv
Running 1 test for test/integration/tests/Full_Register_Deregister.t.sol:Integration_Full_Register_Deregister
[FAIL. Reason: revert: Hello; counterexample: calldata=0x2deac5e50000000000000000000000000000000000000000000000000000000000000000 args=[0]] testFuzz_churnAll_deregisterAll_reregisterAll(uint24) (runs: 0, μ: 0, ~: 0)
Logs:
  _randUser: Created user: Operator2
  _dealRandTokens: dealing assets to: Operator2
  Operator2.registerAsOperator (core)
  Operator2.depositIntoEigenLayer (core)
  _getChurnTargets: incoming operator: Operator2
  _getChurnTargets: churnQuorums: [0]
  _getChurnTargets: standardQuorums: []
  _getChurnTargets: making room by removing operators from quorums: []
  Error: _getChurnTargets: non-full quorum cannot be churned
  Error: Assertion Failed
  _getChurnTargets: selected churn target for quorum 0: Operator1_Alt
  _dealMaxTokens: dealing assets to: Operator2
  Operator2.depositIntoEigenLayer (core)
  - check_Never_Registered(Operator2)
  Operator2.registerOperatorWithChurn
  - standardQuorums: []
  - churnQuorums: [0]
  - churnTargets: [Operator1_Alt]
  - check_Churned_State(Operator2)
  Error: operator pubkey should have been added and churned operator pubkeys should have been removed from apks
  Error: a == b not satisfied [uint]
        Left: 2582841356496569783701107773744347400602274420730358719910718097198309395114
       Right: 10822086612829857808151829430341754119262204537621155540191069406696407943166
  Error: operator pubkey should have been added and churned operator pubkeys should have been removed from apks
  Error: a == b not satisfied [uint]
        Left: 13247024643142095460619063135556783356345434798583216080148658194941536279140
       Right: 13770989844474892507527416045106729498410917265852017889139336639541758415479
  Error: failed to add operator weight and remove churned weight from each quorum
  Error: a == b not satisfied [uint]
        Left: 1021270404
       Right: 1013316117

```

Notice how Foundry doesn't stop after one failed assertion - it keeps going for some reason! But using the logs, we can tell that an assertion in `_getChurnTargets` was responsible, because that's the first error shown in the output.

#### Configuring Fuzzing

Fuzzing is configured via the `_configRand` method called at the start of each test, which accepts bitmaps for the config arguments you want to pass in. This configuration affects the types of quorums generated at the start of each test, as well as the types of users generated during each test.

Here's an example config (with ALL flags set):

```solidity
function testFuzz_someFlow(uint24 _random) public {   
    _configRand({
        _randomSeed: _random,
        _userTypes: DEFAULT | ALT_METHODS,
        _quorumConfig: QuorumConfig({
            numQuorums: ONE | TWO | MANY,
            numStrategies: ONE | TWO | MANY,
            minimumStake: NO_MINIMUM | HAS_MINIMUM,
            fillTypes: EMPTY | SOME_FILL | FULL
        })
    });
}
```

Explanation of each config value:
* `_userTypes` determines the type of User contract spawned when generating users.
    * `DEFAULT` is a standard `User`, and `ALT_METHODS` is the nonstandard `User_AltMethods`. If both these flags are set, when a new user is generated it will randomly choose one of these two contracts to deploy.
* `_quorumConfig` determines what types of quorums are configured at the start of each test:
    * `numQuorums` will cause either 1, 2, or between 3 and 10 quorums to be created (it would be great to do 192 quorums, but that ended up slowing tests down substantially)
    * `numStrategies` causes each deployed quorum to consider either 1, 2, or between 3 and 32 strategy contracts. Each of these strategy contracts are automatically whitelisted in the core contracts.
    * `minimumStake` will cause quorums to either have a minimum, or no minimum stake requirements. If there is a minimum, it will be `MIN_BALANCE` (which is the minimum token amount each User is given on creation - so all generated Users automatically meet a minimum if it exists)
    * `fillTypes` affects how quorums are populated on creation:
        * `EMPTY`: Quorums will not contain any operators
        * `SOME_FILL`: Quorums will contain between 1 and `MAX_OPERATOR_COUNT - 1` operators (e.g. they will NOT be full)
        * `FULL`: Quorums will contain `MAX_OPERATOR_COUNT` operators (e.g. registering is only possible through churn). It'd be weird to have a test that sets this flag in addition to the other two - I use this flag for churn-related testing.