// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {
    IOperatorTableCalculator,
    IOperatorTableCalculatorTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IOperatorTableCalculator.sol";

interface IBN254TableCalculator is IOperatorTableCalculator, IOperatorTableCalculatorTypes {
    /**
     * @notice calculates the operatorInfos for a given operatorSet
     * @param operatorSet the operatorSet to calculate the operator table for
     * @return operatorSetInfo the operatorSetInfo for the given operatorSet
     * @dev The output of this function is converted to bytes via the `calculateOperatorTableBytes` function
     * @dev The `BN254OperatorSetInfo` is given by:
     * ```solidity
     * struct BN254OperatorSetInfo {
     *     bytes32 operatorInfoTreeRoot;
     *     uint256 numOperators;
     *     BN254.G1Point aggregatePubkey;
     *     uint256[] totalWeights;
     * }
     * ```
     * @dev The `operatorInfoTreeRoot` is the root of a merkle tree that contains the operatorInfos for each operator in the operatorSet (see below).
     *      The root is calculated on-chain, and is intended to be utilized by off-chain services
     * @dev The `numOperators` is the number of operators in the operatorSet
     * @dev The `aggregatePubkey` is the aggregate G1 public key of the operators in the operatorSet.
     *      Retrieval of the `aggregatePubKey` depends on maintaining a key registry contract, see `KeyRegistrar` for an example implementation
     * @dev The `totalWeights` is an array of arbitrary stake types. For example, it can be [slashable_stake, delegated_stake, strategy_i_stake, ...]
     *      It is up to the AVS to define the `weights` array, which is used by the `IBN254CertificateVerifier` to verify Certificates
     * @dev The `totalWeights` array should be the same length as each individual `weights` array in `BN254OperatorInfo`, otherwise verification issues can arise
     */
    function calculateOperatorTable(
        OperatorSet calldata operatorSet
    ) external view returns (BN254OperatorSetInfo memory operatorSetInfo);

    /**
     * @notice Get the operatorInfos for a given operatorSet
     * @param operatorSet the operatorSet to get the operatorInfos for
     * @return operatorInfos the operatorInfos for the given operatorSet
     * @dev `BN254OperatorInfo` is given by:
     * ```solidity
     *     struct BN254OperatorInfo {
     *         BN254.G1Point pubkey;
     *         uint256[] weights;
     *     }
     * ```
     * @dev The `pubkey` param is the G1 public key of the operator, which is fetched from the `keyRegistrar` contract
     * @dev The `weights` param is an array of arbitrary stake types. For example, it can be [slashable_stake, delegated_stake, strategy_i_stake, ...]
     *      It is up to the AVS to define the `weights` array, which is used by the `IBN254CertificateVerifier` to verify Certificates
     * @dev The `weights` array for each operator should be the same length and composition, otherwise verification issues can arise
     */
    function getOperatorInfos(
        OperatorSet calldata operatorSet
    ) external view returns (BN254OperatorInfo[] memory operatorInfos);
}
