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
 * This contract adds minimal signature-checking logic, but lacks any logic related to task confirmation per se.
 * @dev To extend this contract, e.g. to confirm tasks based on a simple percentage check, one could add a function
 *  which calls the `checkSignatures` function and compares the return value to `totalStakeHistory[epoch]`.
 */
contract EcdsaEpochBase is EcdsaEpochRegistry_Permissionless {
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
        uint256 _retargettingFactorWei
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
    }

    /*******************************************************************************
                    EXTERNAL FUNCTIONS - unpermissioned
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
}
