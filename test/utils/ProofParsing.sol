// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../../src/libraries/BN254.sol";
import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

contract ProofParsing is Test {
    string internal proofConfigJson;
    string prefix;

    bytes32[18] blockHeaderProof;
    bytes32[3] slotProof;
    bytes32[9] withdrawalProof;
    bytes32[46] validatorProof;
    bytes32[44] historicalSummaryProof;

    bytes32[7] executionPayloadProof;
    bytes32[4] timestampProofs;

    bytes32 slotRoot;
    bytes32 executionPayloadRoot;


    function getSlot() public view returns (uint256) {
        return stdJson.readUint(proofConfigJson, ".slot");
    }







    function getBlockRoot() public view returns (bytes32) {
        return stdJson.readBytes32(proofConfigJson, ".blockHeaderRoot");
    }















    function getValidatorFields() public returns (bytes32[] memory) {
        bytes32[] memory validatorFields = new bytes32[](8);
        for (uint256 i = 0; i < 8; i++) {
            prefix = string.concat(".ValidatorFields[", string.concat(vm.toString(i), "]"));
            validatorFields[i] = (stdJson.readBytes32(proofConfigJson, prefix));
        }
        return validatorFields;
    }




}
