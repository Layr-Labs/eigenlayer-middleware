// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {
    IOperatorTableCalculator,
    IOperatorTableCalculatorTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IOperatorTableCalculator.sol";

interface IECDSATableCalculator is IOperatorTableCalculator, IOperatorTableCalculatorTypes {
    /**
     * @notice calculates the operatorInfos for a given operatorSet
     * @param operatorSet the operatorSet to calculate the operator table for
     * @return operatorInfos the list of operatorInfos for the given operatorSet
     * @dev The output of this function is converted to bytes via the `calculateOperatorTableBytes` function
     * @dev `ECDSAOperatorInfo` is given by:
     * ```solidity
     * struct ECDSAOperatorInfo {
     *     address pubkey;
     *     uint256[] weights;
     * }
     * ```
     * @dev The `pubkey` param is the address of the signing ECDSA key of the operator and not the operator address itself.
     * @dev The `weights` param is an array of arbitrary stake types. For example, it can be [slashable_stake, delegated_stake, strategy_i_stake, ...]
     *      It is up to the AVS to define the `weights` array, which is used by the `IECDSACertificateVerifier` to verify Certificates
     * @dev For each operator, the `weights` array should be the same length and composition, otherwise verification issues can arise
     */
    function calculateOperatorTable(
        OperatorSet calldata operatorSet
    ) external view returns (ECDSAOperatorInfo[] memory operatorInfos);
}
