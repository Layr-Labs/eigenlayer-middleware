// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPaymentCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IPaymentCoordinator.sol";

contract PaymentCoordinatorMock is IPaymentCoordinator {
    /// @notice The address of the entity that can update the contract with new merkle roots
    function paymentUpdater() external view returns (address) {}

    /**
     * @notice The interval in seconds at which the calculation for range payment distribution is done.
     * @dev Payment durations must be multiples of this interval.
     */
    function calculationIntervalSeconds() external view returns (uint32) {}

    /// @notice The maximum amount of time that a range payment can end in the future
    function MAX_PAYMENT_DURATION() external view returns (uint32) {}

    /// @notice max amount of time that a payment can start in the past
    function MAX_RETROACTIVE_LENGTH() external view returns (uint32) {}

    /// @notice max amount of time that a payment can start in the future
    function MAX_FUTURE_LENGTH() external view returns (uint32) {}

    /// @notice absolute min timestamp that a payment can start at
    function GENESIS_PAYMENT_TIMESTAMP() external view returns (uint32) {}

    /// @notice Delay in timestamp before a posted root can be claimed against
    function activationDelay() external view returns (uint32) {}

    /// @notice Mapping: earner => the address of the entity to which new payments are directed on behalf of the earner
    function claimerFor(address earner) external view returns (address) {}

    /// @notice Mapping: claimer => token => total amount claimed
    function cumulativeClaimed(address claimer, IERC20 token) external view returns (uint256) {}

    /// @notice the commission for all operators across all avss
    function globalOperatorCommissionBips() external view returns (uint16) {}

    /// @notice return the hash of the earner's leaf
    function calculateEarnerLeafHash(EarnerTreeMerkleLeaf calldata leaf) external pure returns (bytes32) {}

    /// @notice returns the hash of the earner's token leaf
    function calculateTokenLeafHash(TokenTreeMerkleLeaf calldata leaf) external pure returns (bytes32) {}

    /// @notice returns 'true' if the claim would currently pass the check in `processClaims`
    /// but will revert if not valid
    function checkClaim(PaymentMerkleClaim calldata claim) external view returns (bool) {}

    /// EXTERNAL FUNCTIONS ///

    /**
     * @notice Creates a new range payment on behalf of an AVS, to be split amongst the
     * set of stakers delegated to operators who are registered to the `avs`
     * @param rangePayments The range payments being created
     * @dev Expected to be called by the ServiceManager of the AVS on behalf of which the payment is being made
     * @dev The duration of the `rangePayment` cannot exceed `MAX_PAYMENT_DURATION`
     * @dev The tokens are sent to the `PaymentCoordinator` contract
     * @dev Strategies must be in ascending order of addresses to check for duplicates
     * @dev This function will revert if the `rangePayment` is malformed,
     * e.g. if the `strategies` and `weights` arrays are of non-equal lengths
     */
    function payForRange(RangePayment[] calldata rangePayments) external {}

    /**
     * @notice similar to `payForRange` except the payment is split amongst *all* stakers
     * rather than just those delegated to operators who are registered to a single avs and is
     * a permissioned call based on isPayAllForRangeSubmitter mapping.
     */
    function payAllForRange(RangePayment[] calldata rangePayment) external {}

    /**
     * @notice Claim payments against a given root (read from distributionRoots[claim.rootIndex]).
     * Earnings are cumulative so earners don't have to claim against all distribution roots they have earnings for,
     * they can simply claim against the latest root and the contract will calculate the difference between
     * their cumulativeEarnings and cumulativeClaimed. This difference is then transferred to claimerFor[claim.earner]
     * @param claim The PaymentMerkleClaim to be processed.
     * Contains the root index, earner, payment leaves, and required proofs
     * @dev only callable by the valid claimer, that is
     * if claimerFor[claim.earner] is address(0) then only the earner can claim, otherwise only
     * claimerFor[claim.earner] can claim the payments.
     */
    function processClaim(PaymentMerkleClaim calldata claim) external {}

    /**
     * @notice Creates a new distribution root. activatedAt is set to block.timestamp + activationDelay
     * @param root The merkle root of the distribution
     * @param paymentCalculationEndTimestamp The timestamp until which payments have been calculated
     * @dev Only callable by the paymentUpdater
     */
    function submitRoot(
        bytes32 root,
        uint32 paymentCalculationEndTimestamp
    ) external {}

    /**
     * @notice Sets the permissioned `paymentUpdater` address which can post new roots
     * @dev Only callable by the contract owner
     */
    function setPaymentUpdater(address _paymentUpdater) external {}

    /**
     * @notice Sets the delay in timestamp before a posted root can be claimed against
     * @param _activationDelay Delay in timestamp before a posted root can be claimed against
     * @dev Only callable by the contract owner
     */
    function setActivationDelay(uint32 _activationDelay) external {}

    /**
     * @notice Sets the global commission for all operators across all avss
     * @param _globalCommissionBips The commission for all operators across all avss
     * @dev Only callable by the contract owner
     */
    function setGlobalOperatorCommission(uint16 _globalCommissionBips) external {}

    /**
     * @notice Sets the address of the entity that can claim payments on behalf of the earner (msg.sender)
     * @param claimer The address of the entity that can claim payments on behalf of the earner
     * @dev Only callable by the `earner`
     */
    function setClaimerFor(address claimer) external {}

}