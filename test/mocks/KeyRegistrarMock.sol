// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    IKeyRegistrarTypes,
    IKeyRegistrar,
    BN254
} from "eigenlayer-contracts/src/contracts/interfaces//IKeyRegistrar.sol";
import {
    OperatorSetLib,
    OperatorSet
} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {ISemVerMixin} from "eigenlayer-contracts/src/contracts/interfaces/ISemVerMixin.sol";

contract KeyRegistrarMock is IKeyRegistrar {
    using OperatorSetLib for OperatorSet;

    mapping(bytes32 operatorSetKey => mapping(address => bool)) internal _operatorRegistered;

    function setIsRegistered(
        address operator,
        OperatorSet calldata operatorSet,
        bool _isRegistered
    ) external {
        bytes32 operatorSetKey = operatorSet.key();
        _operatorRegistered[operatorSetKey][operator] = _isRegistered;
    }

    function initialize(
        address initialOwner
    ) external {}

    function configureOperatorSet(OperatorSet memory operatorSet, CurveType curveType) external {}

    function registerKey(
        address operator,
        OperatorSet memory operatorSet,
        bytes calldata pubkey,
        bytes calldata signature
    ) external {}

    function deregisterKey(address operator, OperatorSet memory operatorSet) external {}

    function isRegistered(
        OperatorSet memory operatorSet,
        address operator
    ) external view returns (bool) {
        return _operatorRegistered[operatorSet.key()][operator];
    }

    function getOperatorSetCurveType(
        OperatorSet memory operatorSet
    ) external pure returns (CurveType) {}

    function getBN254Key(
        OperatorSet memory operatorSet,
        address operator
    ) external view returns (BN254.G1Point memory g1Point, BN254.G2Point memory g2Point) {}

    /**
     * @notice Gets the ECDSA public key for an operator with a specific operator set
     * @param operatorSet The operator set to get the key for
     * @param operator Address of the operator
     * @return pubkey The ECDSA public key
     */
    function getECDSAKey(
        OperatorSet memory operatorSet,
        address operator
    ) external pure returns (bytes memory) {}

    /**
     * @notice Gets the ECDSA public key for an operator with a specific operator set
     * @param operatorSet The operator set to get the key for
     * @param operator Address of the operator
     * @return pubkey The ECDSA public key
     */
    function getECDSAAddress(
        OperatorSet memory operatorSet,
        address operator
    ) external pure returns (address) {}

    function isKeyGloballyRegistered(
        bytes32 keyHash
    ) external view returns (bool) {}

    function getKeyHash(
        OperatorSet memory operatorSet,
        address operator
    ) external pure returns (bytes32) {}

    function verifyBN254Signature(
        bytes32 messageHash,
        bytes memory signature,
        BN254.G1Point memory pubkeyG1,
        BN254.G2Point memory pubkeyG2
    ) external pure {}

    function version() external pure returns (string memory) {
        return "v0.0.1";
    }

    function getECDSAKeyRegistrationMessageHash(
        address operator,
        OperatorSet memory operatorSet,
        address keyAddress
    ) external pure returns (bytes32) {
        return keccak256(abi.encode(operator, operatorSet, keyAddress));
    }

    function getBN254KeyRegistrationMessageHash(
        address operator,
        OperatorSet memory operatorSet,
        bytes calldata keyData
    ) external pure returns (bytes32) {
        return keccak256(abi.encode(operator, operatorSet, keyData));
    }

    function encodeBN254KeyData(
        BN254.G1Point memory g1Point,
        BN254.G2Point memory g2Point
    ) external pure returns (bytes memory) {
        return abi.encode(g1Point, g2Point);
    }

    function getOperatorFromSigningKey(
        OperatorSet memory,
        /**
         * operatorSet
         */
        bytes calldata
    )
        /**
         * keyData
         */
        external
        pure
        returns (address, bool)
    {
        return (address(0), false);
    }

    receive() external payable {}
    fallback() external payable {}
}
