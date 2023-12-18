// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "../../src/BLSApkRegistry.sol";
import "../ffi/util/G2Operations.sol";
import {IBLSApkRegistry} from "../../src/interfaces/IBLSApkRegistry.sol";

contract BLSApkRegistryFFITests is G2Operations {
    using BN254 for BN254.G1Point;
    using Strings for uint256;

    Vm cheats = Vm(HEVM_ADDRESS);

    BLSApkRegistry blsApkRegistry;
    IRegistryCoordinator registryCoordinator;

    uint256 privKey;
    IBLSApkRegistry.PubkeyRegistrationParams pubkeyRegistrationParams;

    address alice = address(0x69);

    function setUp() public {
        blsApkRegistry = new BLSApkRegistry(registryCoordinator);
    }

    function testRegisterBLSPublicKey(uint256 _privKey) public {
        cheats.assume(_privKey != 0);
        _setKeys(_privKey);

        pubkeyRegistrationParams.pubkeyRegistrationSignature = _signMessage(alice);

        vm.prank(address(registryCoordinator));
        blsApkRegistry.registerBLSPublicKey(alice, pubkeyRegistrationParams, registryCoordinator.pubkeyRegistrationMessageHash(alice));

        assertEq(blsApkRegistry.operatorToPubkeyHash(alice), BN254.hashG1Point(pubkeyRegistrationParams.pubkeyG1),
            "pubkey hash not stored correctly");
        assertEq(blsApkRegistry.pubkeyHashToOperator(BN254.hashG1Point(pubkeyRegistrationParams.pubkeyG1)), alice,
            "operator address not stored correctly");
    }

    function _setKeys(uint256 _privKey) internal {
        privKey = _privKey;
        pubkeyRegistrationParams.pubkeyG1 = BN254.generatorG1().scalar_mul(_privKey);
        pubkeyRegistrationParams.pubkeyG2 = G2Operations.mul(_privKey);
    }

    function _signMessage(address signer) internal view returns(BN254.G1Point memory) {
        BN254.G1Point memory messageHash = registryCoordinator.pubkeyRegistrationMessageHash(signer);
        return BN254.scalar_mul(messageHash, privKey);
    }
}
