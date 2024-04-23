// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {IPaymentCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IPaymentCoordinator.sol";
import {IServiceManagerUI} from "./IServiceManagerUI.sol";

/**
 * @title Minimal interface for a ServiceManager-type contract that forms the single point for an AVS to push updates to EigenLayer
 * @author Layr Labs, Inc.
 */
interface IServiceManager is IServiceManagerUI {
    /**
     * @notice Creates a new range payment on behalf of an AVS, to be split amongst the
     * set of stakers delegated to operators who are registered to the `avs`.
     * Note that the owner calling this function must have approved the tokens to be transferred to the ServiceManager
     * and of course has the required balances.
     * @param rangePayments The range payments being created
     * @dev Expected to be called by the ServiceManager of the AVS on behalf of which the payment is being made
     * @dev The duration of the `rangePayment` cannot exceed `paymentCoordinator.MAX_PAYMENT_DURATION()`
     * @dev The tokens are sent to the `PaymentCoordinator` contract
     * @dev Strategies must be in ascending order of addresses to check for duplicates
     * @dev This function will revert if the `rangePayment` is malformed,
     * e.g. if the `strategies` and `weights` arrays are of non-equal lengths
     */
    function payForRange(IPaymentCoordinator.RangePayment[] calldata rangePayments) external;
}
