// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {IEjectionManager} from "./interfaces/IEjectionManager.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";

/**
 * @title Used for automated ejection of operators from the RegistryCoordinator under a ratelimit
 * @author Layr Labs, Inc.
 */
contract EjectionManager is IEjectionManager, OwnableUpgradeable{

    /// @notice The basis point denominator for the ejectable stake percent
    uint16 internal constant BIPS_DENOMINATOR = 10000;

    /// @notice the RegistryCoordinator contract that is the entry point for ejection
    IRegistryCoordinator public immutable registryCoordinator;
    /// @notice the StakeRegistry contract that keeps track of quorum stake
    IStakeRegistry public immutable stakeRegistry;

    /// @notice Address permissioned to eject operators under a ratelimit
    address public ejector;

    /// @notice Keeps track of the total stake ejected for a quorum 
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

    /**
     * @param _owner will hold the owner role
     * @param _ejector will hold the ejector role
     * @param _quorumEjectionParams are the ratelimit parameters for the quorum at each index
     */
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
     * @notice Ejects operators from the AVSs RegistryCoordinator under a ratelimit
     * @param _operatorIds The ids of the operators to eject for each quorum
     * @dev This function will eject as many operators as possible without reverting 
     * @dev The owner can eject operators without recording of stake ejection
     */
    function ejectOperators(bytes32[][] memory _operatorIds) external {
        require(msg.sender == ejector || msg.sender == owner(), "Ejector: Only owner or ejector can eject");

        for(uint i = 0; i < _operatorIds.length; ++i) {
            uint8 quorumNumber = uint8(i);

            uint256 amountEjectable = amountEjectableForQuorum(quorumNumber);
            uint256 stakeForEjection; 

            bool broke;
            for(uint8 j = 0; j < _operatorIds[i].length; ++j) {
                uint256 operatorStake = stakeRegistry.getCurrentStake(_operatorIds[i][j], quorumNumber);

                //if caller is ejector enforce ratelimit
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
                
                //try-catch used to prevent race condition of operator deregistering before ejection
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

            //record the stake ejected if ejector and ratelimit enforced
            if(!broke && msg.sender == ejector){ 
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
     * @param _quorumEjectionParams The quorum ratelimit parameters to set for the given quorum
     */
    function setQuorumEjectionParams(uint8 _quorumNumber, QuorumEjectionParams memory _quorumEjectionParams) external onlyOwner() {
        _setQuorumEjectionParams(_quorumNumber, _quorumEjectionParams);
    }

    /**
     * @notice Sets the address permissioned to eject operators under a ratelimit
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
     * @notice Returns the amount of stake that can be ejected for a quorum at the current block.timestamp
     * @param _quorumNumber The quorum number to view ejectable stake for
     */
    function amountEjectableForQuorum(uint8 _quorumNumber) public view returns (uint256) {
        uint256 totalEjected;
        uint256 cutoffTime = block.timestamp - quorumEjectionParams[_quorumNumber].rateLimitWindow;
        uint256 i = stakeEjectedForQuorum[_quorumNumber].length - 1;
        while(stakeEjectedForQuorum[_quorumNumber][i].timestamp > cutoffTime) {
            totalEjected += stakeEjectedForQuorum[_quorumNumber][i].stakeEjected;
            if(i == 0){
                break;
            } else {
                --i;
            }
        }
        uint256 totalEjectable = quorumEjectionParams[_quorumNumber].ejectableStakePercent * stakeRegistry.getCurrentTotalStake(_quorumNumber) / BIPS_DENOMINATOR;
        return totalEjectable - totalEjected;   
    }
}
