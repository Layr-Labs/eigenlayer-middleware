// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IEjector} from "./interfaces/IEjector.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {BitmapUtils} from "./libraries/BitmapUtils.sol";

/**
 * @title Used for automated ejection of operators from the registryCoordinator
 * @author Layr Labs, Inc.
 */
contract Ejector is IEjector, Ownable{

    IRegistryCoordinator public immutable registryCoordinator;
    IStakeRegistry public immutable stakeRegistry;

    /// @notice Address permissioned to eject operators under a ratelimit
    address public ejector;

    /// @notice Keeps track of the total stake ejected for a quorum within a time delta
    mapping(uint8 => mapping(uint256 => uint256)) public stakeEjectedForQuorumInDelta;
    /// @notice Ratelimit parameters for each quorum
    mapping(uint8 => QuorumEjectionParams) public quorumEjectionParams;

    constructor(
        IRegistryCoordinator _registryCoordinator, 
        IStakeRegistry _stakeRegistry,
        address _owner, 
        address _ejector,
        QuorumEjectionParams[] memory _quorumEjectionParams
    ) {
        registryCoordinator = _registryCoordinator;
        stakeRegistry = _stakeRegistry;
        _setEjector(_ejector);
        _transferOwnership(_owner);

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

        for(uint i = 0; i < _operatorIds.length; i++) {
            bytes memory quorumNumbers = BitmapUtils.bitmapToBytesArray(_quorumBitmaps[i]);

            for(uint8 j = 0; j < quorumNumbers.length; j++) {
                uint8 quorumNumber = uint8(quorumNumbers[j]);
                uint256 operatorStake = stakeRegistry.getCurrentStake(_operatorIds[i], quorumNumber);

                uint256 timeBlock = block.timestamp % quorumEjectionParams[quorumNumber].timeDelta;
                if(
                    msg.sender == ejector &&
                    stakeEjectedForQuorumInDelta[quorumNumber][timeBlock] + operatorStake > quorumEjectionParams[quorumNumber].maxStakePerDelta
                ){
                    revert("Ejector: Operator stake exceeds max stake per delta");
                } 
                stakeEjectedForQuorumInDelta[quorumNumber][timeBlock] += operatorStake;                
            }

            registryCoordinator.ejectOperator(
                registryCoordinator.getOperatorFromId(_operatorIds[i]),
                quorumNumbers
            );
        }
    }

    /**
     * @notice Sets the ratelimit parameters for a quorum
     * @param _quorumNumber The quorum number to set the ratelimit parameters for
     * @param _quorumEjectionParams The quorum bitmaps for each respective operator
     */
    function setQuorumEjectionParams(uint8 _quorumNumber, QuorumEjectionParams memory _quorumEjectionParams) external onlyOwner() {
        quorumEjectionParams[_quorumNumber] = _quorumEjectionParams;
    }

    /**
     * @notice Sets the address permissioned to eject operators
     * @param _ejector The address to permission
     */
    function setEjector(address _ejector) external onlyOwner() {
        _setEjector(_ejector);
    }

    function _setEjector(address _ejector) internal {
        emit EjectorChanged(ejector, _ejector);
        ejector = _ejector;
    }
    
}
