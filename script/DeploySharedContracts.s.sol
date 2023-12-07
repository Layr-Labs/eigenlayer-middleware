// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "../src/BLSPublicKeyCompendium.sol";
import "../src/OperatorStateRetriever.sol";

import "forge-std/Script.sol";
import "forge-std/Test.sol";

// # To load the variables in the .env file
// source .env

// # To deploy and verify our contract
// forge script script/DeploySharedContracts.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
contract DeploySharedContracts is Script, Test {
    Vm cheats = Vm(HEVM_ADDRESS);

    BLSPublicKeyCompendium public blsPublicKeyCompendium;
    OperatorStateRetriever public blsOperatorStateRetriever;

    function run() external {
        vm.startBroadcast();
        blsPublicKeyCompendium = new BLSPublicKeyCompendium();
        blsOperatorStateRetriever = new OperatorStateRetriever();
        vm.stopBroadcast();

        string memory deployed_addresses = "addresses";
        vm.serializeAddress(
            deployed_addresses,
            "blsOperatorStateRetriever",
            address(blsOperatorStateRetriever)
        );
        string memory finalJson = vm.serializeAddress(
            deployed_addresses,
            "blsPublicKeyCompendium",
            address(blsPublicKeyCompendium)
        );
        vm.writeJson(finalJson, outputFileName());
    }

    function outputFileName() internal view returns (string memory) {
        return
            string.concat(
                vm.projectRoot(),
                "/script/output/",
                vm.toString(block.chainid),
                "/shared_contracts_deployment_data.json"
            );
    }
}
