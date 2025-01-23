// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IBLSApkRegistry} from "./IBLSApkRegistry.sol";
import {ISlashingRegistryCoordinator} from "./ISlashingRegistryCoordinator.sol";

interface IRegistryCoordinator {
    
    /**
     * @notice Registers msg.sender as an operator for one or more quorums. If any quorum exceeds its maximum
     * operator capacity after the operator is registered, this method will fail.
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for
     * @param socket is the socket of the operator (typically an IP address)
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @param operatorSignature is the signature of the operator used by the AVS to register the operator in the delegation manager
     * @dev `params` is ignored if the caller has previously registered a public key
     * @dev `operatorSignature` is ignored if the operator's status is already REGISTERED
     */
    function registerOperator(
        bytes memory quorumNumbers,
        string memory socket,
        IBLSApkRegistry.PubkeyRegistrationParams memory params,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external;

    /**
     * @notice Registers msg.sender as an operator for one or more quorums. If any quorum reaches its maximum operator
     * capacity, `operatorKickParams` is used to replace an old operator with the new one.
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being registered for
     * @param params contains the G1 & G2 public keys of the operator, and a signature proving their ownership
     * @param operatorKickParams used to determine which operator is removed to maintain quorum capacity as the
     * operator registers for quorums
     * @param churnApproverSignature is the signature of the churnApprover over the `operatorKickParams`
     * @param operatorSignature is the signature of the operator used by the AVS to register the operator in the delegation manager
     * @dev `params` is ignored if the caller has previously registered a public key
     * @dev `operatorSignature` is ignored if the operator's status is already REGISTERED
     */
    function registerOperatorWithChurn(
        bytes calldata quorumNumbers,
        string memory socket,
        IBLSApkRegistry.PubkeyRegistrationParams memory params,
        ISlashingRegistryCoordinator.OperatorKickParam[] memory operatorKickParams,
        ISignatureUtils.SignatureWithSaltAndExpiry memory churnApproverSignature,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external;

    /**
     * @notice Deregisters the caller from one or more quorums
     * @param quorumNumbers is an ordered byte array containing the quorum numbers being deregistered from
     */
    function deregisterOperator(bytes memory quorumNumbers) external;

    /**
     * @notice Enables operator sets mode. This is by default initialized to set `isOperatorSetAVS` to True.
     * So this is only meant to be called for existing AVSs that have a existing quorums and a previously deployed
     * version of middleware contracts.
     * @dev This is only callable by the owner of the RegistryCoordinator
     */
    function enableOperatorSets() external;
}
