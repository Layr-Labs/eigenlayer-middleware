// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {BN254} from "src/libraries/BN254.sol";
import {BN256G2} from "./BN256G2.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

library OperatorLib {
    using BN254 for *;
    using Strings for uint256;

    struct Wallet {
        uint256 privateKey;
        address addr;
    }

    struct BLSWallet {
        uint256 privateKey;
        BN254.G2Point publicKeyG2;
        BN254.G1Point publicKeyG1;
    }

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Operator {
        Wallet key;
        BLSWallet signingKey;
    }

    function createBLSWallet(uint256 salt) internal returns (BLSWallet memory) {
        uint256 privateKey = uint256(keccak256(abi.encodePacked(salt)));
        BN254.G1Point memory publicKeyG1 = BN254.generatorG1().scalar_mul(privateKey);
        BN254.G2Point memory publicKeyG2 = mul(privateKey);

        return BLSWallet({
            privateKey: privateKey,
            publicKeyG2: publicKeyG2,
            publicKeyG1: publicKeyG1
        });
    }

    function createWallet(uint256 salt) internal pure returns (Wallet memory) {
        uint256 privateKey = uint256(keccak256(abi.encodePacked(salt)));
        address addr = vm.addr(privateKey);

        return Wallet({
            privateKey: privateKey,
            addr: addr
        });
    }

    function createOperator(string memory name) internal returns (Operator memory) {
        uint256 salt = uint256(keccak256(abi.encodePacked(name)));
        Wallet memory vmWallet = createWallet(salt);
        BLSWallet memory blsWallet = createBLSWallet(salt);

        return Operator({
            key: vmWallet,
            signingKey: blsWallet
        });
    }

        function mul(uint256 x) internal returns (BN254.G2Point memory g2Point) {
        string[] memory inputs = new string[](5);
        inputs[0] = "go";
        inputs[1] = "run";
        inputs[2] = "test/ffi/go/g2mul.go";
        inputs[3] = x.toString();

        inputs[4] = "1";
        bytes memory res = vm.ffi(inputs);
        g2Point.X[1] = abi.decode(res, (uint256));

        inputs[4] = "2";
        res = vm.ffi(inputs);
        g2Point.X[0] = abi.decode(res, (uint256));

        inputs[4] = "3";
        res = vm.ffi(inputs);
        g2Point.Y[1] = abi.decode(res, (uint256));

        inputs[4] = "4";
        res = vm.ffi(inputs);
        g2Point.Y[0] = abi.decode(res, (uint256));
    }

}