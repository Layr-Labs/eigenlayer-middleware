// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

/**
 * @dev Reverts the transaction with the provided data.
 * This function uses low-level assembly to manipulate the data directly.
 * This is necessary to ensure the data is correctly formatted for the revert operation.
 * @param data The data to revert with.
 */
function _revertWithData(
    bytes memory data
) pure {
    // prettier-ignore
    assembly {
        revert(add(data, 32), mload(data))
    }
}

/**
 * @dev Returns the provided data.
 * This function uses low-level assembly to manipulate the data directly.
 * This is necessary to ensure the data is correctly formatted for the return operation.
 * @param data The data to return.
 */
function _returnWithData(
    bytes memory data
) pure {
    // prettier-ignore
    assembly {
        return(add(data, 32), mload(data))
    }
}

/**
 * @dev Interface for static delegate call operations.
 * Having the separate interface allows us to use delegatecall which the compiler interprets its usage as a potential modifier of state.
 * We can wrap with this view version of the function so that functions using the library can still use the restricted view keyword.
 */
interface IStaticDelegateCall {
    /**
     * @dev Performs a delegate call and reverts with the result.
     * @param to The address to delegate call to.
     * @param data The call data to send.
     */
    function delegateCallAndRevert(address to, bytes memory data) external view;
}

/**
 * @title LibStaticDelegateCall
 * @dev Library for performing static delegate calls and handling their results.
 */
library StaticDelegateCallLib {
    /**
     * @dev Performs a delegate call to the specified address with the provided data preventing state modification
     * This is done by first calling a special function on itself that always reverts with the return data of the delegatecall
     * If the delegate call succeeds, the function returns the result.
     * If the delegate call reverts, the function reverts with the returned data.
     * @param to The address to delegate call to.
     * @param data The call data to send.
     */
    function staticDelegateCall(address to, bytes memory data) internal view {
        try IStaticDelegateCall(address(this)).delegateCallAndRevert(to, data) {
            assert(false);
        } catch (bytes memory revertData) {
            (bool success, bytes memory returnData) = abi.decode(revertData, (bool, bytes));
            // Transform the data back into the actual result of the delegatecall
            if (success) {
                _returnWithData(returnData);
            } else {
                _revertWithData(returnData);
            }
        }
    }
}

/**
 * @title StaticDelegateCaller
 * @dev Abstract contract to perform delegate calls and revert with the result.
 */
abstract contract StaticDelegateCaller {
    /**
     * @dev Error to indicate that the caller is not authorized.
     */
    error Unauthorized();

    /**
     * @dev Performs a delegate call to the specified address with the provided data and reverts with the result.
     * This ensures that no state modifications occur.
     * @param to The address to delegate call to.
     * @param data The call data to send.
     */
    function delegateCallAndRevert(address to, bytes memory data) external {
        if (msg.sender != address(this)) {
            revert Unauthorized();
        }
        (bool success, bytes memory result) = to.delegatecall(data);

        bytes memory encodedData = abi.encode(success, result);
        // Transform the result of the delegatecall into a revert, regardless of what actually happened
        // Guarantees no state modifications
        _revertWithData(encodedData);
    }
}
