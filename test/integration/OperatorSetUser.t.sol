// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./User.t.sol";
import "forge-std/console.sol";

contract OperatorSetUser is User {
    using BN254 for *;
    using Strings for *;
    using BitmapStrings for *;
    using BitmapUtils for *;

    SlashingRegistryCoordinator slashingRegistryCoordinator;
    AllocationManager allocationManager;
    address avs;

    constructor(
        string memory name,
        uint256 _privKey,
        IBLSApkRegistryTypes.PubkeyRegistrationParams memory _pubkeyParams
    ) User(name, _privKey, _pubkeyParams) {
        IUserDeployer deployer = IUserDeployer(msg.sender);

        slashingRegistryCoordinator = deployer.slashingRegistryCoordinator();
        allocationManager = AllocationManager(deployer.allocationManager());

        avs = slashingRegistryCoordinator.avs();

        // Generate BN254 keypair and registration signature
        privKey = _privKey;
        pubkeyParams = _pubkeyParams;

        BN254.G1Point memory registrationMessageHash =
            slashingRegistryCoordinator.pubkeyRegistrationMessageHash(address(this));
        pubkeyParams.pubkeyRegistrationSignature = registrationMessageHash.scalar_mul(privKey);

        operatorId = pubkeyParams.pubkeyG1.hashG1Point();
    }

    function registerOperator(
        bytes calldata quorums
    ) public virtual override createSnapshot returns (bytes32) {
        _log("registerOperator", quorums);

        vm.warp(block.timestamp + 1);
        // If operator has previously registered and is still slashable, roll blocks until they are
        // no longer slashable
        vm.roll(block.number + uint256(allocationManager.DEALLOCATION_DELAY()) + 1);

        // encode bytes data field passed into SlashingRegistryCoordinator.registerOperator
        // Register params for AllocationManager
        bytes memory data = abi.encode(
            ISlashingRegistryCoordinatorTypes.RegistrationType.NORMAL, NAME, pubkeyParams
        );
        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({avs: avs, operatorSetIds: _getOperatorSetIds(quorums), data: data});

        allocationManager.registerForOperatorSets({operator: address(this), params: registerParams});

        return pubkeyParams.pubkeyG1.hashG1Point();
    }

    function registerOperatorWithChurn(
        bytes calldata churnQuorums,
        User[] calldata churnTargets,
        bytes calldata standardQuorums
    ) public virtual override createSnapshot {
        _logChurn("registerOperatorWithChurn", churnQuorums, churnTargets, standardQuorums);

        vm.warp(block.timestamp + 1);
        // If operator has previously registered and is still slashable, roll blocks until they are
        // no longer slashable
        vm.roll(block.number + uint256(allocationManager.DEALLOCATION_DELAY()) + 1);

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

        // Encode with RegistrationType.CHURN
        bytes memory data = abi.encode(
            ISlashingRegistryCoordinatorTypes.RegistrationType.CHURN,
            NAME,
            pubkeyParams,
            kickParams,
            churnApproverSignature
        );

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({avs: avs, operatorSetIds: _getOperatorSetIds(allQuorums), data: data});
        allocationManager.registerForOperatorSets({operator: address(this), params: registerParams});
    }

    function deregisterOperator(
        bytes calldata quorums
    ) public virtual override createSnapshot {
        _log("deregisterOperator", quorums);
        uint32[] memory operatorSetIds = _getOperatorSetIds(quorums);
        IAllocationManagerTypes.DeregisterParams memory deregisterParams = IAllocationManagerTypes
            .DeregisterParams({avs: avs, operator: address(this), operatorSetIds: operatorSetIds});
        allocationManager.deregisterFromOperatorSets({params: deregisterParams});
    }

    /// @dev Uses updateOperators to update this user's stake
    function updateStakes() public virtual override createSnapshot {
        _log("updateStakes (updateOperators)");

        // get all quorums this operator is registered for
        uint192 currentBitmap = slashingRegistryCoordinator.getCurrentQuorumBitmap(operatorId);
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
        slashingRegistryCoordinator.updateOperatorsForQuorum(operatorsPerQuorum, quorumNumbers);
    }

    function _getOperatorSetIds(
        bytes memory quorums
    ) internal pure returns (uint32[] memory) {
        uint32[] memory operatorSetIds = new uint32[](quorums.length);
        for (uint256 i = 0; i < quorums.length; i++) {
            operatorSetIds[i] = uint32(uint8(quorums[i]));
        }
        return operatorSetIds;
    }

    function _generateOperatorKickParams(
        bytes memory allQuorums,
        bytes calldata churnQuorums,
        User[] calldata churnTargets,
        bytes calldata standardQuorums
    )
        internal
        virtual
        override
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
        bytes32 digest = slashingRegistryCoordinator.calculateOperatorChurnApprovalDigestHash({
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

contract OperatorSetUser_AltMethods is OperatorSetUser {
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
    ) OperatorSetUser(name, _privKey, _pubkeyParams) {}

    /// @dev Rather than calling deregisterOperator, this pranks the ejector and calls
    /// ejectOperator
    function deregisterOperator(
        bytes calldata quorums
    ) public virtual override createSnapshot {
        _log("deregisterOperator (eject)", quorums);

        address ejector = slashingRegistryCoordinator.ejector();

        cheats.prank(ejector);
        slashingRegistryCoordinator.ejectOperator(address(this), quorums);
    }

    /// @dev Uses updateOperatorsForQuorum to update stakes of all operators in all quorums
    function updateStakes() public virtual override createSnapshot {
        _log("updateStakes (updateOperatorsForQuorum)");

        bytes memory allQuorums =
            ((1 << slashingRegistryCoordinator.quorumCount()) - 1).bitmapToBytesArray();
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

        slashingRegistryCoordinator.updateOperatorsForQuorum(operatorsPerQuorum, allQuorums);
    }
}
