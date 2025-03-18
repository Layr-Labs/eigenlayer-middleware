## SocketRegistry

| File | Type | Proxy |
| -------- | -------- | -------- |
| [`SocketRegistry.sol`](../src/SocketRegistry.sol) | Singleton | Transparent proxy |

The `SocketRegistry` is a simple registry contract that keeps track of operator sockets (arbitrary strings). This socket could represent network connection information such as IP addresses, ports, or other connectivity details.

#### High-level Concepts

This registry maintains a mapping between operator IDs (represented as bytes32 values) and their corresponding socket information. The contract is designed to work in conjunction with the `SlashingRegistryCoordinator`, which is the only contract authorized to update socket information for operators.

This document organizes methods according to the following themes:
* [Socket Management](#socket-management)

---    

### Socket Management

These methods allow for managing operator socket information:
* [`setOperatorSocket`](#setoperatorsocket)

#### `setOperatorSocket`

```solidity
function setOperatorSocket(
    bytes32 _operatorId,
    string memory _socket
)   
    external 
    onlySlashingRegistryCoordinator
```

Sets a socket string with an operator ID (hash of the G1 BLS public key) in the registry. This function is called by the `SlashingRegistryCoordinator`.

*Entry Points:*
Called by the `SlashingRegistryCoordinator` when an operator is registered or needs to update their socket information

*Effects:*
* Sets operatorIdToSocket[_operatorId] to the provided `_socket` string

*Requirements:*
* Caller MUST be the `SlashingRegistryCoordinator`