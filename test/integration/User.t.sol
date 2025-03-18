// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// Interfaces
import {
    ISignatureUtilsMixin,
    ISignatureUtilsMixinTypes
} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

// Core
import "eigenlayer-contracts/src/contracts/core/DelegationManager.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import "eigenlayer-contracts/src/contracts/core/StrategyManager.sol";
import "eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";
import "eigenlayer-contracts/src/contracts/core/AllocationManager.sol";

// Middleware
import "../../src/interfaces/IRegistryCoordinator.sol";
import "../../src/RegistryCoordinator.sol";
import "../../src/BLSApkRegistry.sol";
import "../../src/IndexRegistry.sol";
import "../../src/StakeRegistry.sol";
import "../../src/ServiceManagerBase.sol";

import "../../src/libraries/BN254.sol";
import "../../src/libraries/BitmapUtils.sol";
import "./TimeMachine.t.sol";
import "./utils/Sort.t.sol";
import "./utils/BitmapStrings.t.sol";
import "../mocks/ServiceManagerMock.sol";

interface IUserDeployer {
    function slashingRegistryCoordinator() external view returns (SlashingRegistryCoordinator);
    function registryCoordinator() external view returns (RegistryCoordinator);
    function avsDirectory() external view returns (AVSDirectory);
    function allocationManager() external view returns (AllocationManager);
    function serviceManager() external view returns (ServiceManagerMock);
    function timeMachine() external view returns (TimeMachine);
    function churnApproverPrivateKey() external view returns (uint256);
    function churnApprover() external view returns (address);
}

contract User is Test {
    using BN254 for *;
    using Strings for *;
    using BitmapStrings for *;
    using BitmapUtils for *;

    Vm cheats = Vm(VM_ADDRESS);

    // Core contracts
    DelegationManager delegationManager;
    StrategyManager strategyManager;
    AVSDirectory avsDirectory;

    // Middleware contracts
    RegistryCoordinator registryCoordinator;
    ServiceManagerBase serviceManager;
    BLSApkRegistry blsApkRegistry;
    StakeRegistry stakeRegistry;
    IndexRegistry indexRegistry;

    TimeMachine timeMachine;

    uint256 churnApproverPrivateKey;
    address churnApprover;

    string public NAME;
    bytes32 public operatorId;

    // BLS keypair:
    uint256 privKey;
    IBLSApkRegistryTypes.PubkeyRegistrationParams pubkeyParams;

    // EIP1271 sigs:
    mapping(bytes32 => bool) digests;
    uint256 salt = 0;

    constructor(
        string memory name,
        uint256 _privKey,
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory _pubkeyParams
    ) {
        IUserDeployer deployer = IUserDeployer(msg.sender);

        registryCoordinator = deployer.registryCoordinator();
        avsDirectory = deployer.avsDirectory();
        serviceManager = ServiceManagerBase(address(deployer.serviceManager()));

        blsApkRegistry = BLSApkRegistry(address(registryCoordinator.blsApkRegistry()));
        stakeRegistry = StakeRegistry(address(registryCoordinator.stakeRegistry()));
        indexRegistry = IndexRegistry(address(registryCoordinator.indexRegistry()));

        delegationManager = DelegationManager(address(stakeRegistry.delegation()));
        strategyManager = StrategyManager(address(delegationManager.strategyManager()));
        avsDirectory = AVSDirectory(address(serviceManager.avsDirectory()));

        timeMachine = deployer.timeMachine();

        churnApproverPrivateKey = deployer.churnApproverPrivateKey();
        churnApprover = deployer.churnApprover();

        NAME = name;

        // Generate BN254 keypair and registration signature
        privKey = _privKey;
        pubkeyParams = _pubkeyParams;

        BN254.G1Point memory registrationMessageHash =
            registryCoordinator.pubkeyRegistrationMessageHash(address(this));
        pubkeyParams.pubkeyRegistrationSignature = registrationMessageHash.scalar_mul(privKey);

        operatorId = pubkeyParams.pubkeyG1.hashG1Point();
    }

    modifier createSnapshot() virtual {
        timeMachine.createSnapshot();
        _;
    }

    /**
     * Middleware contracts:
     */
    function registerOperator(
        bytes calldata quorums
    ) public virtual createSnapshot returns (bytes32) {
        _log("registerOperator", quorums);

        vm.warp(block.timestamp + 1);

        registryCoordinator.registerOperator({
            quorumNumbers: quorums,
            socket: NAME,
            params: pubkeyParams,
            operatorSignature: _genAVSRegistrationSig()
        });

        return pubkeyParams.pubkeyG1.hashG1Point();
    }

    /// @param churnQuorums Quorums to register for that have an associated churnTarget
    /// @param churnTargets A user that can be churned for each of churnQuorums
    /// @param standardQuorums Any additional quorums to register for that don't require churn
    function registerOperatorWithChurn(
        bytes calldata churnQuorums,
        User[] calldata churnTargets,
        bytes calldata standardQuorums
    ) public virtual createSnapshot {
        _logChurn("registerOperatorWithChurn", churnQuorums, churnTargets, standardQuorums);

        // Sanity check input:
        // - churnQuorums and churnTargets should have equal length
        // - churnQuorums and standardQuorums should not have any bits in common
        uint192 churnBitmap = uint192(churnQuorums.orderedBytesArrayToBitmap());
        uint192 standardBitmap = uint192(standardQuorums.orderedBytesArrayToBitmap());
        assertEq(
            churnQuorums.length,
            churnTargets.length,
            "User.registerOperatorWithChurn: input length mismatch"
        );
        assertTrue(
            churnBitmap.noBitsInCommon(standardBitmap),
            "User.registerOperatorWithChurn: input quorums have common bits"
        );

        bytes memory allQuorums = churnBitmap.plus(standardBitmap).bitmapToBytesArray();

        (
            ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory kickParams,
            ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory churnApproverSignature
        ) = _generateOperatorKickParams(allQuorums, churnQuorums, churnTargets, standardQuorums);

        vm.warp(block.timestamp + 1);
        registryCoordinator.registerOperatorWithChurn({
            quorumNumbers: allQuorums,
            socket: NAME,
            params: pubkeyParams,
            operatorKickParams: kickParams,
            churnApproverSignature: churnApproverSignature,
            operatorSignature: _genAVSRegistrationSig()
        });
    }

    function deregisterOperator(
        bytes calldata quorums
    ) public virtual createSnapshot {
        _log("deregisterOperator", quorums);

        registryCoordinator.deregisterOperator(quorums);
    }

    /// @dev Uses updateOperators to update this user's stake
    function updateStakes() public virtual createSnapshot {
        _log("updateStakes (updateOperators)");

        // get all quorums this operator is registered for
        uint192 currentBitmap = registryCoordinator.getCurrentQuorumBitmap(operatorId);
        bytes memory quorumNumbers = currentBitmap.bitmapToBytesArray();

        // get all operators in those quorums
        address[][] memory operatorsPerQuorum = new address[][](quorumNumbers.length);
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            bytes32[] memory operatorIds = indexRegistry.getOperatorListAtBlockNumber(
                uint8(quorumNumbers[i]), uint32(block.number)
            );
            operatorsPerQuorum[i] = new address[](operatorIds.length);
            for (uint256 j = 0; j < operatorIds.length; j++) {
                operatorsPerQuorum[i][j] = blsApkRegistry.pubkeyHashToOperator(operatorIds[j]);
            }

            operatorsPerQuorum[i] = Sort.sortAddresses(operatorsPerQuorum[i]);
        }
        registryCoordinator.updateOperatorsForQuorum(operatorsPerQuorum, quorumNumbers);
    }

    /**
     * Core contracts:
     */
    function registerAsOperator() public virtual createSnapshot {
        _log("registerAsOperator (core)");

        /// TODO: check
        delegationManager.registerAsOperator(msg.sender, 0, NAME);
    }

    // Deposit LSTs into the StrategyManager. This setup does not use the EPMgr or native ETH.
    function depositIntoEigenlayer(
        IStrategy[] memory strategies,
        uint256[] memory tokenBalances
    ) public virtual createSnapshot {
        _log("depositIntoEigenLayer (core)");

        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy strat = strategies[i];
            uint256 tokenBalance = tokenBalances[i];

            IERC20 underlyingToken = strat.underlyingToken();
            underlyingToken.approve(address(strategyManager), tokenBalance);
            strategyManager.depositIntoStrategy(strat, underlyingToken, tokenBalance);
        }
    }

    function exitEigenlayer()
        public
        virtual
        createSnapshot
        returns (IStrategy[] memory, uint256[] memory)
    {
        _log("exitEigenlayer (core)");

        (IStrategy[] memory strategies, uint256[] memory shares) =
            delegationManager.getDepositedShares(address(this));

        IDelegationManagerTypes.QueuedWithdrawalParams[] memory params =
            new IDelegationManager.QueuedWithdrawalParams[](1);
        params[0] = IDelegationManagerTypes.QueuedWithdrawalParams({
            strategies: strategies,
            depositShares: shares,
            __deprecated_withdrawer: address(this)
        });

        delegationManager.queueWithdrawals(params);

        return (strategies, shares);
    }

    /**
     * EIP1271 Signatures:
     */
    bytes4 internal constant EIP1271_MAGICVALUE = 0x1626ba7e;

    function isValidSignature(bytes32 digestHash, bytes memory) public view returns (bytes4) {
        if (digests[digestHash]) {
            return EIP1271_MAGICVALUE;
        }

        return bytes4(0);
    }

    function pubkeyG1() public view returns (BN254.G1Point memory) {
        return pubkeyParams.pubkeyG1;
    }

    function _genAVSRegistrationSig()
        internal
        returns (ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory)
    {
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory signature =
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry({
            signature: new bytes(0),
            salt: bytes32(salt++),
            expiry: type(uint256).max
        });

        bytes32 digest = avsDirectory.calculateOperatorAVSRegistrationDigestHash({
            operator: address(this),
            avs: address(serviceManager),
            salt: signature.salt,
            expiry: signature.expiry
        });

        digests[digest] = true;
        return signature;
    }

    // Operator0.registerOperator
    function _log(
        string memory s
    ) internal virtual {
        emit log(string.concat(NAME, ".", s));
    }

    // Operator0.registerOperator: 0x00010203...
    function _log(string memory s, bytes calldata quorums) internal virtual {
        emit log_named_string(string.concat(NAME, ".", s), quorums.toString());
    }

    // Operator0.registerOperatorWithChurn
    // - standardQuorums: 0x00010203...
    // - churnQuorums: 0x0405...
    // - churnTargets: Operator1, Operator2, ...
    function _logChurn(
        string memory s,
        bytes memory churnQuorums,
        User[] memory churnTargets,
        bytes memory standardQuorums
    ) internal virtual {
        emit log(string.concat(NAME, ".", s));

        emit log_named_string("- standardQuorums", standardQuorums.toString());
        emit log_named_string("- churnQuorums", churnQuorums.toString());

        string memory targetString = "[";
        for (uint256 i = 0; i < churnTargets.length; i++) {
            if (i == churnTargets.length - 1) {
                targetString = string.concat(targetString, churnTargets[i].NAME());
            } else {
                targetString = string.concat(targetString, churnTargets[i].NAME(), ", ");
            }
        }
        targetString = string.concat(targetString, "]");

        emit log_named_string("- churnTargets", targetString);
    }

    function _generateOperatorKickParams(
        bytes memory allQuorums,
        bytes calldata churnQuorums,
        User[] calldata churnTargets,
        bytes calldata standardQuorums
    )
        internal
        virtual
        returns (
            ISlashingRegistryCoordinatorTypes.OperatorKickParam[] memory,
            ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory
        )
    {
        ISlashingRegistryCoordinator.OperatorKickParam[] memory kickParams =
            new ISlashingRegistryCoordinator.OperatorKickParam[](allQuorums.length);

        // this constructs OperatorKickParam[] in ascending quorum order
        // (yikes)
        uint256 churnIdx;
        uint256 stdIdx;
        while (churnIdx + stdIdx < allQuorums.length) {
            if (churnIdx == churnQuorums.length) {
                kickParams[churnIdx + stdIdx] = ISlashingRegistryCoordinatorTypes.OperatorKickParam({
                    quorumNumber: 0,
                    operator: address(0)
                });
                stdIdx++;
            } else if (
                stdIdx == standardQuorums.length || churnQuorums[churnIdx] < standardQuorums[stdIdx]
            ) {
                kickParams[churnIdx + stdIdx] = ISlashingRegistryCoordinatorTypes.OperatorKickParam({
                    quorumNumber: uint8(churnQuorums[churnIdx]),
                    operator: address(churnTargets[churnIdx])
                });
                churnIdx++;
            } else if (standardQuorums[stdIdx] < churnQuorums[churnIdx]) {
                kickParams[churnIdx + stdIdx] = ISlashingRegistryCoordinatorTypes.OperatorKickParam({
                    quorumNumber: 0,
                    operator: address(0)
                });
                stdIdx++;
            } else {
                revert("User.registerOperatorWithChurn: malformed input");
            }
        }

        // Generate churn approver signature
        bytes32 _salt = keccak256(abi.encodePacked(++salt, address(this)));
        uint256 expiry = type(uint256).max;
        bytes32 digest = registryCoordinator.calculateOperatorChurnApprovalDigestHash({
            registeringOperator: address(this),
            registeringOperatorId: operatorId,
            operatorKickParams: kickParams,
            salt: _salt,
            expiry: expiry
        });

        // Sign digest
        (uint8 v, bytes32 r, bytes32 s) = cheats.sign(churnApproverPrivateKey, digest);
        bytes memory signature = new bytes(65);
        assembly {
            mstore(add(signature, 0x20), r)
            mstore(add(signature, 0x40), s)
        }
        signature[signature.length - 1] = bytes1(v);
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory churnApproverSignature =
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry({
            signature: signature,
            salt: _salt,
            expiry: expiry
        });

        return (kickParams, churnApproverSignature);
    }
}

contract User_AltMethods is User {
    using BitmapUtils for *;

    modifier createSnapshot() virtual override {
        cheats.roll(block.number + 1);
        timeMachine.createSnapshot();
        _;
    }

    constructor(
        string memory name,
        uint256 _privKey,
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory _pubkeyParams
    ) User(name, _privKey, _pubkeyParams) {}

    /// @dev Rather than calling deregisterOperator, this pranks the ejector and calls
    /// ejectOperator
    function deregisterOperator(
        bytes calldata quorums
    ) public virtual override createSnapshot {
        _log("deregisterOperator (eject)", quorums);

        address ejector = registryCoordinator.ejector();

        cheats.prank(ejector);
        registryCoordinator.ejectOperator(address(this), quorums);
    }

    /// @dev Uses updateOperatorsForQuorum to update stakes of all operators in all quorums
    function updateStakes() public virtual override createSnapshot {
        _log("updateStakes (updateOperatorsForQuorum)");

        bytes memory allQuorums =
            ((1 << registryCoordinator.quorumCount()) - 1).bitmapToBytesArray();
        address[][] memory operatorsPerQuorum = new address[][](allQuorums.length);

        for (uint256 i = 0; i < allQuorums.length; i++) {
            uint8 quorum = uint8(allQuorums[i]);
            bytes32[] memory operatorIds =
                indexRegistry.getOperatorListAtBlockNumber(quorum, uint32(block.number));

            operatorsPerQuorum[i] = new address[](operatorIds.length);

            for (uint256 j = 0; j < operatorIds.length; j++) {
                operatorsPerQuorum[i][j] = blsApkRegistry.getOperatorFromPubkeyHash(operatorIds[j]);
            }

            operatorsPerQuorum[i] = Sort.sortAddresses(operatorsPerQuorum[i]);
        }

        registryCoordinator.updateOperatorsForQuorum(operatorsPerQuorum, allQuorums);
    }
}
