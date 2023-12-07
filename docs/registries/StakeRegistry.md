## StakeRegistry

| File | Type | Proxy? |
| -------- | -------- | -------- |
| [`StakeRegistry.sol`](../src/StakeRegistry.sol) | Singleton | Transparent proxy |

TODO

#### High-level Concepts

TODO

This document organizes methods according to the following themes (click each to be taken to the relevant section):

TODO
<!-- * [Depositing Into EigenLayer](#depositing-into-eigenlayer)
* [Restaking Beacon Chain ETH](#restaking-beacon-chain-eth)
* [Withdrawal Processing](#withdrawal-processing)
* [System Configuration](#system-configuration)
* [Other Methods](#other-methods) -->

#### Important State Variables

TODO

<!-- * `EigenPodManager`:
    * `mapping(address => IEigenPod) public ownerToPod`: Tracks the deployed `EigenPod` for each Staker
    * `mapping(address => int256) public podOwnerShares`: Keeps track of the actively restaked beacon chain ETH for each Staker. 
        * In some cases, a beacon chain balance update may cause a Staker's balance to drop below zero. This is because when queueing for a withdrawal in the `DelegationManager`, the Staker's current shares are fully removed. If the Staker's beacon chain balance drops after this occurs, their `podOwnerShares` may go negative. This is a temporary change to account for the drop in balance, and is ultimately corrected when the withdrawal is finally processed.
        * Since balances on the consensus layer are stored only in Gwei amounts, the EigenPodManager enforces the invariant that `podOwnerShares` is always a whole Gwei amount for every staker, i.e. `podOwnerShares[staker] % 1e9 == 0` always. -->

---    

### Theme

TODO

<!-- Before a Staker begins restaking beacon chain ETH, they need to deploy an `EigenPod`, stake, and start a beacon chain validator:
* [`EigenPodManager.createPod`](#eigenpodmanagercreatepod)
* [`EigenPodManager.stake`](#eigenpodmanagerstake)
    * [`EigenPod.stake`](#eigenpodstake)

To complete the deposit process, the Staker needs to prove that the validator's withdrawal credentials are pointed at the `EigenPod`:
* [`EigenPod.verifyWithdrawalCredentials`](#eigenpodverifywithdrawalcredentials) -->

#### `registerOperator`

```solidity

```

TODO

*Effects*:
*

*Requirements*:
* 

#### `deregisterOperator`

```solidity

```

TODO

*Effects*:
*

*Requirements*:
* 

#### `updateOperatorStake`

```solidity

```

TODO

*Effects*:
*

*Requirements*:
* 

#### `initializeQuorum`

```solidity

```

TODO

*Effects*:
*

*Requirements*:
* 

#### `setMinimumStakeForQuorum`

```solidity

```

TODO

*Effects*:
*

*Requirements*:
* 

#### `addStrategies`

```solidity

```

TODO

*Effects*:
*

*Requirements*:
* 

#### `removeStrategies`

```solidity

```

TODO

*Effects*:
*

*Requirements*:
* 

#### `modifyStrategyParams`

```solidity

```

TODO

*Effects*:
*

*Requirements*:
* 

---