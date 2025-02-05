// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ISlashingRegistryCoordinator} from "./ISlashingRegistryCoordinator.sol";
import {IStakeRegistry} from "./IStakeRegistry.sol";

interface IEjectionManagerErrors {
    /// @notice Thrown when the caller is not the owner or ejector.
    error OnlyOwnerOrEjector();
    /// @notice Thrown when quorum number exceeds MAX_QUORUM_COUNT.
    error MaxQuorumCount();
}

interface IEjectionManagerTypes {
    /// @notice Parameters for controlling ejection rate limits per quorum.
    /// @param rateLimitWindow Time window to track ejection rate (in seconds).
    /// @param ejectableStakePercent Maximum percentage of stake that can be ejected per window (in BIPS).
    struct QuorumEjectionParams {
        uint32 rateLimitWindow;
        uint16 ejectableStakePercent;
    }

    /// @notice Records a stake ejection event with timing and amount.
    /// @param timestamp Time when the ejection occurred.
    /// @param stakeEjected Amount of stake that was ejected.
    struct StakeEjection {
        uint256 timestamp;
        uint256 stakeEjected;
    }
}

interface IEjectionManagerEvents is IEjectionManagerTypes {
    /*
     * @notice Emitted when the ejector address is set.
     * @param ejector The address being configured as ejector.
     * @param status The new status for the ejector address.
     */
    event EjectorUpdated(address ejector, bool status);

    /*
     * @notice Emitted when the rate limit parameters for a quorum are set.
     * @param quorumNumber The quorum number being configured.
     * @param rateLimitWindow The new time window for rate limiting.
     * @param ejectableStakePercent The new percentage of stake that can be ejected.
     */
    event QuorumEjectionParamsSet(
        uint8 quorumNumber, uint32 rateLimitWindow, uint16 ejectableStakePercent
    );

    /*
     * @notice Emitted when an operator is ejected.
     * @param operatorId The unique identifier of the ejected operator.
     * @param quorumNumber The quorum number the operator was ejected from.
     */
    event OperatorEjected(bytes32 operatorId, uint8 quorumNumber);

    /*
     * @notice Emitted when operators are ejected for a quorum.
     * @param ejectedOperators Number of operators that were ejected.
     * @param ratelimitHit Whether the ejection rate limit was reached.
     */
    event QuorumEjection(uint32 ejectedOperators, bool ratelimitHit);
}

interface IEjectionManager is IEjectionManagerErrors, IEjectionManagerEvents {
    /* STATE */

    /*
     * @notice Returns the address of the slashing registry coordinator contract.
     * @return The address of the slashing registry coordinator.
     * @dev This value is immutable and set during contract construction.
     */
    function slashingRegistryCoordinator() external view returns (ISlashingRegistryCoordinator);

    /*
     * @notice Returns the address of the stake registry contract.
     * @return The address of the stake registry.
     * @dev This value is immutable and set during contract construction.
     */
    function stakeRegistry() external view returns (IStakeRegistry);

    /*
     * @notice Returns whether `ejector` is authorized to eject operators under a rate limit.
     * @param ejector The address to check.
     * @return Whether the address is authorized to eject operators.
     */
    function isEjector(
        address ejector
    ) external view returns (bool);

    /*
     * @notice Returns the stake ejected for a quorum `quorumNumber` at array offset `index`.
     * @param quorumNumber The quorum number to query.
     * @param index The index in the ejection history.
     * @return timestamp The timestamp of the ejection.
     * @return stakeEjected The amount of stake ejected.
     */
    function stakeEjectedForQuorum(
        uint8 quorumNumber,
        uint256 index
    ) external view returns (uint256 timestamp, uint256 stakeEjected);

    /*
     * @notice Returns the rate limit parameters for quorum `quorumNumber`.
     * @param quorumNumber The quorum number to query.
     * @return rateLimitWindow The time window to track ejection rate (in seconds).
     * @return ejectableStakePercent The maximum percentage of stake that can be ejected per window (in BIPS).
     */
    function quorumEjectionParams(
        uint8 quorumNumber
    ) external view returns (uint32 rateLimitWindow, uint16 ejectableStakePercent);

    /* ACTIONS */

    /*
     * @notice Ejects operators specified in `operatorIds` from the AVS's RegistryCoordinator under a rate limit.
     * @param operatorIds The ids of the operators to eject for each quorum.
     * @dev This function will eject as many operators as possible prioritizing operators at the lower index.
     * @dev The owner can eject operators without recording of stake ejection.
     */
    function ejectOperators(
        bytes32[][] memory operatorIds
    ) external;

    /*
     * @notice Sets the rate limit parameters for quorum `quorumNumber` to `quorumEjectionParams`.
     * @param quorumNumber The quorum number to set the rate limit parameters for.
     * @param quorumEjectionParams The quorum rate limit parameters to set.
     */
    function setQuorumEjectionParams(
        uint8 quorumNumber,
        QuorumEjectionParams memory quorumEjectionParams
    ) external;

    /*
     * @notice Sets whether address `ejector` is permissioned to eject operators under a rate limit to `status`.
     * @param ejector The address to permission.
     * @param status The status to set for the given address.
     */
    function setEjector(address ejector, bool status) external;

    /* VIEW */

    /*
     * @notice Returns the amount of stake that can be ejected for quorum `quorumNumber` at the current block.timestamp.
     * @param quorumNumber The quorum number to view ejectable stake for.
     * @return The amount of stake that can be ejected.
     */
    function amountEjectableForQuorum(
        uint8 quorumNumber
    ) external view returns (uint256);
}
