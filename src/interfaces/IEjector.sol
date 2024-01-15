// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IRegistryCoordinator} from "./IRegistryCoordinator.sol";
import {IStakeRegistry} from "./IStakeRegistry.sol";

/**
 * @title Interface for a contract that ejects operators from an AVSs RegistryCoordinator
 * @author Layr Labs, Inc.
 */
interface IEjector {

    /// @notice A quorum's ratelimit parameters
    struct QuorumEjectionParams {
        uint32 timeDelta; // Time delta to track ejection over
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
    event OperatorEjected(bytes32 operatorId, uint256 quorumBitmap);
    ///@notice Emitted when an operator ejection fails
    event FailedOperatorEjection(bytes32 operatorId, uint256 quorumBitmap, bytes err);
    ///@notice Emitted when the ratelimit parameters for a quorum are set
    event QuorumEjectionParamsSet(uint8 quorumNumber, uint32 timeDelta, uint16 ejectableStakePercent);

    /**
     * @notice Ejects operators from the AVSs registryCoordinator
     * @param _operatorIds The addresses of the operators to eject
     * @param _quorumBitmaps The quorum bitmaps for each respective operator
     */
    function ejectOperators(bytes32[] memory _operatorIds, uint256[] memory _quorumBitmaps) external;

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

    /**
     * @notice Checks if an amount of stake can be ejected for a quorum with ratelimit
     * @param _amount The amount of stake to eject
     * @param _quorumNumber The quorum number to eject for
     */
    function canEject(uint256 _amount, uint8 _quorumNumber) external view returns (bool);
    
}
