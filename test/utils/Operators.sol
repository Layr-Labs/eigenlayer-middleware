// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../../src/libraries/BN254.sol";
import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

contract Operators is Test {
    string internal operatorConfigJson;

    constructor() {
        operatorConfigJson = vm.readFile("./src/test/test-data/operators.json");
    }

    function operatorPrefix(
        uint256 index
    ) public pure returns (string memory) {
        return string.concat(".operators[", string.concat(vm.toString(index), "]."));
    }

    function getNumOperators() public view returns (uint256) {
        return stdJson.readUint(operatorConfigJson, ".numOperators");
    }

    function getOperatorPubkeyG2(
        uint256 index
    ) public view returns (BN254.G2Point memory) {
        BN254.G2Point memory pubkey = BN254.G2Point({
            X: [
                readUint(operatorConfigJson, index, "PubkeyG2.X.A1"),
                readUint(operatorConfigJson, index, "PubkeyG2.X.A0")
            ],
            Y: [
                readUint(operatorConfigJson, index, "PubkeyG2.Y.A1"),
                readUint(operatorConfigJson, index, "PubkeyG2.Y.A0")
            ]
        });
        return pubkey;
    }

    function readUint(
        string memory json,
        uint256 index,
        string memory key
    ) public pure returns (uint256) {
        return stringToUint(stdJson.readString(json, string.concat(operatorPrefix(index), key)));
    }

    function stringToUint(
        string memory s
    ) public pure returns (uint256) {
        bytes memory b = bytes(s);
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            if (uint256(uint8(b[i])) >= 48 && uint256(uint8(b[i])) <= 57) {
                result = result * 10 + (uint256(uint8(b[i])) - 48);
            }
        }
        return result;
    }
}
