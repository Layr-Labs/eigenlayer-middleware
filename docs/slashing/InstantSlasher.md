## InstantSlasher

| File | Type | Proxy |
| -------- | -------- | -------- |
| [`InstantSlasher.sol`](../src/InstantSlasher.sol) | Implementation | No |

The `InstantSlasher` is a concrete implementation of the `SlasherBase` contract that provides immediate execution of slashing requests without any delay or veto period. This contract should be used with caution, as slashing is a critical operation within an AVS. This implementation is reccomended if your AVS is mature, robust and the slashing conditions are well understood (i.e. those which do not arise from subjective or non-malicious reasons like a software bug)

*As of current implementation*:
* This contract executes slashing requests immediately when initiated by the authorized slasher
* No waiting period or veto mechanism is implemented
* Each slashing request is assigned a unique ID

---    

### Core Functionality

#### `fulfillSlashingRequest`
```solidity
function fulfillSlashingRequest(
    IAllocationManager.SlashingParams calldata _slashingParams
) 
    external 
    virtual 
    override(IInstantSlasher) 
    onlySlasher
```
Immediately executes a slashing request against the specified operator.

*Entry Points*:
* External calls from the authorized slasher

*Effects*:
* Assigns a unique ID to the slashing request
* Calls the internal `_fulfillSlashingRequest` function to execute the slashing action
* Increments the `nextRequestId` counter for future requests

*Requirements*:
* Caller MUST be the authorized slasher (enforced by `onlySlasher` modifier)
* Slashing parameters must be valid