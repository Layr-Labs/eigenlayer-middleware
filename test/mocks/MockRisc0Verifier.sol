
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

struct ExitCode {
    SystemExitCode system;
    uint8 user;
}

enum SystemExitCode {
    Halted,
    Paused,
    SystemSplit
}

struct ReceiptClaim {
    bytes32 preStateDigest;
    bytes32 postStateDigest;
    ExitCode exitCode;
    bytes32 input;
    bytes32 output;
}

struct Receipt {
    bytes seal;
    ReceiptClaim claim;
}

contract MockRiscZeroVerifier {
    function verify(
        bytes calldata seal,
        bytes32,
        /*imageId*/
        bytes32 postStateDigest,
        bytes32 /*journalDigest*/
    ) public pure returns (bool) {
        // Require that the seal be specifically empty.
        // Reject if the caller may have sent a real seal.
        return seal.length == 0 && postStateDigest == bytes32(0);
    }

    function verify_integrity(Receipt memory receipt) public pure returns (bool) {
        // Require that the seal be specifically empty.
        // Reject if the caller may have sent a real seal.
        return receipt.seal.length == 0 && receipt.claim.postStateDigest == bytes32(0);
    }
}
