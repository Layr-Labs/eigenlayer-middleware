// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "forge-std/Script.sol";
import {RegistryCoordinatorMock} from "../test/mocks/RegistryCoordinatorMock.sol";
import {BLSApkRegistryMock} from "../test/mocks/BLSApkRegistryMock.sol";
import {BLSApkRegistry} from "../src/BLSApkRegistry.sol";

import {IBLSApkRegistry} from "../src/interfaces/IBLSApkRegistry.sol";
import {BN254} from "../src/libraries/BN254.sol";
import "forge-std/Test.sol";


contract TestRegistryDeploy is Script {
    using BN254 for BN254.G1Point;
    Vm cheats = Vm(VM_ADDRESS);

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        RegistryCoordinatorMock registryCoordMock = new RegistryCoordinatorMock();
        BLSApkRegistryMock registry = new BLSApkRegistryMock(registryCoordMock);
        // vm.stopBroadcast(); 



        // vm.startBroadcast(address(registryCoordMock));

        address operator = address(123);

        IBLSApkRegistry.PubkeyRegistrationParams memory pubkeyRegistrationParams;

        uint256 privKey = 69;
        pubkeyRegistrationParams.pubkeyG1 = BN254.generatorG1().scalar_mul(
            privKey
        );

        BN254.G1Point memory defaultPubkey = pubkeyRegistrationParams.pubkeyG1;
        bytes32 defaultPubkeyHash = BN254.hashG1Point(defaultPubkey);

        //privKey*G2
        pubkeyRegistrationParams.pubkeyG2.X[
                1
            ] = 19_101_821_850_089_705_274_637_533_855_249_918_363_070_101_489_527_618_151_493_230_256_975_900_223_847;
        pubkeyRegistrationParams.pubkeyG2.X[
                0
            ] = 5_334_410_886_741_819_556_325_359_147_377_682_006_012_228_123_419_628_681_352_847_439_302_316_235_957;
        pubkeyRegistrationParams.pubkeyG2.Y[
                1
            ] = 354_176_189_041_917_478_648_604_979_334_478_067_325_821_134_838_555_150_300_539_079_146_482_658_331;
        pubkeyRegistrationParams.pubkeyG2.Y[
                0
            ] = 4_185_483_097_059_047_421_902_184_823_581_361_466_320_657_066_600_218_863_748_375_739_772_335_928_910;

        // BN254.G1Point memory messageHash = registryCoordMock
        //     .pubkeyRegistrationMessageHash(operator);
        // pubkeyRegistrationParams.pubkeyRegistrationSignature = _signMessage(
        //     operator
        // );
        BN254.G1Point memory messageHash;


        // cheats.startPrank(address(registryCoordMock));
        registry.registerBLSPublicKey(
            operator,
            pubkeyRegistrationParams,
            messageHash
         );
        //  cheats.stopPrank();

        vm.stopBroadcast();
    }


    // function _signMessage(
    //     address signer
    // ) internal view returns (BN254.G1Point memory) {
    //     BN254.G1Point memory messageHash = registryCoordinator
    //         .pubkeyRegistrationMessageHash(signer);
    //     return BN254.scalar_mul(messageHash, privKey);
    // }
}