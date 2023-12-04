// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "./interfaces/IIndexRegistry.sol";
import "./interfaces/IRegistryCoordinator.sol";

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

/**
 * @title Storage variables for the `IndexRegistry` contract.
 * @author Layr Labs, Inc.
 * @notice This storage contract is separate from the logic to simplify the upgrade process.
 */
abstract contract IndexRegistryStorage is Initializable, IIndexRegistry {

    /// @notice The value that is returned when an operator does not exist at an index at a certain block
    bytes32 public constant OPERATOR_DOES_NOT_EXIST_ID = bytes32(0);

    /// @notice The RegistryCoordinator contract for this middleware
    IRegistryCoordinator public immutable registryCoordinator;

    /// @notice list of all operators ever registered, may include duplicates. used to avoid running an indexer on nodes
    bytes32[] public globalOperatorList;

    /// @notice mapping of quorumNumber => operator id => current index
    mapping(uint8 => mapping(bytes32 => uint32)) public operatorIdToIndex;
    /// @notice mapping of quorumNumber => index => operator id history for that index
    mapping(uint8 => mapping(uint32 => OperatorUpdate[])) internal _indexToOperatorIdHistory;
    /// @notice mapping of quorumNumber => history of numbers of unique registered operators
    mapping(uint8 => QuorumUpdate[]) internal _totalOperatorsHistory;

    constructor(
        IRegistryCoordinator _registryCoordinator
    ){
        registryCoordinator = _registryCoordinator;
        // disable initializers so that the implementation contract cannot be initialized
        _disableInitializers();
    }

    // storage gap for upgradeability
    uint256[47] private __GAP;
}
