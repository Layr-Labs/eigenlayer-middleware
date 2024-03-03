// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

contract Utils is Script {
    function convertBoolToString(bool input) public pure returns (string memory) {
        if (input) {
            return "true";
        } else {
            return "false";
        }
    }

    // Forge scripts best practice: https://book.getfoundry.sh/tutorials/best-practices#scripts
    function readInput(string memory inputFileName) internal view returns (string memory) {
        string memory inputDir = string.concat(vm.projectRoot(), "/script/input/");
        string memory chainDir = string.concat(vm.toString(block.chainid), "/");
        string memory file = string.concat(inputFileName, ".json");
        return vm.readFile(string.concat(inputDir, chainDir, file));
    }

    function readOutput(string memory outputFileName) internal view returns (string memory) {
        string memory inputDir = string.concat(vm.projectRoot(), "/script/output/");
        string memory chainDir = string.concat(vm.toString(block.chainid), "/");
        string memory file = string.concat(outputFileName, ".json");
        return vm.readFile(string.concat(inputDir, chainDir, file));
    }

    function writeOutput(string memory outputJson, string memory outputFileName) internal {
        string memory outputDir = string.concat(vm.projectRoot(), "/script/output/");
        string memory chainDir = string.concat(vm.toString(block.chainid), "/");
        string memory outputFilePath = string.concat(outputDir, chainDir, outputFileName, ".json");
        vm.writeJson(outputJson, outputFilePath);
    }
}
