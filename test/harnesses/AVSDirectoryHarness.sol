// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IDelegationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {AVSDirectory} from "eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";

// wrapper around the AVSDirectory contract that exposes internal functionality, for unit testing
contract AVSDirectoryHarness is AVSDirectory {
    constructor(
        IDelegationManager _delegation
    ) AVSDirectory(_delegation) {}

    function setOperatorSaltIsSpent(address operator, bytes32 salt, bool isSpent) external {
        operatorSaltIsSpent[operator][salt] = isSpent;
    }

    function setAvsOperatorStatus(
        address avs,
        address operator,
        OperatorAVSRegistrationStatus status
    ) external {
        avsOperatorStatus[avs][operator] = status;
    }

    function setIsOperatorSetAVS(address avs, bool isOperatorSet) external {
        isOperatorSetAVS[avs] = isOperatorSet;
    }

    function setIsOperatorSet(address avs, uint32 operatorSetId, bool isSet) external {
        isOperatorSet[avs][operatorSetId] = isSet;
    }

    function setIsMember(
        address avs,
        address operator,
        uint32[] calldata operatorSetIds,
        bool membershipStatus
    ) external {
        if (membershipStatus) {
            _registerToOperatorSets(avs, operator, operatorSetIds);
        } else {
            _deregisterFromOperatorSets(avs, operator, operatorSetIds);
        }
    }

    function _registerToOperatorSetsExternal(
        address avs,
        address operator,
        uint32[] calldata operatorSetIds
    ) external {
        _registerToOperatorSets(avs, operator, operatorSetIds);
    }

    function _deregisterFromOperatorSetsExternal(
        address avs,
        address operator,
        uint32[] calldata operatorSetIds
    ) external {
        _deregisterFromOperatorSets(avs, operator, operatorSetIds);
    }

    function _calculateDigestHashExternal(
        bytes32 structHash
    ) external view returns (bytes32) {
        return _calculateDigestHash(structHash);
    }

    function _calculateDomainSeparatorExternal() external view returns (bytes32) {
        return _calculateDomainSeparator();
    }
}
