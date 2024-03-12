// SPDX-License-Identifier: BUSL-1.1
<<<<<<< HEAD
pragma solidity ^0.8.12;
=======
pragma solidity =0.8.12;
>>>>>>> test: apk registry unit tests and foundry config update (#145)

import {BN254} from "../../src/libraries/BN254.sol";

interface IBLSApkRegistryEvents {
    // EVENTS
    /// @notice Emitted when `operator` registers with the public keys `pubkeyG1` and `pubkeyG2`.
    event NewPubkeyRegistration(address indexed operator, BN254.G1Point pubkeyG1, BN254.G2Point pubkeyG2);

    // @notice Emitted when a new operator pubkey is registered for a set of quorums
    event OperatorAddedToQuorums(
        address operator,
<<<<<<< HEAD
<<<<<<< HEAD
        bytes32 operatorId,
=======
>>>>>>> test: apk registry unit tests and foundry config update (#145)
=======
        bytes32 operatorId,
>>>>>>> feat: nonsigning rate helpers (#202)
        bytes quorumNumbers
    );

    // @notice Emitted when an operator pubkey is removed from a set of quorums
    event OperatorRemovedFromQuorums(
        address operator, 
<<<<<<< HEAD
<<<<<<< HEAD
        bytes32 operatorId,
=======
>>>>>>> test: apk registry unit tests and foundry config update (#145)
=======
        bytes32 operatorId,
>>>>>>> feat: nonsigning rate helpers (#202)
        bytes quorumNumbers
    );
}
