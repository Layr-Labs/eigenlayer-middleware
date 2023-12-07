// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

<<<<<<< HEAD
import "../../src/BLSPublicKeyCompendium.sol";
import "./util/G2Operations.sol";
=======
import "src/BLSApkRegistry.sol";
import "test/ffi/util/G2Operations.sol";
>>>>>>> 68f3817 (chore: delete BLSPublicKeyCompendium and associated interface)

contract BLSApkRegistryFFITests is G2Operations {
    using BN254 for BN254.G1Point;
    using Strings for uint256;

    Vm cheats = Vm(HEVM_ADDRESS);

    BLSApkRegistry blsApkRegistry;

    uint256 privKey;
    BN254.G1Point pubKeyG1;
    BN254.G2Point pubKeyG2;
    BN254.G1Point signedMessageHash;

    address alice = address(0x69);

    function setUp() public {
        IRegistryCoordinator registryCoordinator;
        blsApkRegistry = new BLSApkRegistry(registryCoordinator);
    }

    function testRegisterBLSPublicKey(uint256 _privKey) public {
        cheats.assume(_privKey != 0);
        _setKeys(_privKey);

        signedMessageHash = _signMessage(alice);

        vm.prank(alice);
        blsApkRegistry.registerBLSPublicKey(signedMessageHash, pubKeyG1, pubKeyG2);

        assertEq(blsApkRegistry.operatorToPubkeyHash(alice), BN254.hashG1Point(pubKeyG1), "pubkey hash not stored correctly");
        assertEq(blsApkRegistry.pubkeyHashToOperator(BN254.hashG1Point(pubKeyG1)), alice, "operator address not stored correctly");
    }

    function _setKeys(uint256 _privKey) internal {
        privKey = _privKey;
        pubKeyG1 = BN254.generatorG1().scalar_mul(_privKey);
        pubKeyG2 = G2Operations.mul(_privKey);
    }

    function _signMessage(address signer) internal view returns(BN254.G1Point memory) {
        BN254.G1Point memory messageHash = blsApkRegistry.getMessageHash(signer);
        return BN254.scalar_mul(messageHash, privKey);
    }
}
