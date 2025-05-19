// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {BN254} from "./libraries/BN254.sol";

/**
 * @title KeyRegistrar
 * @notice A core singleton contract that manages operator keys for different AVSs
 * @dev Provides registration, deregistration, and rotation of keys with support for aggregate keys
 */
contract KeyRegistrar is Initializable, OwnableUpgradeable {
    using BN254 for BN254.G1Point;

    /// @dev Returns the hash of the zero pubkey for BN254 aka BN254.G1Point(0,0)
    bytes32 internal constant ZERO_PK_HASH = hex"ad3228b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5";

    /// @dev Enum defining supported curve types
    enum CurveType {
        ECDSA,
        BN254
        // BLS12_381 // Future support
    }

    /// @dev Structure to store key information across different curves
    struct KeyInfo {
        bool isRegistered;
        uint256 lastRotationBlock;
    }

    /// @dev Maps (AVS, operator, curve type) to key info
    mapping(address => mapping(address => mapping(CurveType => KeyInfo))) private avsOperatorKeyInfo;

    /// @dev Maps (AVS, operator) to their ECDSA public keys
    mapping(address => mapping(address => bytes)) private avsOperatorToECDSAKey;

    /// @dev Maps (AVS, operator) to their BN254 G1 points
    mapping(address => mapping(address => BN254.G1Point)) private avsOperatorToBN254Key;

    /// @dev Maps (AVS, operator) to their BN254 G2 points (for BLS verification)
    mapping(address => mapping(address => BN254.G2Point)) private avsOperatorToBN254KeyG2;

    /// @dev Maps (AVS, operator, curve type) to key hash for quick lookup
    mapping(address => mapping(address => mapping(CurveType => bytes32))) private avsOperatorToKeyHash;

    /// @dev Maps (AVS, curve type, key hash) to operator address for reverse lookup
    mapping(address => mapping(CurveType => mapping(bytes32 => address))) private avsKeyHashToOperator;

    /// @dev Maps (AVS, operatorSetId) to their aggregate BN254 G1 point
    mapping(address => mapping(uint32 => BN254.G1Point)) private avsOperatorSetToAggregateBN254Key;

    /// @dev Maps AVS to their authorized registrar contract
    mapping(address => address) public avsToRegistrar;

    /// @dev Optional delay period before a key rotation takes effect (in blocks)
    uint256 public rotationDelay;

    /// Events
    event RegistrarAuthorized(address indexed avs, address indexed registrar);
    event KeyRegistered(address indexed avs, address indexed operator, CurveType curveType, bytes pubkey);
    event KeyDeregistered(address indexed avs, address indexed operator, CurveType curveType);
    event KeyRotationInitiated(address indexed avs, address indexed operator, CurveType curveType, bytes oldKey, bytes newKey, uint256 effectiveBlock);
    event AggregateBN254KeyUpdated(address indexed avs, uint32 indexed operatorSetId, BN254.G1Point newAggregateKey);
    event RotationDelayUpdated(uint256 oldDelay, uint256 newDelay);

    /// Errors
    error KeyAlreadyRegistered();
    error KeyNotRegistered();
    error InvalidKeyFormat();
    error ZeroAddress();
    error ZeroPubkey();
    error KeyRotationInProgress();
    error InvalidCurveType();
    error Unauthorized();
    error OperatorNotFound();

    /// @dev Only the authorized registrar for an AVS can call functions with this modifier
    modifier onlyAVSRegistrar(address avs) {
        if (msg.sender != avsToRegistrar[avs] && msg.sender != owner()) {
            revert Unauthorized();
        }
        _;
    }

    /// @dev Initializes the contract
    /// @param initialRotationDelay Initial key rotation delay in blocks
    function initialize(uint256 initialRotationDelay) external initializer {
        __Ownable_init();
        rotationDelay = initialRotationDelay;
    }

    /**
     * @notice Authorize a registrar contract for a specific AVS
     * @param registrar Address of the registrar contract
     */
    function authorizeRegistrar(address registrar) external {
        if (registrar == address(0)) {
            revert ZeroAddress();
        }
        avsToRegistrar[msg.sender] = registrar;
        emit RegistrarAuthorized(msg.sender, registrar);
    }

    /**
     * @notice Registers a new cryptographic key for an operator with a specific AVS
     * @param avs Address of the AVS
     * @param operator Address of the operator
     * @param operatorSetIds Array of operator set IDs to add the operator to (only for BN254 keys)
     * @param curveType Type of curve (ECDSA, BN254)
     * @param pubkey Public key bytes
     * @return alreadyRegistered True if the key was already registered
     */
    function registerKey(
        address avs,
        address operator,
        uint32[] calldata operatorSetIds,
        CurveType curveType,
        bytes calldata pubkey
    ) external onlyAVSRegistrar(avs) returns (bool alreadyRegistered) {
        if (avs == address(0) || operator == address(0)) {
            revert ZeroAddress();
        }
        
        // Check if the key is already registered
        if (avsOperatorKeyInfo[avs][operator][curveType].isRegistered) {
            return true;
        }

        // Validate key format and register based on curve type
        if (curveType == CurveType.ECDSA) {
            _registerECDSAKey(avs, operator, pubkey);
        } else if (curveType == CurveType.BN254) {
            BN254.G1Point memory operatorKey = _registerBN254Key(avs, operator, pubkey);
            
            // Update aggregate keys for specified operator sets
            for (uint256 i = 0; i < operatorSetIds.length; i++) {
                uint32 operatorSetId = operatorSetIds[i];
                _updateAggregateBN254Key(avs, operatorSetId, operatorKey, true);
            }
        } else {
            revert InvalidCurveType();
        }

        // Update key info
        avsOperatorKeyInfo[avs][operator][curveType] = KeyInfo({
            isRegistered: true,
            lastRotationBlock: block.number
        });

        emit KeyRegistered(avs, operator, curveType, pubkey);
        return false;
    }

    /**
     * @notice Deregisters a cryptographic key for an operator with a specific AVS
     * @param avs Address of the AVS
     * @param operator Address of the operator
     * @param operatorSetIds Array of operator set IDs to remove the operator from (only for BN254 keys)
     * @param curveType Type of curve (ECDSA, BN254)
     * @return removed True if the key was removed
     */
    function deregisterKey(
        address avs,
        address operator,
        uint32[] calldata operatorSetIds,
        CurveType curveType
    ) external onlyAVSRegistrar(avs) returns (bool removed) {
        if (!avsOperatorKeyInfo[avs][operator][curveType].isRegistered) {
            return false;
        }

        // Get the key hash before deleting
        bytes32 keyHash = avsOperatorToKeyHash[avs][operator][curveType];

        // For BN254 keys, update the aggregate keys
        if (curveType == CurveType.BN254) {
            BN254.G1Point memory operatorKey = avsOperatorToBN254Key[avs][operator];
            
            // Update aggregate keys for specified operator sets
            for (uint256 i = 0; i < operatorSetIds.length; i++) {
                uint32 operatorSetId = operatorSetIds[i];
                _updateAggregateBN254Key(avs, operatorSetId, operatorKey, false);
            }
        }

        // Reset key storage based on curve type
        if (curveType == CurveType.ECDSA) {
            delete avsOperatorToECDSAKey[avs][operator];
        } else if (curveType == CurveType.BN254) {
            delete avsOperatorToBN254Key[avs][operator];
            delete avsOperatorToBN254KeyG2[avs][operator];
        }

        // Clear mappings
        delete avsKeyHashToOperator[avs][curveType][keyHash];
        delete avsOperatorToKeyHash[avs][operator][curveType];
        delete avsOperatorKeyInfo[avs][operator][curveType];

        emit KeyDeregistered(avs, operator, curveType);
        return true;
    }

    /**
     * @notice Checks if a key is registered for an operator with a specific AVS
     * @param avs Address of the AVS
     * @param operator Address of the operator
     * @param curveType Type of curve (ECDSA, BN254)
     * @return True if the key is registered
     */
    function isRegistered(
        address avs,
        address operator,
        CurveType curveType
    ) external view returns (bool) {
        return avsOperatorKeyInfo[avs][operator][curveType].isRegistered;
    }

    /**
     * @notice Initiates key rotation for an operator with a specific AVS
     * @param avs Address of the AVS
     * @param operator Address of the operator
     * @param operatorSetIds Array of operator set IDs to update (only for BN254 keys)
     * @param curveType Type of curve (ECDSA, BN254)
     * @param newPubkey New public key bytes
     */
    function rotateKey(
        address avs,
        address operator,
        uint32[] calldata operatorSetIds,
        CurveType curveType,
        bytes calldata newPubkey
    ) external onlyAVSRegistrar(avs) {
        // Check if key is registered
        if (!avsOperatorKeyInfo[avs][operator][curveType].isRegistered) {
            revert KeyNotRegistered();
        }

        // Get old key
        bytes memory oldKey;
        if (curveType == CurveType.ECDSA) {
            oldKey = avsOperatorToECDSAKey[avs][operator];
            _registerECDSAKey(avs, operator, newPubkey);
        } else if (curveType == CurveType.BN254) {
            BN254.G1Point memory oldKeyPoint = avsOperatorToBN254Key[avs][operator];
            oldKey = abi.encode(oldKeyPoint.X, oldKeyPoint.Y);
            
            // Register new key
            BN254.G1Point memory newKeyPoint = _registerBN254Key(avs, operator, newPubkey);
            
            // Update all specified operator sets
            for (uint256 i = 0; i < operatorSetIds.length; i++) {
                uint32 operatorSetId = operatorSetIds[i];
                _updateOperatorSetAggregateBN254Key(avs, operatorSetId, oldKeyPoint, newKeyPoint);
            }
        } else {
            revert InvalidCurveType();
        }

        // Update rotation timestamp
        uint256 effectiveBlock = block.number + rotationDelay;
        avsOperatorKeyInfo[avs][operator][curveType].lastRotationBlock = effectiveBlock;

        emit KeyRotationInitiated(avs, operator, curveType, oldKey, newPubkey, effectiveBlock);
    }

    /**
     * @notice Update an operator set's aggregate BN254 key
     * @param avs Address of the AVS
     * @param operatorSetId ID of the operator set
     * @param key BN254 key to add or remove
     * @param isAddition True to add the key, false to remove it
     */
    function _updateAggregateBN254Key(
        address avs,
        uint32 operatorSetId,
        BN254.G1Point memory key,
        bool isAddition
    ) internal {
        BN254.G1Point memory currentApk = avsOperatorSetToAggregateBN254Key[avs][operatorSetId];
        BN254.G1Point memory newApk;
        
        if (isAddition) {
            newApk = currentApk.plus(key);
        } else {
            newApk = currentApk.plus(key.negate());
        }
        
        avsOperatorSetToAggregateBN254Key[avs][operatorSetId] = newApk;
        
        emit AggregateBN254KeyUpdated(avs, operatorSetId, newApk);
    }

    /**
     * @notice Update an operator set's aggregate BN254 key when an operator's key is rotated
     * @param avs Address of the AVS
     * @param operatorSetId ID of the operator set
     * @param oldKey Old BN254 key
     * @param newKey New BN254 key
     */
    function _updateOperatorSetAggregateBN254Key(
        address avs,
        uint32 operatorSetId,
        BN254.G1Point memory oldKey,
        BN254.G1Point memory newKey
    ) internal {
        BN254.G1Point memory currentApk = avsOperatorSetToAggregateBN254Key[avs][operatorSetId];
        // Remove old key and add new key
        BN254.G1Point memory newApk = currentApk.plus(oldKey.negate()).plus(newKey);
        avsOperatorSetToAggregateBN254Key[avs][operatorSetId] = newApk;
        
        emit AggregateBN254KeyUpdated(avs, operatorSetId, newApk);
    }

    /**
     * @notice Gets the aggregate BN254 public key for an operator set
     * @param avs Address of the AVS
     * @param operatorSetId ID of the operator set
     * @return The aggregate BN254 G1 public key
     */
    function getApk(
        address avs,
        uint32 operatorSetId
    ) external view returns (BN254.G1Point memory) {
        return avsOperatorSetToAggregateBN254Key[avs][operatorSetId];
    }

    /**
     * @notice Sets the rotation delay for key rotations
     * @param newDelay New delay in blocks
     */
    function setRotationDelay(uint256 newDelay) external onlyOwner {
        uint256 oldDelay = rotationDelay;
        rotationDelay = newDelay;
        emit RotationDelayUpdated(oldDelay, newDelay);
    }

    /**
     * @notice Gets the BN254 public key for an operator with a specific AVS
     * @param avs Address of the AVS
     * @param operator Address of the operator
     * @return pubkey The BN254 G1 public key
     */
    function getBN254Key(address avs, address operator) external view returns (BN254.G1Point memory) {
        return avsOperatorToBN254Key[avs][operator];
    }

    /**
     * @notice Gets the BN254 G2 public key for an operator with a specific AVS
     * @param avs Address of the AVS
     * @param operator Address of the operator
     * @return pubkeyG2 The BN254 G2 public key
     */
    function getBN254KeyG2(address avs, address operator) external view returns (BN254.G2Point memory) {
        return avsOperatorToBN254KeyG2[avs][operator];
    }

    /**
     * @notice Gets the ECDSA public key for an operator with a specific AVS
     * @param avs Address of the AVS
     * @param operator Address of the operator
     * @return pubkey The ECDSA public key
     */
    function getECDSAKey(address avs, address operator) external view returns (bytes memory) {
        return avsOperatorToECDSAKey[avs][operator];
    }

    /**
     * @notice Gets the operator address from a key hash for a specific AVS
     * @param avs Address of the AVS
     * @param curveType Type of curve
     * @param keyHash Hash of the key
     * @return operator The operator address
     */
    function getOperatorFromKeyHash(
        address avs,
        CurveType curveType,
        bytes32 keyHash
    ) external view returns (address) {
        return avsKeyHashToOperator[avs][curveType][keyHash];
    }

    /**
     * @notice Gets the key hash for an operator with a specific AVS
     * @param avs Address of the AVS
     * @param operator Address of the operator
     * @param curveType Type of curve
     * @return keyHash The key hash
     */
    function getKeyHash(
        address avs,
        address operator,
        CurveType curveType
    ) external view returns (bytes32) {
        return avsOperatorToKeyHash[avs][operator][curveType];
    }

    /**
     * @notice Registers an ECDSA key for an operator with a specific AVS
     * @param avs Address of the AVS
     * @param operator Address of the operator
     * @param pubkey ECDSA public key bytes
     */
    function _registerECDSAKey(
        address avs,
        address operator,
        bytes memory pubkey
    ) internal {
        if (pubkey.length != 65) {
            revert InvalidKeyFormat();
        }

        bytes32 keyHash = keccak256(pubkey);
        address existingOperator = avsKeyHashToOperator[avs][CurveType.ECDSA][keyHash];
        
        if (existingOperator != address(0) && existingOperator != operator) {
            revert KeyAlreadyRegistered();
        }

        avsOperatorToECDSAKey[avs][operator] = pubkey;
        avsOperatorToKeyHash[avs][operator][CurveType.ECDSA] = keyHash;
        avsKeyHashToOperator[avs][CurveType.ECDSA][keyHash] = operator;
    }

    /**
     * @notice Registers a BN254 key for an operator with a specific AVS
     * @param avs Address of the AVS
     * @param operator Address of the operator
     * @param pubkey BN254.G1Point and BN254.G2Point encoded as bytes
     * @return The registered BN254.G1Point
     */
    function _registerBN254Key(
        address avs,
        address operator,
        bytes memory pubkey
    ) internal returns (BN254.G1Point memory) {
        // Decode BN254 G1 and G2 points from the pubkey bytes
        (uint256 g1X, uint256 g1Y, uint256[2] memory g2X, uint256[2] memory g2Y) = 
            abi.decode(pubkey, (uint256, uint256, uint256[2], uint256[2]));

        // Validate G1 point
        BN254.G1Point memory g1Point = BN254.G1Point(g1X, g1Y);
        if (g1X == 0 && g1Y == 0) {
            revert ZeroPubkey();
        }

        // Create G2 point
        BN254.G2Point memory g2Point = BN254.G2Point(g2X, g2Y);

        // Verify that G1 and G2 form a valid keypair
        require(
            BN254.pairing(g1Point, BN254.negGeneratorG2(), BN254.generatorG1(), g2Point),
            "Invalid BLS keypair"
        );

        // Calculate key hash
        bytes32 keyHash = BN254.hashG1Point(g1Point);
        address existingOperator = avsKeyHashToOperator[avs][CurveType.BN254][keyHash];
        
        if (existingOperator != address(0) && existingOperator != operator) {
            revert KeyAlreadyRegistered();
        }

        // Store the key
        avsOperatorToBN254Key[avs][operator] = g1Point;
        avsOperatorToBN254KeyG2[avs][operator] = g2Point;
        avsOperatorToKeyHash[avs][operator][CurveType.BN254] = keyHash;
        avsKeyHashToOperator[avs][CurveType.BN254][keyHash] = operator;
        
        return g1Point;
    }
}