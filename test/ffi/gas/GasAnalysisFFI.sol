// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "../FFIBase.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract GasAnalysisFFITests is FFIBase {
    using BN254 for BN254.G1Point;
    using Strings for uint256;

    string dataPath = "test/ffi/gas/output/gas_data.json";
    BLSSignatureChecker blsSignatureChecker;

    uint64 numOperators = 50;
    uint64 numberOfQuorums = 1;

    bytes message = "eigen";
    bytes32 msgHash;

    function setUp() virtual public {
        defaultMaxOperatorCount = 1000;
        _deployMockEigenLayerAndAVS();
        blsSignatureChecker = new BLSSignatureChecker(registryCoordinator);

        uint256 setQuorumBitmap = (1 << numberOfQuorums) - 1;
        //uint256 setQuorumBitmap = 0;
        msgHash = _setOperators(setQuorumBitmap, numberOfQuorums, numOperators, message);
    }

    function xtestIncreasingNonSigners() public {

        string memory parent_object = "parent object";
        string memory new_data;

        for(uint64 numNonSigners = 0; numNonSigners <= numOperators; numNonSigners++) {

            (
                bytes memory quorumNumbers, 
                uint32 referenceBlockNumber, 
                BLSSignatureChecker.NonSignerStakesAndSignature memory nonSignerStakesAndSignature
            ) = _getNonSignerStakeAndSignatures(
                numOperators, 
                numNonSigners, 
                numberOfQuorums
            );

            uint256 gasBefore = gasleft();
            blsSignatureChecker.checkSignatures(
                msgHash, 
                quorumNumbers,
                referenceBlockNumber, 
                nonSignerStakesAndSignature
            );
            uint256 gasAfter = gasleft();
            uint256 gasCost = gasBefore - gasAfter;

            if(numNonSigners > 9){
                new_data = vm.serializeUint(parent_object, uint256(numNonSigners).toString(), gasCost);
            } else {
                new_data = vm.serializeUint(parent_object, string.concat("0", uint256(numNonSigners).toString()), gasCost);
            }

            console.log("numNonSigners: %s, gasCost: %s", numNonSigners, gasCost);
        }

        //vm.writeJson(new_data, dataPath, string.concat(".", uint256(numberOfQuorums).toString()));

    }

}