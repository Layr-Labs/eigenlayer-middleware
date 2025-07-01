## AVSRegistrar

| File | Type | Notes |
| -------- | -------- | -------- |
| [`AVSRegistrar.sol`](../../src/middlewareV2/registrar/AVSRegistrar.sol) | Base Contract | Core registrar with hooks for extensibility |
| [`AVSRegistrarWithSocket.sol`](../../src/middlewareV2/registrar/presets/AVSRegistrarWithSocket.sol) | Preset | Adds socket URL management |
| [`AVSRegistrarWithAllowlist.sol`](../../src/middlewareV2/registrar/presets/AVSRegistrarWithAllowlist.sol) | Preset | Restricts registration to allowlisted operators |
| [`AVSRegistrarAsIdentifier.sol`](../../src/middlewareV2/registrar/presets/AVSRegistrarAsIdentifier.sol) | Preset | Serves as the AVS identifier |

Interfaces:

| File | Notes |
| -------- | -------- |
| [`IAVSRegistrar.sol`](../../lib/eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol) | Main interface (in core repo) |
| [`IAVSRegistrarInternal.sol`](../../src/interfaces/IAVSRegistrarInternal.sol) | Errors and events |
| [`ISocketRegistry.sol`](../../src/interfaces/ISocketRegistryV2.sol) | Socket management interface |
| [`IAllowlist.sol`](../../src/interfaces/IAllowlist.sol) | Allowlist management interface |

---

## Overview

The AVSRegistrar is the primary interface between AVSs and the EigenLayer core protocol for managing operator registration. It enforces that operators have valid keys registered in the `KeyRegistrar` before allowing them to join operator sets. The registrar integrates with the `AllocationManager` to ensure proper stake allocation and operator set membership.

### Key Features

- **Access Control**: All registration/deregistration calls must originate from the `AllocationManager`
- **Key Validation**: Ensures operators have registered appropriate keys (ECDSA or BN254) for their operator sets
- **Extensibility**: Provides hooks for custom registration logic
- **Modular Design**: Presets demonstrate common patterns like socket management and access control

---

## AVSRegistrar (Base Contract)

The base `AVSRegistrar` contract provides core registration functionality with a flexible hooks paradigm for extensibility.

### Core Functions

#### `registerOperator`

```solidity
/**
 * @notice Called by the AllocationManager when an operator wants to register
 * for one or more operator sets
 * @param operator The registering operator
 * @param avs The AVS the operator is registering for (must match this.avs())
 * @param operatorSetIds The list of operator set ids being registered for
 * @param data Arbitrary data the operator can provide as part of registration
 * @dev This method reverts if registration is unsuccessful
 */
function registerOperator(
    address operator,
    address avs,
    uint32[] calldata operatorSetIds,
    bytes calldata data
) external virtual onlyAllocationManager;
```

Registers an operator to one or more operator sets after validating their keys.

*Access Control*:
* Only callable by the `AllocationManager` (enforced by modifier)

*Process*:
1. Calls `_beforeRegisterOperator` hook
2. Validates operator keys via `_validateOperatorKeys`
3. Calls `_afterRegisterOperator` hook
4. Emits `OperatorRegistered` event

*Reverts*:
* `NotAllocationManager` - If caller is not the AllocationManager
* `KeyNotRegistered` - If operator lacks valid keys for any operator set
* Any custom errors from hook implementations

#### `deregisterOperator`

```solidity
/**
 * @notice Called by the AllocationManager when an operator is deregistered from
 * one or more operator sets
 * @param operator The deregistering operator
 * @param avs The AVS the operator is deregistering from (must match this.avs())
 * @param operatorSetIds The list of operator set ids being deregistered from
 * @dev If this method reverts, it is ignored by the AllocationManager
 */
function deregisterOperator(
    address operator,
    address avs,
    uint32[] calldata operatorSetIds
) external virtual onlyAllocationManager;
```

Deregisters an operator from one or more operator sets.

*Access Control*:
* Only callable by the `AllocationManager`

*Process*:
1. Calls `_beforeDeregisterOperator` hook
2. Calls `_afterDeregisterOperator` hook
3. Emits `OperatorDeregistered` event

*Note*: Unlike registration, deregistration failures are ignored by the AllocationManager

#### `supportsAVS`

```solidity
/**
 * @notice Returns true if the AVS is supported by the registrar
 * @param _avs The AVS to check
 * @return true if the AVS is supported, false otherwise
 */
function supportsAVS(
    address _avs
) public view virtual returns (bool);
```

Checks if this registrar supports a given AVS address.

*Returns*:
* `true` if `_avs` matches the configured AVS address
* `false` otherwise

### The Hooks Paradigm

The AVSRegistrar implements a hooks paradigm that enables flexible customization without modifying core logic. This design pattern provides four extension points:

#### Hook Functions

```solidity
/**
 * @notice Hook called before the operator is registered
 * @param operator The operator to register
 * @param operatorSetIds The operator sets to register
 * @param data The data to register
 */
function _beforeRegisterOperator(
    address operator,
    uint32[] calldata operatorSetIds,
    bytes calldata data
) internal virtual {}

/**
 * @notice Hook called after the operator is registered
 * @param operator The operator to register
 * @param operatorSetIds The operator sets to register
 * @param data The data to register
 */
function _afterRegisterOperator(
    address operator,
    uint32[] calldata operatorSetIds,
    bytes calldata data
) internal virtual {}

/**
 * @notice Hook called before the operator is deregistered
 * @param operator The operator to deregister
 * @param operatorSetIds The operator sets to deregister
 */
function _beforeDeregisterOperator(
    address operator,
    uint32[] calldata operatorSetIds
) internal virtual {}

/**
 * @notice Hook called after the operator is deregistered
 * @param operator The operator to deregister
 * @param operatorSetIds The operator sets to deregister
 */
function _afterDeregisterOperator(
    address operator,
    uint32[] calldata operatorSetIds
) internal virtual {}
```

#### Hook Usage Patterns

**Before Hooks** are ideal for:
- Access control checks (e.g., allowlist verification)
- Validation of registration data
- Checking operator eligibility
- Enforcing custom requirements

**After Hooks** are ideal for:
- Storing operator metadata (e.g., socket URLs)
- Updating internal state
- Triggering external notifications
- Recording additional information

#### Benefits of the Hooks Paradigm

1. **Composability**: Multiple behaviors can be combined by chaining hook implementations
2. **Reusability**: Common patterns can be extracted into modules
3. **Upgradability**: New functionality can be added without modifying core logic
4. **Separation of Concerns**: Core registration logic remains simple and focused

### Internal Functions

#### `_validateOperatorKeys`

```solidity
/**
 * @notice Validates that the operator has registered a key for the given operator sets
 * @param operator The operator to validate
 * @param operatorSetIds The operator sets to validate
 * @dev This function assumes the operator has already registered a key in the Key Registrar
 */
function _validateOperatorKeys(
    address operator,
    uint32[] calldata operatorSetIds
) internal view;
```

Ensures the operator has registered appropriate keys for all specified operator sets.

*Process*:
* For each operator set ID:
  * Constructs the `OperatorSet` struct
  * Calls `keyRegistrar.checkKey()` to verify key registration
  * Reverts with `KeyNotRegistered` if check fails

---

## AVSRegistrarWithSocket

Extends the base registrar to capture and store operator socket URLs for off-chain communication.

### Additional Functionality

- Inherits from `SocketRegistry` module
- Stores socket URLs in the `_afterRegisterOperator` hook
- Allows operators to update their socket URLs post-registration

### Registration Data Format

```solidity
// Socket URL must be ABI-encoded as a string
bytes memory data = abi.encode("https://operator.example.com:8080");
```

### Key Methods (from SocketRegistry)

```solidity
/**
 * @notice Get the socket URL for an operator
 * @param operator The operator address
 * @return The operator's socket URL
 */
function getOperatorSocket(address operator) external view returns (string memory);

/**
 * @notice Update the socket URL for the calling operator
 * @param operator The operator address (must be msg.sender)
 * @param socket The new socket URL
 */
function updateSocket(address operator, string memory socket) external;
```

---

## AVSRegistrarWithAllowlist

Adds permissioned registration by maintaining per-operator-set allowlists.

### Additional Functionality

- Inherits from `Allowlist` module with `OwnableUpgradeable`
- Checks allowlist in the `_beforeRegisterOperator` hook
- Admin can manage allowlists via standard functions

### Initialization

```solidity
/**
 * @notice Initialize the allowlist with an admin
 * @param admin The address that can manage the allowlist
 */
function initialize(address admin) public override initializer;
```

### Key Methods (from Allowlist)

```solidity
/**
 * @notice Add an operator to the allowlist for a specific operator set
 * @param operatorSet The operator set to update
 * @param operator The operator to add
 * @dev Only callable by owner
 */
function addOperatorToAllowlist(
    OperatorSet memory operatorSet,
    address operator
) external onlyOwner;

/**
 * @notice Remove an operator from the allowlist
 * @param operatorSet The operator set to update
 * @param operator The operator to remove
 * @dev Only callable by owner
 */
function removeOperatorFromAllowlist(
    OperatorSet memory operatorSet,
    address operator
) external onlyOwner;

/**
 * @notice Check if an operator is allowed for a specific operator set
 * @param operatorSet The operator set to check
 * @param operator The operator to check
 * @return true if allowed, false otherwise
 */
function isOperatorAllowed(
    OperatorSet memory operatorSet,
    address operator
) public view returns (bool);
```

---

## AVSRegistrarAsIdentifier

A specialized registrar that serves as both the registrar and the AVS identifier in the EigenLayer protocol.

### Key Differences

- The registrar contract address becomes the AVS address
- Manages AVS metadata and permissions during initialization
- Integrates with `PermissionController` for admin management

### Initialization

```solidity
/**
 * @notice Initialize the AVS with metadata and admin
 * @param admin The address that will control the AVS
 * @param metadataURI The metadata URI for the AVS
 */
function initialize(address admin, string memory metadataURI) public initializer;
```

*Initialization Process*:
1. Updates AVS metadata URI in the AllocationManager
2. Sets itself as the AVS registrar
3. Initiates admin transfer via PermissionController

### Use Cases

This preset is ideal when:
- You want a single contract to represent your AVS
- You need simplified deployment and management
- You want the registrar to be the primary AVS identity

### Benefits

1. **Simplified Architecture**: One less contract to deploy and manage
2. **Clear Identity**: The registrar IS the AVS
3. **Integrated Permissions**: Admin control is built into initialization