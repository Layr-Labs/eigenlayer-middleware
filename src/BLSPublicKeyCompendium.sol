// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "./interfaces/IBLSPublicKeyCompendium.sol";

import "./libraries/BN254.sol";

/**
 * @title A shared contract for EigenLayer operators to register their BLS public keys.
 * @author Layr Labs, Inc.
 * @notice Terms of Service: https://docs.eigenlayer.xyz/overview/terms-of-service
 */
contract BLSPublicKeyCompendium is IBLSPublicKeyCompendium {
    using BN254 for BN254.G1Point;

    /// @notice the hash of the zero pubkey aka BN254.G1Point(0,0)
    bytes32 internal constant ZERO_PK_HASH = hex"ad3228b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5";

    /// @notice maps operator address to pubkey hash
    mapping(address => bytes32) public operatorToPubkeyHash;
    /// @notice maps pubkey hash to operator address
    mapping(bytes32 => address) public pubkeyHashToOperator;
    /// @notice maps operator address to pubkeyG1
    mapping(address => BN254.G1Point) public operatorToPubkey;

    /*******************************************************************************
                            EXTERNAL FUNCTIONS 
    *******************************************************************************/

    /**
     * @notice Called by an operator to register themselves as the owner of a BLS public key and reveal their G1 and G2 public key.
     * @param signedMessageHash is the registration message hash signed by the private key of the operator
     * @param pubkeyG1 is the corresponding G1 public key of the operator 
     * @param pubkeyG2 is the corresponding G2 public key of the operator
     */
    function registerBLSPublicKey(
        BN254.G1Point memory signedMessageHash, 
        BN254.G1Point memory pubkeyG1, 
        BN254.G2Point memory pubkeyG2
    ) external {
        bytes32 pubkeyHash = BN254.hashG1Point(pubkeyG1);
        require(
            pubkeyHash != ZERO_PK_HASH, "BLSPublicKeyCompendium.registerBLSPublicKey: cannot register zero pubkey"
        );
        require(
            operatorToPubkeyHash[msg.sender] == bytes32(0),
            "BLSPublicKeyCompendium.registerBLSPublicKey: operator already registered pubkey"
        );
        require(
            pubkeyHashToOperator[pubkeyHash] == address(0),
            "BLSPublicKeyCompendium.registerBLSPublicKey: public key already registered"
        );

        // H(m) 
        BN254.G1Point memory messageHash = getMessageHash(msg.sender);

        // gamma = h(sigma, P, P', H(m))
        uint256 gamma = uint256(keccak256(abi.encodePacked(
            signedMessageHash.X, 
            signedMessageHash.Y, 
            pubkeyG1.X, 
            pubkeyG1.Y, 
            pubkeyG2.X, 
            pubkeyG2.Y, 
            messageHash.X, 
            messageHash.Y
        ))) % BN254.FR_MODULUS;
        
        // e(sigma + P * gamma, [-1]_2) = e(H(m) + [1]_1 * gamma, P') 
        require(BN254.pairing(
            signedMessageHash.plus(pubkeyG1.scalar_mul(gamma)),
            BN254.negGeneratorG2(),
            messageHash.plus(BN254.generatorG1().scalar_mul(gamma)),
            pubkeyG2
        ), "BLSPublicKeyCompendium.registerBLSPublicKey: either the G1 signature is wrong, or G1 and G2 private key do not match");

        operatorToPubkey[msg.sender] = pubkeyG1;
        operatorToPubkeyHash[msg.sender] = pubkeyHash;
        pubkeyHashToOperator[pubkeyHash] = msg.sender;

        emit NewPubkeyRegistration(msg.sender, pubkeyG1, pubkeyG2);
    }

    /*******************************************************************************
                            VIEW FUNCTIONS
    *******************************************************************************/

    /**
     * @notice Returns the pubkey of an operator, verifying that the pubkey and its hash are valid
     * @dev Reverts if the operator has not registered a valid pubkey
     */
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

    /**
     * @notice Returns the message hash that an operator must sign to register their BLS public key.
     * @param operator is the address of the operator registering their BLS public key
     */
    function getMessageHash(address operator) public view returns (BN254.G1Point memory) {
        return BN254.hashToG1(keccak256(abi.encodePacked(
            operator, 
            address(this),
            block.chainid, 
            "EigenLayer_BN254_Pubkey_Registration"
        )));
    }
}
