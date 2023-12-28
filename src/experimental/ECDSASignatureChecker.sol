// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {ECDSARegistryCoordinator} from "./ECDSARegistryCoordinator.sol";
import {ECDSAStakeRegistry, IDelegationManager} from "./ECDSAStakeRegistry.sol";
import {EIP1271SignatureUtils} from "eigenlayer-contracts/src/contracts/libraries/EIP1271SignatureUtils.sol";

import {BitmapUtils} from "../libraries/BitmapUtils.sol";

/**
 * @title Used for checking ECDSA signatures from the operators of a `ECDSARegistry`.
 * @author Layr Labs, Inc.
 * @notice Terms of Service: https://docs.eigenlayer.xyz/overview/terms-of-service
 * @notice This is the contract for checking the validity of aggregate operator signatures.
 */
contract ECDSASignatureChecker {    

    /**
     * @notice this data structure is used for recording the details on the total stake of the registered
     * operators and those operators who are part of the quorum for a particular taskNumber
     */
    struct QuorumStakeTotals {
        // total stake of the operators in each quorum
        uint96[] signedStakeForQuorum;
        // total amount staked by all operators in each quorum
        uint96[] totalStakeForQuorum;
    }

    // EVENTS
    /// @notice Emitted when `staleStakesForbiddenUpdat
    event StaleStakesForbiddenUpdate(bool value);   

    // CONSTANTS & IMMUTABLES

    ECDSARegistryCoordinator public immutable registryCoordinator;
    ECDSAStakeRegistry public immutable stakeRegistry;
    IDelegationManager public immutable delegation;
    /// @notice If true, check the staleness of the operator stakes and that its within the delegation withdrawalDelayBlocks window.
    bool public staleStakesForbidden;

    modifier onlyCoordinatorOwner() {
        require(msg.sender == registryCoordinator.owner(), "ECDSASignatureChecker.onlyCoordinatorOwner: caller is not the owner of the registryCoordinator");
        _;
    }

    constructor(ECDSARegistryCoordinator _registryCoordinator) {
        registryCoordinator = _registryCoordinator;
        stakeRegistry = ECDSAStakeRegistry(address(_registryCoordinator.stakeRegistry()));
        delegation = stakeRegistry.delegation();
        
        staleStakesForbidden = true;
    }

    /**
     * RegistryCoordinator owner can either enforce or not that operator stakes are staler
     * than the delegation.withdrawalDelayBlocks() window.
     * @param value to toggle staleStakesForbidden
     */
    function setStaleStakesForbidden(bool value) external onlyCoordinatorOwner {
        staleStakesForbidden = value;
        emit StaleStakesForbiddenUpdate(value);
    }

    /**
     * @notice This function is called by disperser when it has aggregated all the signatures of the operators
     * that are part of the quorum for a particular taskNumber and is asserting them into onchain. The function
     * checks that the claim for aggregated signatures are valid.
     *
     * The thesis of this procedure entails:
     * - getting the aggregated pubkey of all registered nodes at the time of pre-commit by the
     * disperser (represented by apk in the parameters),
     * - subtracting the pubkeys of all the signers not in the quorum (nonSignerPubkeys) and storing 
     * the output in apk to get aggregated pubkey of all operators that are part of quorum.
     * - use this aggregated pubkey to verify the aggregated signature under BLS scheme.
     * 
     * @dev Before signature verification, the function verifies operator stake information.  This includes ensuring that the provided `referenceBlockNumber`
     * is correct, i.e., ensure that the stake returned from the specified block number is recent enough and that the stake is either the most recent update
     * for the total stake (of the operator) or latest before the referenceBlockNumber.
     * @param msgHash is the hash being signed
     * @param quorumNumbers is the bytes array of quorum numbers that are being signed for
     * @param signerIds TODO: document
     * @param signatures TODO: document
     * @return quorumStakeTotals is the struct containing the total and signed stake for each quorum
     * @return signatoryRecordHash is the hash of the signatory record, which is used for fraud proofs
     */
    function checkSignatures(
        bytes32 msgHash, 
        bytes calldata quorumNumbers,
        address[] memory signerIds,
        bytes[] memory signatures
    ) 
        public 
        view
        returns (
            QuorumStakeTotals memory,
            bytes32
        )
    {
        require(
            signerIds.length == signatures.length,
            "ECDSASignatureChecker.checkSignatures: signature input length mismatch"
        );
        // For each quorum, we're also going to query the total stake for all registered operators
        // at the referenceBlockNumber, and derive the stake held by signers by subtracting out
        // stakes held by nonsigners.
        QuorumStakeTotals memory stakeTotals;
        stakeTotals.totalStakeForQuorum = new uint96[](quorumNumbers.length);
        stakeTotals.signedStakeForQuorum = new uint96[](quorumNumbers.length);

        // Get a bitmap of the quorums signing the message, and validate that
        // quorumNumbers contains only unique, valid quorum numbers
        uint256 signingQuorumBitmap = BitmapUtils.orderedBytesArrayToBitmap(quorumNumbers, registryCoordinator.quorumCount());

        for (uint256 i = 0; i < signerIds.length; ++i) {

            // The check below validates that operatorIds are sorted (and therefore free of duplicates)
            if (i != 0) {
                require(
                    uint160(signerIds[i]) >  uint160(signerIds[i - 1]),
                    "ECDSASignatureChecker.checkSignatures: signer keys not sorted"
                );
            }

            // check the operator's signature
            EIP1271SignatureUtils.checkSignature_EIP1271(signerIds[i], msgHash, signatures[i]);

            uint256 operatorBitmap = registryCoordinator.operatorBitmap(signerIds[i]);
            for (uint256 j = 0; j < quorumNumbers.length; j++) {
                uint8 quorumNumber = uint8(quorumNumbers[j]);
                if (BitmapUtils.isSet(operatorBitmap, quorumNumber)) {
                    stakeTotals.signedStakeForQuorum[j] += stakeRegistry.operatorStake(signerIds[i], quorumNumber);
                }
            }
        }


        /**
         * For each quorum (at referenceBlockNumber):
         * - add the apk for all registered operators
         * - query the total stake for each quorum
         * - subtract the stake for each nonsigner to calculate the stake belonging to signers
         */
        {
            uint256 withdrawalDelayBlocks = delegation.withdrawalDelayBlocks();
            bool _staleStakesForbidden = staleStakesForbidden;

            for (uint256 i = 0; i < quorumNumbers.length; i++) {
                // If we're disallowing stale stake updates, check that each quorum's last update block
                // is within withdrawalDelayBlocks
                if (_staleStakesForbidden) {
                    require(
                        registryCoordinator.quorumUpdateBlockNumber(uint8(quorumNumbers[i])) + withdrawalDelayBlocks >= block.number,
                        "ECDSASignatureChecker.checkSignatures: StakeRegistry updates must be within withdrawalDelayBlocks window"
                    );
                }

                // Get the total and starting signed stake for the quorum at referenceBlockNumber
                stakeTotals.totalStakeForQuorum[i] = stakeRegistry.totalStake(uint8(quorumNumbers[i]));
            }

        }

        // set signatoryRecordHash variable used for fraudproofs
        bytes32 signatoryRecordHash = keccak256(abi.encodePacked(block.number, signerIds));

        // return the total stakes that signed for each quorum, and a hash of the information required to prove the exact signers and stake
        return (stakeTotals, signatoryRecordHash);
    }

}
