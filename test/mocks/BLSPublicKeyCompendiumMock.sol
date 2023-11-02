// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "src/interfaces/IBLSPublicKeyCompendium.sol";
import "eigenlayer-contracts/src/contracts/libraries/BN254.sol";
/**
 * @title A shared contract for EigenLayer operators to register their BLS public keys.
 * @author Layr Labs, Inc.
 * @notice Terms of Service: https://docs.eigenlayer.xyz/overview/terms-of-service
 */
contract BLSPublicKeyCompendiumMock is IBLSPublicKeyCompendium{

    /// @notice the hash of the zero pubkey aka BN254.G1Point(0,0)
    bytes32 internal constant ZERO_PK_HASH = hex"ad3228b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5";

    /// @notice maps operator address to pubkey hash
    mapping(address => bytes32) public operatorToPubkeyHash;
    /// @notice maps pubkey hash to operator address
    mapping(bytes32 => address) public pubkeyHashToOperator;
    /// @notice maps operator address to pubkeyG1
    mapping(address => BN254.G1Point) public operatorToPubkey;

    /**
     * @notice Called by an operator to register themselves as the owner of a BLS public key and reveal their G1 and G2 public key.
     * @param signedMessageHash is the registration message hash signed by the private key of the operator
     * @param pubkeyG1 is the corresponding G1 public key of the operator 
     * @param pubkeyG2 is the corresponding G2 public key of the operator
     */
    function registerBLSPublicKey(BN254.G1Point memory signedMessageHash, BN254.G1Point memory pubkeyG1, BN254.G2Point memory pubkeyG2) external {
    }

    function registerPublicKey(BN254.G1Point memory pk) external {

        bytes32 pubkeyHash = BN254.hashG1Point(pk);
        // store updates
        operatorToPubkeyHash[msg.sender] = pubkeyHash;
        pubkeyHashToOperator[pubkeyHash] = msg.sender;
        operatorToPubkey[msg.sender] = pk;
    }

    function setBLSPublicKey(address account, BN254.G1Point memory pk) external {

        bytes32 pubkeyHash = BN254.hashG1Point(pk);
        // store updates
        operatorToPubkeyHash[account] = pubkeyHash;
        pubkeyHashToOperator[pubkeyHash] = account;
        operatorToPubkey[account] = pk;
    }

    function getRegisteredPubkey(address operator) public view returns (BN254.G1Point memory) {
        BN254.G1Point memory pubkey = operatorToPubkey[operator];
        bytes32 pubkeyHash = operatorToPubkeyHash[operator];

        require(
            pubkeyHash != bytes32(0) && BN254.hashG1Point(pubkey) == pubkeyHash, 
            "BLSPublicKeyCompendium.getRegisteredPubkey: operator is not registered"
        );

        require(pubkeyHash != ZERO_PK_HASH, "BLSPublicKeyCompendium.getRegisteredPubkey: invalid pubkey");
        
        return pubkey;
    }

    function getMessageHash(address operator) external view returns (BN254.G1Point memory) {}
}
