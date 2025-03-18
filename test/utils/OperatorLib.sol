// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";

import {console2 as console} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStakeRegistry} from "../../src/interfaces/IStakeRegistry.sol";
import {ISlashingRegistryCoordinatorTypes} from
    "../../src/interfaces/ISlashingRegistryCoordinator.sol";
import {IRegistryCoordinator} from "../../src/RegistryCoordinator.sol";
import {OperatorStateRetriever} from "../../src/OperatorStateRetriever.sol";
import {RegistryCoordinator} from "../../src/RegistryCoordinator.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {
    IAllocationManager,
    IAllocationManagerTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IBLSApkRegistry, IBLSApkRegistryTypes} from "../../src/interfaces/IBLSApkRegistry.sol";
import {IStrategyFactory} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyFactory.sol";
import {PauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {UpgradeableProxyLib} from "../unit/UpgradeableProxyLib.sol";
import {CoreDeployLib} from "./CoreDeployLib.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {BN254} from "../../src/libraries/BN254.sol";
import {BN256G2} from "./BN256G2.sol";

library OperatorLib {
    using BN254 for *;
    using Strings for uint256;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Wallet {
        uint256 privateKey;
        address addr;
    }

    struct BLSWallet {
        uint256 privateKey;
        BN254.G2Point publicKeyG2;
        BN254.G1Point publicKeyG1;
    }

    struct Operator {
        Wallet key;
        BLSWallet signingKey;
    }

    function createBLSWallet(
        uint256 salt
    ) internal returns (BLSWallet memory) {
        uint256 privateKey = uint256(keccak256(abi.encodePacked(salt)));
        BN254.G1Point memory publicKeyG1 = BN254.generatorG1().scalar_mul(privateKey);
        BN254.G2Point memory publicKeyG2 = mul(privateKey);

        return
            BLSWallet({privateKey: privateKey, publicKeyG2: publicKeyG2, publicKeyG1: publicKeyG1});
    }

    function createWallet(
        uint256 salt
    ) internal pure returns (Wallet memory) {
        uint256 privateKey = uint256(keccak256(abi.encodePacked(salt)));
        address addr = vm.addr(privateKey);

        return Wallet({privateKey: privateKey, addr: addr});
    }

    function createOperator(
        string memory name
    ) internal returns (Operator memory) {
        uint256 salt = uint256(keccak256(abi.encodePacked(name)));
        Wallet memory vmWallet = createWallet(salt);
        BLSWallet memory blsWallet = createBLSWallet(salt);

        return Operator({key: vmWallet, signingKey: blsWallet});
    }

    function mul(
        uint256 x
    ) internal returns (BN254.G2Point memory g2Point) {
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

    function signWithOperatorKey(
        Operator memory operator,
        bytes32 digest
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator.key.privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function signWithSigningKey(
        Operator memory operator,
        bytes32 digest
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator.signingKey.privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function aggregate(
        BN254.G2Point memory pk1,
        BN254.G2Point memory pk2
    ) internal view returns (BN254.G2Point memory apk) {
        (apk.X[0], apk.X[1], apk.Y[0], apk.Y[1]) = BN256G2.ECTwistAdd(
            pk1.X[0], pk1.X[1], pk1.Y[0], pk1.Y[1], pk2.X[0], pk2.X[1], pk2.Y[0], pk2.Y[1]
        );
    }

    function mintMockTokens(Operator memory operator, address token, uint256 amount) internal {
        ERC20Mock(token).mint(operator.key.addr, amount);
    }

    function depositTokenIntoStrategy(
        Operator memory,
        address strategyManager,
        address strategy,
        address token,
        uint256 amount
    ) internal returns (uint256) {
        /// TODO :make sure strategy associated with token
        IStrategy strategy = IStrategy(strategy);
        require(address(strategy) != address(0), "Strategy was not found");
        IStrategyManager strategyManager = IStrategyManager(strategyManager);

        ERC20Mock(token).approve(address(strategyManager), amount);
        uint256 shares = strategyManager.depositIntoStrategy(strategy, IERC20(token), amount);

        return shares;
    }

    function registerAsOperator(Operator memory operator, address delegationManager) internal {
        IDelegationManager delegationManagerInstance = IDelegationManager(delegationManager);

        delegationManagerInstance.registerAsOperator(operator.key.addr, 0, "");
    }

    function registerOperatorToAVS_M2(
        Operator memory operator,
        address avsDirectory,
        address serviceManager,
        address registryCoordinator,
        bytes memory quorumNumbers,
        string memory socket
    ) internal {
        IAVSDirectory avsDirectoryInstance = IAVSDirectory(avsDirectory);
        RegistryCoordinator registryCoordinatorInstance = RegistryCoordinator(registryCoordinator);

        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, operator.key.addr));
        uint256 expiry = block.timestamp + 1 hours;

        bytes32 operatorRegistrationDigestHash = avsDirectoryInstance
            .calculateOperatorAVSRegistrationDigestHash(operator.key.addr, serviceManager, salt, expiry);

        bytes memory signature = signWithOperatorKey(operator, operatorRegistrationDigestHash);
        // Get the pubkey registration message hash that needs to be signed
        bytes32 pubkeyRegistrationMessageHash =
            registryCoordinatorInstance.calculatePubkeyRegistrationMessageHash(operator.key.addr);

        // Sign the pubkey registration message hash
        BN254.G1Point memory blsSig =
            signMessage(operator.signingKey, pubkeyRegistrationMessageHash);

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory params = IBLSApkRegistryTypes
            .PubkeyRegistrationParams({
            pubkeyG1: operator.signingKey.publicKeyG1,
            pubkeyG2: operator.signingKey.publicKeyG2,
            pubkeyRegistrationSignature: blsSig
        });

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature =
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry({
            signature: signature,
            salt: salt,
            expiry: expiry
        });

        // Call the registerOperator function on the registry
        registryCoordinatorInstance.registerOperator(
            quorumNumbers, socket, params, operatorSignature
        );
    }

    function deregisterOperatorFromAVS_M2(
        Operator memory operator,
        address registryCoordinator
    ) internal {
        vm.prank(operator.key.addr);
        RegistryCoordinator(registryCoordinator).deregisterOperator("");
    }

    function registerOperatorFromAVS_OpSet(
        Operator memory operator,
        address allocationManager,
        address registryCoordinator,
        address avs,
        uint32[] memory operatorSetIds
    ) internal {
        bytes memory registrationParamsData;
        IAllocationManager allocationManagerInstance = IAllocationManager(allocationManager);

        // Get the pubkey registration message hash that needs to be signed
        bytes32 pubkeyRegistrationMessageHash = RegistryCoordinator(registryCoordinator)
            .calculatePubkeyRegistrationMessageHash(operator.key.addr);

        // Sign the pubkey registration message hash
        BN254.G1Point memory signature =
            signMessage(operator.signingKey, pubkeyRegistrationMessageHash);

        IBLSApkRegistryTypes.PubkeyRegistrationParams memory blsParams = IBLSApkRegistryTypes
            .PubkeyRegistrationParams({
            pubkeyG1: operator.signingKey.publicKeyG1,
            pubkeyG2: operator.signingKey.publicKeyG2,
            pubkeyRegistrationSignature: signature
        });

        registrationParamsData = abi.encode(
            ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL,
            "test-socket", // Random socket string
            blsParams
        );

        IAllocationManagerTypes.RegisterParams memory params = IAllocationManagerTypes
            .RegisterParams({avs: avs, operatorSetIds: operatorSetIds, data: registrationParamsData});

        // Register the operator in the Allocation Manager
        allocationManagerInstance.registerForOperatorSets(operator.key.addr, params);
    }

    function deregisterOperatorFromAVS_OpSet(
        Operator memory operator,
        address allocationManager,
        address avs,
        uint32[] calldata operatorSetIds
    ) internal {
        IAllocationManager allocationManagerInstance = IAllocationManager(allocationManager);

        IAllocationManagerTypes.DeregisterParams memory params = IAllocationManagerTypes
            .DeregisterParams({operator: operator.key.addr, avs: avs, operatorSetIds: operatorSetIds});

        // Deregister the operator in the Allocation Manager
        allocationManagerInstance.deregisterFromOperatorSets(params);
    }

    function setAllocationDelay(
        Operator memory operator,
        address allocationManager,
        uint32 delay
    ) internal {
        IAllocationManager allocationManagerInstance = IAllocationManager(allocationManager);

        // Set the allocation delay for the operator
        allocationManagerInstance.setAllocationDelay(operator.key.addr, delay);
    }

    function modifyOperatorAllocations(
        Operator memory operator,
        address allocationManager,
        IAllocationManagerTypes.AllocateParams[] memory params
    ) internal {
        IAllocationManager allocationManagerInstance = IAllocationManager(allocationManager);

        allocationManagerInstance.modifyAllocations(operator.key.addr, params);
    }

    function createAndAddOperator(
        uint256 salt
    ) internal returns (Operator memory) {
        Wallet memory operatorKey = createWallet(salt);
        BLSWallet memory signingKey = createBLSWallet(salt);

        Operator memory newOperator = Operator({key: operatorKey, signingKey: signingKey});

        return newOperator;
    }

    function signMessage(
        BLSWallet memory blsWallet,
        bytes32 messageHash
    ) internal view returns (BN254.G1Point memory) {
        // Hash the message to a point on G1
        BN254.G1Point memory messagePoint = BN254.hashToG1(messageHash);

        // Sign by multiplying the hashed message point with the private key
        return messagePoint.scalar_mul(blsWallet.privateKey);
    }

    function signMessageWithOperator(
        Operator memory operator,
        bytes32 messageHash
    ) internal view returns (BN254.G1Point memory) {
        return signMessage(operator.signingKey, messageHash);
    }
}
