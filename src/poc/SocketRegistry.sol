// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {SocketRegistryStorage} from "./SocketRegistryStorage.sol";
import {AVSRegistrar} from "./AVSRegistrar.sol";
import {ISocketRegistry} from "./interfaces/ISocketRegistry.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

abstract contract SocketRegistry is AVSRegistrar, SocketRegistryStorage {
    function __SocketRegistry_init(
        uint256 startIndex,
        uint256 endIndex
    ) internal onlyInitializing {
        __SocketRegistry_init_unchained(startIndex, endIndex);
    }

    function __SocketRegistry_init_unchained(
        uint256 startIndex,
        uint256 endIndex
    ) internal onlyInitializing {
        _getSocketRegistryStorage().startIndex = startIndex;
        _getSocketRegistryStorage().endIndex = endIndex;
    }

    /// @inheritdoc ISocketRegistry
    function updateSocket(address operator, string memory socket) external {
        require(
            allocationManager.isMemberOfOperatorSet(
                operator, OperatorSet({avs: avs, id: operatorSetId})
            ),
            "Operator not registered for operator set"
        );
        _updateSocket(operator, socket);
    }

    /**
     * @notice Overrides the afterRegisterOperator function to update the socket
     * @param operator The operator to update the socket for
     * @param data The data to update the socket with
     */
    function _afterRegisterOperator(
        address operator,
        bytes calldata data
    ) internal virtual override {
        super._afterRegisterOperator(operator, data);
        string memory socket = abi.decode(_parseRegistrationData(data), (string));
        _updateSocket(operator, socket);
    }

    /**
     * @notice Overrides the afterDeregisterOperator function to clear the socker of an operator
     * @param operator The operator to remove the socket from
     */
    function _afterDeregisterOperator(
        address operator
    ) internal virtual override {
        super._afterDeregisterOperator(operator);
        _updateSocket(operator, "");
    }

    /// @inheritdoc ISocketRegistry
    function getSocket(
        address operator
    ) external view returns (string memory) {
        return _getSocketRegistryStorage()._operatorSocket[operator];
    }

    /// @dev Internal function to update the socket for an operator
    function _updateSocket(address operator, string memory socket) internal {
        _getSocketRegistryStorage()._operatorSocket[operator] = socket;
    }

    function _parseRegistrationData(
        bytes calldata data
    ) internal virtual view override returns (bytes memory) {
        return data[_getSocketRegistryStorage().startIndex:_getSocketRegistryStorage().endIndex];
    }
}
