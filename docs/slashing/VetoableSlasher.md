## VetoableSlasher

| File | Type | Proxy |
| -------- | -------- | -------- |
| [`VetoableSlasher.sol`](../src/VetoableSlasher.sol) | Implementation | No |

The `VetoableSlasher` is a concrete implementation of the [`SlasherBase`](./SlasherBase.md) contract that adds a veto mechanism to the slashing process. This implementation introduces a waiting period during which a designated veto committee can cancel slashing requests before they are executed. This slasher implementation is recommended for AVSs to use as their systems matures, to account for slashing faults that arise from subjective conditions or non-malicious reasons such as a software bug. As the AVSs matures and the slashing conditions become well defined, the instant slasher may be a suitable contract. It is reccomended to have your veto comittee to be comprised of a set of diverse subject matter experts. 

*As of current implementation*:
* Slashing requests are queued and can only be fulfilled after a configurable veto window has passed
* A designated veto committee can cancel slashing requests during the veto window
* Slashing requests have a status that tracks their lifecycle: Requested, Cancelled, or Completed

---    

### Core Functionality

#### `queueSlashingRequest`
```solidity
function queueSlashingRequest(
    IAllocationManager.SlashingParams calldata params
) 
    external 
    virtual 
    override 
    onlySlasher
```
Creates and queues a new slashing request that will be executable after the veto window has passed.

*Entry Points*:
* External calls from the authorized slasher

*Effects*:
* Assigns a unique ID to the slashing request
* Creates a new slashing request with the provided parameters
* Sets the request status to `Requested`
* Stores the current block number as the request block
* Emits a `SlashingRequested` event

*Requirements*:
* Caller MUST be the authorized slasher (enforced by `onlySlasher` modifier)
* Slashing parameters must be valid

#### `cancelSlashingRequest`
```solidity
function cancelSlashingRequest(
    uint256 requestId
) 
    external 
    virtual 
    override 
    onlyVetoCommittee
```
Allows the veto committee to cancel a pending slashing request within the veto window.

*Entry Points*:
* External calls from the veto committee

*Effects*:
* Changes the request status from `Requested` to `Cancelled`
* Emits a `SlashingRequestCancelled` event

*Requirements*:
* Caller MUST be the veto committee (enforced by `onlyVetoCommittee` modifier)
* The request MUST be in the `Requested` status
* The current block number MUST be less than the request block plus the veto window

#### `fulfillSlashingRequest`
```solidity
function fulfillSlashingRequest(
    uint256 requestId
) 
    external 
    virtual 
    override 
    onlySlasher
```
Executes a slashing request after the veto window has passed, if it has not been cancelled.

*Entry Points*:
* External calls from the authorized slasher

*Effects*:
* Changes the request status from `Requested` to `Completed`
* Calls the internal `_fulfillSlashingRequest` function to execute the slashing action

*Requirements*:
* Caller MUST be the authorized slasher (enforced by `onlySlasher` modifier)
* The request MUST be in the `Requested` status
* The veto window MUST have passed (current block number >= request block + veto window)

### Modifiers

#### `onlyVetoCommittee`
```solidity
modifier onlyVetoCommittee()
```
Ensures that only the veto committee can call certain functions.

*Effects*:
* Calls `_checkVetoCommittee` to verify that the caller is the veto committee
* Allows the function execution to proceed if the check passes