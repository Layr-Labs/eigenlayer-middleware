// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {BN254} from "eigenlayer-contracts/src/contracts/libraries/BN254.sol";
import {
    IOperatorTableCalculator,
    IOperatorTableCalculatorTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IOperatorTableCalculator.sol";
import {IBN254CertificateVerifierTypes} from
    "eigenlayer-contracts/src/contracts/interfaces/IBN254CertificateVerifier.sol";

interface IBN254TableCalculator is IOperatorTableCalculator, IOperatorTableCalculatorTypes {
    /**
     * @notice Calculates the BN254 operator table info for a given operatorSet
     * @param operatorSet The operatorSet to calculate the operator table for
     * @return operatorSetInfo The BN254OperatorSetInfo containing merkle root, aggregate pubkey, and total weights
     * @dev The output of this function is used by the multichain protocol to transport operator stake weights to destination chains
     * @dev This function aggregates operator weights, creates a merkle tree of operator info, and calculates the aggregate BN254 public key
     */
    function calculateOperatorTable(
        OperatorSet calldata operatorSet
    ) external view returns (BN254OperatorSetInfo memory operatorSetInfo);

    /**
     * @notice Get the individual operator infos for a given operatorSet
     * @param operatorSet The operatorSet to get the operatorInfos for
     * @return operatorInfos The array of BN254OperatorInfo structs containing pubkeys and weights for registered operators
     * @dev Only returns operators that have registered their BN254 keys with the KeyRegistrar
     */
    function getOperatorInfos(
        OperatorSet calldata operatorSet
    ) external view returns (BN254OperatorInfo[] memory operatorInfos);

    /**
     * @notice Returns the 0-based index of an operator within the operator table built by `calculateOperatorTable`
     * @param operatorSet The operator set context used to build the table
     * @param operator The operator address whose index is requested
     * @return found True if the operator is included in the table (registered), false otherwise
     * @return index The 0-based index within the table when `found` is true; zero when `found` is false
     * @dev The operator table is formed by iterating results from `getOperatorSetWeights(operatorSet)` and including
     *      only operators that are registered in `keyRegistrar` for the given `operatorSet`, preserving order.
     *      This function deterministically reconstructs that inclusion order to locate the operator's index.
     */
    function getOperatorIndex(
        OperatorSet calldata operatorSet,
        address operator
    ) external view returns (bool found, uint32 index);

    /**
     * @notice Returns non-signer witnesses and aggregate non-signer BN254 G1 public key for a given set of signing operators
     * @param operatorSet The operator set context
     * @param signingOperators The list of operators that signed (addresses)
     * @return nonSignerWitnesses The witnesses for operators that did not sign
     * @return nonSignerApk The aggregate BN254 G1 public key of the non-signers
     * @dev Reconstructs the operator info merkle tree deterministically to produce proofs and indices.
     * @dev The output of this function is only valid when the operator table has been freshly updated and the current operator set state exactly matches the state at
     *      a given `referenceTimestamp`. In all other cases, the generated `nonSignerWitnesses` will be inconsistent with verification logic.
     */
    function getNonSignerWitnessesAndApk(
        OperatorSet calldata operatorSet,
        address[] calldata signingOperators
    )
        external
        view
        returns (
            IBN254CertificateVerifierTypes.BN254OperatorInfoWitness[] memory nonSignerWitnesses,
            BN254.G1Point memory nonSignerApk
        );
}
