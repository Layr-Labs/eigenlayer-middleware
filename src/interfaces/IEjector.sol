// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IRegistryCoordinator} from "./IRegistryCoordinator.sol";
import {IStakeRegistry} from "./IStakeRegistry.sol";

/**
 * @title Interface for a contract that ejects operators from an AVS
 * @author Layr Labs, Inc.
 */
interface IEjector {

    /// @notice A quorum's ratelimit parameters
    struct QuorumEjectionParams {
        uint256 timeDelta; // Time delta to track ejection over
        uint256 maxStakePerDelta; // Max stake to be ejectable per time delta
    }

    ///@notice Emitted when the ejector address is set
    event EjectorChanged(address previousAddress, address newAddress);

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
    
}
