// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IServiceManager} from "../interfaces/IServiceManager.sol";

import {EcdsaEpochRegistry_Permissionless} from "./EcdsaEpochRegistry_Permissionless.sol";

import {EIP1271SignatureUtils} from "eigenlayer-contracts/src/contracts/libraries/EIP1271SignatureUtils.sol";

/**
 * @notice An example AVS contract that builds on top of the `EcdsaEpochRegistry_Permissionless`.
 * This contract adds minimal signature-checking logic, as well as minimal task-confirmation logic
 */
contract EcdsaEpochBase is EcdsaEpochRegistry_Permissionless {

    // @notice Constant used when calculating whether or not signatures meet the task confirmation threshold
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    // @notice Signature threshold that must be met for task confirmation
    uint256 public confirmationThresholdBips;

    // @notice Mapping: msgHash => timestamp of confirmation
    mapping(bytes32 => uint256) public confirmedTaskTimestamps;

    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[49] private __GAP;

    event ConfirmationThresholdBipsSet(uint256 previousValue, uint256 newValue);
    event TaskConfirmed(bytes32 indexed msgHash, uint256 timestamp);

    /** 
     * @dev setting the `_epochZeroStart` to be in the past is disallowed.
     * If you try to do so, the current block.timestamp will be used instead.
     * Future times are allowed, with no safety check in place.
     */
    constructor(
        IServiceManager _serviceManager,
        IDelegationManager _delegationManager,
        uint256 _epochLengthSeconds,
        uint256 _epochZeroStart,
        uint256 _minimumWeightRequirementInitValue,
        uint256 _targetOperatorSetSize,
        uint256 _maxRegisteredOperators,
        uint256 _defaultWeightRequirement,
        uint256 _retargettingFactorWei,
        uint256 _confirmationThresholdBips
    )
        EcdsaEpochRegistry_Permissionless(
            _serviceManager,
            _delegationManager,
            _epochLengthSeconds,
            _epochZeroStart,
            _minimumWeightRequirementInitValue,
            _targetOperatorSetSize,
            _maxRegisteredOperators,
            _defaultWeightRequirement,
            _retargettingFactorWei
        )
    {
        _setConfirmationThresholdBips(_confirmationThresholdBips);
    }

    /*******************************************************************************
                    EXTERNAL FUNCTIONS - permissioned
    *******************************************************************************/
    function setConfirmationThresholdBips(uint256 _confirmationThresholdBips) external virtual onlyOwner {
        _setConfirmationThresholdBips(_confirmationThresholdBips);
    }

    /*******************************************************************************
                    EXTERNAL FUNCTIONS - unpermissioned
    *******************************************************************************/

    /**
     * @notice Confirms a task for the current epoch. Checks the provided signatures + ensures that they meet the
     * `confirmationThresholdBips` as a fraction of the total stake for the epoch.
     */
    function confirmTask(
        bytes32 msgHash,
        address[] memory operators,
        bytes[] memory signatures
    )
        public
        virtual
    {
        uint256 _currentEpoch = currentEpoch();
        uint256 totalSignedAmount = checkSignatures(msgHash, operators, signatures, _currentEpoch);
        uint256 totalStakeForEpoch = totalStakeHistory[_currentEpoch];
        require((totalSignedAmount * BASIS_POINTS_DIVISOR) >= (totalStakeForEpoch * confirmationThresholdBips),
            "signature threshold not met");
        confirmedTaskTimestamps[msgHash] = block.timestamp;
        emit TaskConfirmed(msgHash, block.timestamp);
    }

    /*******************************************************************************
                            INTERNAL FUNCTIONS
    *******************************************************************************/
    function _setConfirmationThresholdBips(uint256 _confirmationThresholdBips) internal {
        require(_confirmationThresholdBips <= BASIS_POINTS_DIVISOR, "cannot require more than 100% confirmation");
        require(_confirmationThresholdBips != 0, "cannot require 0% confirmation");
        emit ConfirmationThresholdBipsSet(confirmationThresholdBips, _confirmationThresholdBips);
        confirmationThresholdBips = _confirmationThresholdBips;
    }

    /*******************************************************************************
                            VIEW FUNCTIONS
    *******************************************************************************/
    function checkSignatures(
        bytes32 msgHash,
        address[] memory operators,
        bytes[] memory signatures,
        uint256 epoch
    ) 
        public 
        view
        virtual
        returns (uint256 totalSignedAmount)
    {
        require(
            operators.length == signatures.length,
            "BLSSignatureChecker.checkSignatures: signature input length mismatch"
        );

        for (uint256 i = 0; i < operators.length; ++i) {

            // The check below validates that operatorIds are sorted (and therefore free of duplicates)
            if (i != 0) {
                require(
                    operators[i] >  operators[i - 1],
                    "ECDSASignatureChecker.checkSignatures: signer keys not sorted"
                );
            }

            // check the operator's signature
            // TODO: any modifications to msgHash? e.g. hashing the 'msgHash' with the address whose sig is being checked
            EIP1271SignatureUtils.checkSignature_EIP1271(operators[i], msgHash, signatures[i]);

            totalSignedAmount += _operatorStakeHistory[operators[i]][epoch];
        }

        return totalSignedAmount;
    }

    function isTaskConfirmed(bytes32 msgHash) external view virtual returns (bool) {
        return confirmedTaskTimestamps[msgHash] != 0;
    }
}
