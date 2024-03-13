// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IServiceManager} from "../interfaces/IServiceManager.sol";
import {LinearWeightQuorum} from "./LinearWeightQuorum.sol";

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

/** 
 * @notice ~Equivalent to the `EcdsaEpochRegistry` contract, but built from modular pieces instead of
 * a more monolithic construction.
 */
contract EcdsaEpochRegistry_Modular is LinearWeightQuorum {
    /// @notice the ServiceManager for this AVS, which forwards calls onto EigenLayer's core contracts
    IServiceManager public immutable serviceManager;

    // @notice the length of each epoch, in seconds
    uint256 public immutable epochLengthSeconds;
    // @notice the start of the initial epoch
    uint256 public immutable epochZeroStart;

    /// @notice History of the total stakes
    /// Mapping: epoch => total stake in epoch
    mapping(uint256 => uint256) public totalStakeHistory;

    // TODO: possibly pack the first 2 variables here
    /// @notice Mapping: operator address => epoch => stake of operator in epoch
    mapping(address => mapping(uint256 => uint256)) internal _operatorStakeHistory;

    // TODO: this corresponds with suggested packing, above.
    function operatorStakeHistory(address operator, uint256 epoch) public view returns (uint256) {
        return _operatorStakeHistory[operator][epoch];
    }

    enum OperatorStatus {
        // default is NEVER_REGISTERED
        NEVER_REGISTERED,
        REGISTERED,
        DEREGISTERED
    }

    // TODO: documentation
    mapping(address => OperatorStatus) operatorStatus;

    // @notice: mapping: epoch => set of operators for the epoch
    mapping(uint256 => address[]) public operatorsForEpoch;
    // TODO: could probably restructure `operatorStakeHistory` to also jam that into the same slot as above

    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[46] private __GAP;

    /** 
     * @dev setting the `_epochZeroStart` to be in the past is disallowed.
     * If you try to do so, the current block.timestamp will be used instead.
     * Future times are allowed, with no safety check in place.
     */
    constructor(
        IServiceManager _serviceManager,
        IDelegationManager _delegationManager,
        uint256 _epochLengthSeconds,
        uint256 _epochZeroStart
    )
        LinearWeightQuorum(_delegationManager)
    {
        serviceManager = _serviceManager;
        epochLengthSeconds = _epochLengthSeconds;
        uint256 epochZeroValueToSet;
        if (_epochZeroStart < block.timestamp) {
            epochZeroValueToSet = block.timestamp;
        } else {
            epochZeroValueToSet = _epochZeroStart;
        }
        epochZeroStart = epochZeroValueToSet;
    }

    /*******************************************************************************
                    EXTERNAL FUNCTIONS - unpermissioned
    *******************************************************************************/
    /**
     * @notice Registers msg.sender as an operator.
     * @param operatorSignature is the signature of the operator used by the AVS to register the operator in the delegation manager
     */
    function registerOperator(
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) public virtual {
        address operator = msg.sender;
        _registerOperator(operator, operatorSignature);
    }

    // @notice Deregisters the msg.sender.
    function deregisterOperator() public virtual {
        address operator = msg.sender;
        _deregisterOperator(operator);
    }

    /*******************************************************************************
                    EXTERNAL FUNCTIONS -- permissioned
    *******************************************************************************/
    // @notice TODO: proper documentation
    function evaluateOperatorSet(
        address[] memory operatorsToEvaluate,
        uint256 minimumWeight
    ) public virtual onlyOwner {
        _evaluateOperatorSet(operatorsToEvaluate, minimumWeight);
    }

    /*******************************************************************************
                            INTERNAL FUNCTIONS
    *******************************************************************************/
    // TODO: documentation
    function _registerOperator(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) internal virtual {
        if (operatorStatus[operator] != OperatorStatus.REGISTERED) {
            operatorStatus[operator] = OperatorStatus.REGISTERED;

            // Register the operator with the EigenLayer via this AVS's ServiceManager
            serviceManager.registerOperatorToAVS(operator, operatorSignature);

            // TODO: event
            // emit OperatorRegistered(operator, operatorId);
        }
    }

    // TODO: documentation
    function _deregisterOperator(
        address operator
    ) internal virtual {
        if (operatorStatus[operator] == OperatorStatus.REGISTERED) {

            operatorStatus[operator] = OperatorStatus.DEREGISTERED;
            serviceManager.deregisterOperatorFromAVS(operator);

            // TODO: event
            // emit OperatorDeregistered(operator, operatorId);
        }
    }

    // @notice TODO: proper documentation
    function _evaluateOperatorSet(
        address[] memory operatorsToEvaluate,
        uint256 minimumWeight
    ) internal virtual {
        address lastOperator = address(0);
        uint256 _currentEpoch = currentEpoch();
        require(operatorsForEpoch[_currentEpoch].length == 0, "operator set already set for epoch");
        // add any registered operator that meets the weight requirement to the current epoch's operator set
        for (uint256 i = 0; i < operatorsToEvaluate.length; ++i) {
            // check for duplicates
            require(operatorsToEvaluate[i] > lastOperator, "failed the duplicate check");
            if (operatorStatus[operatorsToEvaluate[i]] == OperatorStatus.REGISTERED) {
                uint256 operatorWeight = weightOfOperator(operatorsToEvaluate[i]);
                if (operatorWeight >= minimumWeight) {
                    operatorsForEpoch[_currentEpoch].push(operatorsToEvaluate[i]);
                    _operatorStakeHistory[operatorsToEvaluate[i]][_currentEpoch] = operatorWeight;
                    // TODO: add event
                }
            }
        }
    }

    /*******************************************************************************
                            VIEW FUNCTIONS
    *******************************************************************************/
    /// @notice converts a UTC timestamp to an epoch number. Reverts if the timestamp is prior to the initial epoch
    function timestampToEpoch(uint256 timestamp) public view returns (uint256) {
        require(timestamp >= epochZeroStart, "TODO: informative revert message");
        return (timestamp - epochZeroStart) / epochLengthSeconds;
    }

    // @dev reverts if the 0-th epoch has not yet started
    function currentEpoch() public view returns (uint256) {
        return (block.timestamp - epochZeroStart) / epochLengthSeconds;
    }

    // @notice Returns the UTC timestamp at which the `epochNumber`-th epoch begins
    function epochStart(uint256 epochNumber) public view returns (uint256) {
        return epochZeroStart + (epochNumber * epochLengthSeconds);
    }

    // @notice Returns the stake weight for the `operator` in the current epoch
    function currentStake(address operator) public view returns (uint256) {
        return operatorStakeHistory(operator, currentEpoch());
    }

    // @notice Returns the total stake weight for in the current epoch
    function currentTotalStake() public view returns (uint256) {
        return totalStakeHistory[currentEpoch()];
    }
}
