// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {BN254}from"eigenlayer-contracts/src/contracts/libraries/BN254.sol";

/**
 * @title Minimal interface for the `BLSPublicKeyCompendium` contract.
 * @author Layr Labs, Inc.
 * @notice Terms of Service: https://docs.eigenlayer.xyz/overview/terms-of-service
 */
interface IBLSPublicKeyCompendium {

    // EVENTS
    /// @notice Emitted when `operator` registers with the public keys `pubkeyG1` and `pubkeyG2`.
    event NewPubkeyRegistration(address indexed operator, BN254.G1Point pubkeyG1, BN254.G2Point pubkeyG2);

    /**
     * @notice mappings from operator address to X and Y coordinate of operator's G1 pubkey.
     * Returns *zero* if the `operator` has never registered, and otherwise returns the X or Y coordinate of the public key of the operator.
     * @dev separating into two mappings (instead of a operatorToG1Pubkey mapping to a BN254.G1Point) because Axiom's mapping queries
     * (https://docs-v2.axiom.xyz/axiom-repl/data-functions#solidity-nested-mapping-subquery) can only return a single slot.
     * so even if we had a mapping to a BN254.G1Point the query would only return the first X value.
     * Hence we would need to compute the slots directly and pass them as input, export them as public outputs and validate their value in the
     * axiomv2callback, which is a lot of work... hopefully they'll add a better api to their mapping queries soon and we can refactor this.
     */
    function operatorToG1PubkeyX(address operator) external view returns (uint256);
    function operatorToG1PubkeyY(address operator) external view returns (uint256);

    /**
     * @notice mapping from pubkey hash to operator address.
     * Returns *zero* if no operator has ever registered the public key corresponding to `pubkeyHash`,
     * and otherwise returns the (unique) registered operator who owns the BLS public key that is the preimage of `pubkeyHash`.
     */
    function pubkeyHashToOperator(bytes32 pubkeyHash) external view returns (address);

    /**
     * @notice Called by an operator to register themselves as the owner of a BLS public key and reveal their G1 and G2 public key.
     * @param signedMessageHash is the registration message hash signed by the private key of the operator
     * @param pubkeyG1 is the corresponding G1 public key of the operator 
     * @param pubkeyG2 is the corresponding G2 public key of the operator
     */
    function registerBLSPublicKey(BN254.G1Point memory signedMessageHash, BN254.G1Point memory pubkeyG1, BN254.G2Point memory pubkeyG2) external;

    /**
     * @notice Returns the message hash that an operator must sign to register their BLS public key.
     * @param operator is the address of the operator registering their BLS public key
     */
    function getMessageHash(address operator) external view returns (BN254.G1Point memory);
}
