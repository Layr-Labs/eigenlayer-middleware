// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IServiceManagerUI} from "./interfaces/IServiceManagerUI.sol";

/**
 * @title Contract that proxies calls to a ServiceManager contract.
 * This contract is designed to be used by off-chain services which need
 * errors to be handled gracefully.
 * @author Layr Labs, Inc.
 */
contract ServiceManagerRouter {
    address public constant FAILED_CALL_ADDRESS =
        address(0x000000000000000000000000000000000000dEaD);

    /**
     * @notice Returns the list of strategies that the AVS supports for restaking
     * @param serviceManager Address of AVS's ServiceManager contract
     */
    function getRestakeableStrategies(
        address serviceManager
    ) external view returns (address[] memory) {
        bytes memory data =
            abi.encodeWithSelector(IServiceManagerUI.getRestakeableStrategies.selector);
        return _makeCall(serviceManager, data);
    }

    /**
     * @notice Returns the list of strategies that the operator has potentially restaked on the AVS
     * @param serviceManager Address of AVS's ServiceManager contract
     * @param operator Address of the operator to get restaked strategies for
     */
    function getOperatorRestakedStrategies(
        address serviceManager,
        address operator
    ) external view returns (address[] memory) {
        bytes memory data = abi.encodeWithSelector(
            IServiceManagerUI.getOperatorRestakedStrategies.selector, operator
        );
        return _makeCall(serviceManager, data);
    }

    /**
     * @notice Internal helper function to make static calls
     * @dev Handles calls to contracts that don't implement the given function and to EOAs by
     *      returning a failed call address
     */
    function _makeCall(
        address serviceManager,
        bytes memory data
    ) internal view returns (address[] memory) {
        (bool success, bytes memory strategiesBytes) = serviceManager.staticcall(data);
        if (success && strategiesBytes.length > 0) {
            return abi.decode(strategiesBytes, (address[]));
        } else {
            address[] memory failedCall = new address[](1);
            failedCall[0] = FAILED_CALL_ADDRESS;
            return failedCall;
        }
    }
}
