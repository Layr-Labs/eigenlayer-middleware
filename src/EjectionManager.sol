// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {IEjectionManager} from "./interfaces/IEjectionManager.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {BitmapUtils} from "./libraries/BitmapUtils.sol";

/**
 * @title Used for automated ejection of operators from the RegistryCoordinator
 * @author Layr Labs, Inc.
 */
contract EjectionManager is IEjectionManager, OwnableUpgradeable{

    /// @notice The basis point denominator for the ejectable stake percent
    uint16 internal constant BIPS_DENOMINATOR = 10000;

    IRegistryCoordinator public immutable registryCoordinator;
    IStakeRegistry public immutable stakeRegistry;

    /// @notice Address permissioned to eject operators under a ratelimit
    address public ejector;

    /// @notice Keeps track of the total stake ejected for a quorum within a time delta
    mapping(uint8 => StakeEjection[]) public stakeEjectedForQuorum;
    /// @notice Ratelimit parameters for each quorum
    mapping(uint8 => QuorumEjectionParams) public quorumEjectionParams;

    constructor(
        IRegistryCoordinator _registryCoordinator, 
        IStakeRegistry _stakeRegistry
    ) {
        registryCoordinator = _registryCoordinator;
        stakeRegistry = _stakeRegistry;

        _disableInitializers();
    }

    function initialize(
        address _owner, 
        address _ejector,
        QuorumEjectionParams[] memory _quorumEjectionParams
    ) external initializer {
        _transferOwnership(_owner);
        _setEjector(_ejector);

        for(uint8 i = 0; i < _quorumEjectionParams.length; i++) {
            _setQuorumEjectionParams(i, _quorumEjectionParams[i]);
        }
    }

    /**
     * @notice Ejects operators from the AVSs registryCoordinator under a ratelimit
     * @dev This function will eject as many operators as possible without reverting
     * @param _operatorIds The ids of the operators to eject for each quorum
     */
    function ejectOperators(bytes32[][] memory _operatorIds) external {
        require(msg.sender == ejector || msg.sender == owner(), "Ejector: Only owner or ejector can eject");

        for(uint i = 0; i < _operatorIds.length; ++i) {
            uint8 quorumNumber = uint8(i);

            _cleanOldEjections(quorumNumber);
            uint256 amountEjectable = _amountEjectableForQuorum(quorumNumber);
            uint256 stakeForEjection; 

            bool broke;
            for(uint8 j = 0; j < _operatorIds[i].length; ++j) {
                uint256 operatorStake = stakeRegistry.getCurrentStake(_operatorIds[i][j], quorumNumber);

                if(
                    msg.sender == ejector && 
                    quorumEjectionParams[quorumNumber].rateLimitWindow > 0 &&
                    stakeForEjection + operatorStake > amountEjectable
                ){
                    stakeEjectedForQuorum[quorumNumber].push(StakeEjection({
                        timestamp: block.timestamp,
                        stakeEjected: stakeForEjection
                    }));
                    broke = true;
                    break;
                }
                
                try registryCoordinator.ejectOperator(
                    registryCoordinator.getOperatorFromId(_operatorIds[i][j]),
                    abi.encodePacked(quorumNumber)
                ) {
                    stakeForEjection += operatorStake;
                    emit OperatorEjected(_operatorIds[i][j], quorumNumber);
                } catch (bytes memory err) {
                    emit FailedOperatorEjection(_operatorIds[i][j], quorumNumber, err);
                }
            }

            if(!broke){
                stakeEjectedForQuorum[quorumNumber].push(StakeEjection({
                    timestamp: block.timestamp,
                    stakeEjected: stakeForEjection
                }));
            }

        }
    }

    /**
     * @notice Sets the ratelimit parameters for a quorum
     * @param _quorumNumber The quorum number to set the ratelimit parameters for
     * @param _quorumEjectionParams The quorum bitmaps for each respective operator
     */
    function setQuorumEjectionParams(uint8 _quorumNumber, QuorumEjectionParams memory _quorumEjectionParams) external onlyOwner() {
        _setQuorumEjectionParams(_quorumNumber, _quorumEjectionParams);
    }

    /**
     * @notice Sets the address permissioned to eject operators
     * @param _ejector The address to permission
     */
    function setEjector(address _ejector) external onlyOwner() {
        _setEjector(_ejector);
    }

    ///@dev internal function to set the quorum ejection params
    function _setQuorumEjectionParams(uint8 _quorumNumber, QuorumEjectionParams memory _quorumEjectionParams) internal {
        quorumEjectionParams[_quorumNumber] = _quorumEjectionParams;
        emit QuorumEjectionParamsSet(_quorumNumber, _quorumEjectionParams.rateLimitWindow, _quorumEjectionParams.ejectableStakePercent);
    }

    ///@dev internal function to set the ejector
    function _setEjector(address _ejector) internal {
        emit EjectorUpdated(ejector, _ejector);
        ejector = _ejector;
    }

    /**
     * @dev Removes stale ejections for a quorums history
     * @param _quorumNumber The quorum number to clean ejections for
     */
    function _cleanOldEjections(uint8 _quorumNumber) internal {
        uint256 cutoffTime = block.timestamp - quorumEjectionParams[_quorumNumber].rateLimitWindow;
        uint256 index = 0;
        StakeEjection[] storage stakeEjections = stakeEjectedForQuorum[_quorumNumber];
        while (index < stakeEjections.length && stakeEjections[index].timestamp < cutoffTime) {
            index++;
        }
        if (index > 0) {
            for (uint256 i = index; i < stakeEjections.length; ++i) {
                stakeEjections[i - index] = stakeEjections[i];
            }
            for (uint256 i = 0; i < index; ++i) {
                stakeEjections.pop();
            }
        }
    }

    /**
     * @notice Returns the amount of stake that can be ejected for a quorum 
     * @dev This function only returns a valid amount after _cleanOldEjections has been called
     * @param _quorumNumber The quorum number to view ejectable stake for
     */
    function _amountEjectableForQuorum(uint8 _quorumNumber) internal view returns (uint256) {
        uint256 totalEjected = 0;
        for (uint256 i = 0; i < stakeEjectedForQuorum[_quorumNumber].length; i++) {
            totalEjected += stakeEjectedForQuorum[_quorumNumber][i].stakeEjected;
        }
        uint256 totalEjectable = quorumEjectionParams[_quorumNumber].ejectableStakePercent * stakeRegistry.getCurrentTotalStake(_quorumNumber) / BIPS_DENOMINATOR;
        return totalEjectable - totalEjected;   
    }

}
