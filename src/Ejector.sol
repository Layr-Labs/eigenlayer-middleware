// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IEjector} from "./interfaces/IEjector.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {BitmapUtils} from "./libraries/BitmapUtils.sol";

/**
 * @title Used for automated ejection of operators from the RegistryCoordinator
 * @author Layr Labs, Inc.
 */
contract Ejector is IEjector, Ownable{

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
        address _owner, 
        address _ejector,
        IRegistryCoordinator _registryCoordinator, 
        IStakeRegistry _stakeRegistry,
        QuorumEjectionParams[] memory _quorumEjectionParams
    ) {
        registryCoordinator = _registryCoordinator;
        stakeRegistry = _stakeRegistry;
        _transferOwnership(_owner);
        _setEjector(_ejector);

        for(uint8 i = 0; i < _quorumEjectionParams.length; i++) {
            quorumEjectionParams[i] = _quorumEjectionParams[i];
        }
    }

    /**
     * @notice Ejects operators from the AVSs registryCoordinator
     * @param _operatorIds The addresses of the operators to eject
     * @param _quorumBitmaps The quorum bitmaps for each respective operator
     */
    function ejectOperators(bytes32[] memory _operatorIds, uint256[] memory _quorumBitmaps) external {
        require(msg.sender == ejector || msg.sender == owner(), "Ejector: Only owner or ejector can eject");
        require(_operatorIds.length == _quorumBitmaps.length, "Ejector: _operatorIds and _quorumBitmaps must be same length");

        for(uint i = 0; i < _operatorIds.length; ++i) {
            bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(_quorumBitmaps[i]);

            for(uint8 j = 0; j < quorumNumbers.length; ++j) {
                uint8 quorumNumber = uint8(quorumNumbers[j]);
                uint256 operatorStake = stakeRegistry.getCurrentStake(_operatorIds[i], quorumNumber);

                if(msg.sender == ejector){
                    _cleanOldEjections(quorumNumber);
                    require(canEject(operatorStake, quorumNumber), "Ejector: Stake exceeds quorum ejection ratelimit");
                }

                stakeEjectedForQuorum[quorumNumber].push(StakeEjection({
                    timestamp: block.timestamp,
                    stakeEjected: operatorStake
                }));
            }

            try registryCoordinator.ejectOperator(
                registryCoordinator.getOperatorFromId(_operatorIds[i]),
                quorumNumbers
            ) {
                emit OperatorEjected(_operatorIds[i], _quorumBitmaps[i]);
            } catch (bytes memory err) {
                for(uint8 j = 0; j < quorumNumbers.length; ++j) {
                    stakeEjectedForQuorum[uint8(quorumNumbers[j])].pop();
                }
                emit FailedOperatorEjection(_operatorIds[i], _quorumBitmaps[i], err);
            }
        }
    }

    /**
     * @notice Sets the ratelimit parameters for a quorum
     * @param _quorumNumber The quorum number to set the ratelimit parameters for
     * @param _quorumEjectionParams The quorum bitmaps for each respective operator
     */
    function setQuorumEjectionParams(uint8 _quorumNumber, QuorumEjectionParams memory _quorumEjectionParams) external onlyOwner() {
        quorumEjectionParams[_quorumNumber] = _quorumEjectionParams;
        emit QuorumEjectionParamsSet(_quorumNumber, _quorumEjectionParams.timeDelta, _quorumEjectionParams.ejectableStakePercent);
    }

    /**
     * @notice Sets the address permissioned to eject operators
     * @param _ejector The address to permission
     */
    function setEjector(address _ejector) external onlyOwner() {
        _setEjector(_ejector);
    }

    ///@dev internal function to set the ejector
    function _setEjector(address _ejector) internal {
        emit EjectorUpdated(ejector, _ejector);
        ejector = _ejector;
    }

    /**
     * @dev Cleans up old ejections for a quorums StakeEjection array
     * @param _quorumNumber The addresses of the operators to eject
     */
    function _cleanOldEjections(uint8 _quorumNumber) internal {
        uint256 cutoffTime = block.timestamp - quorumEjectionParams[_quorumNumber].timeDelta;
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
     * @notice Checks if an amount of stake can be ejected for a quorum with ratelimit
     * @param _amount The amount of stake to eject
     * @param _quorumNumber The quorum number to eject for
     */
    function canEject(uint256 _amount, uint8 _quorumNumber) public view returns (bool) {
        uint256 totalEjected = 0;
        for (uint256 i = 0; i < stakeEjectedForQuorum[_quorumNumber].length; i++) {
            totalEjected += stakeEjectedForQuorum[_quorumNumber][i].stakeEjected;
        }
        uint256 totalEjectable = quorumEjectionParams[_quorumNumber].ejectableStakePercent * stakeRegistry.getCurrentTotalStake(_quorumNumber) / BIPS_DENOMINATOR;
        return totalEjected + _amount <= totalEjectable;
    }

}
