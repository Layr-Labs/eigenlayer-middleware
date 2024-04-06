// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IRegistryCoordinator} from "./IRegistryCoordinator.sol";
import {IStakeRegistry} from "./IStakeRegistry.sol";

/**
 * @title Interface for a contract that ejects operators from an AVSs RegistryCoordinator
 * @author Layr Labs, Inc.
 */
interface IEjectionManager {

    /// @notice A quorum's ratelimit parameters
    struct QuorumEjectionParams {
        uint32 rateLimitWindow; // Time delta to track ejection over
        uint16 ejectableStakePercent; // Max stake to be ejectable per time delta
    }

    /// @notice A stake ejection event
    struct StakeEjection {
        uint256 timestamp; // Timestamp of the ejection
        uint256 stakeEjected; // Amount of stake ejected at the timestamp
    }

    ///@notice Emitted when the ejector address is set
    event EjectorUpdated(address previousAddress, address newAddress);
    ///@notice Emitted when an operator is ejected
    event OperatorEjected(bytes32 operatorId, uint8 quorumNumber);
    ///@notice Emitted when an operator ejection fails
    event FailedOperatorEjection(bytes32 operatorId, uint8 quorumNumber, bytes err);
    ///@notice Emitted when the ratelimit parameters for a quorum are set
    event QuorumEjectionParamsSet(uint8 quorumNumber, uint32 rateLimitWindow, uint16 ejectableStakePercent);

   /**
     * @notice Ejects operators from the AVSs registryCoordinator under a ratelimit
     * @param _operatorIds The ids of the operators to eject for each quorum
     */
    function ejectOperators(bytes32[][] memory _operatorIds) external;

    /**
     * @notice Sets the ratelimit parameters for a quorum
     * @param _quorumNumber The quorum number to set the ratelimit parameters for
     * @param _quorumEjectionParams The quorum bitmaps for each respective operator
     */
    function setQuorumEjectionParams(uint8 _quorumNumber, QuorumEjectionParams memory _quorumEjectionParams) external;

    /**
     * @notice Sets the address permissioned to eject operators
     * @param _ejector The address to permission
     */
    function setEjector(address _ejector) external;


    
}
