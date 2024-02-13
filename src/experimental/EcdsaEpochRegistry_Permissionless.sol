// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IServiceManager} from "../interfaces/IServiceManager.sol";

import {EcdsaEpochRegistry_Modular} from "./EcdsaEpochRegistry_Modular.sol";

contract EcdsaEpochRegistry_Permissionless is EcdsaEpochRegistry_Modular {
    // @notice unordered list of all currently-registered operators
    address[] public registeredOperators;

    function numberRegisteredOperators() public view virtual returns (uint256) {
        return registeredOperators.length;
    }

    // @notice Mapping: operator address => current index in `registeredOperators` array
    mapping(address => uint256) public operatorIndex;

    // @notice Mapping epoch => the minimum weight of the operators for that epoch
    mapping(uint256 => uint256) public realizedMinimumWeight;

    // @notice minimum weight for operators to register
    uint256 public minimumWeightRequirement;

    // @notice the `minimumWeightRequirement` is adjusted each epoch, to help target the `targetOperatorSetSize`
    uint256 public targetOperatorSetSize;

    // @notice upper bound on length of `registeredOperators` array
    uint256 public maxRegisteredOperators;

    // @notice default value to which the `minimumWeightRequirement` will reset in the event that there were zero operators in the previous epoch
    uint256 public defaultWeightRequirement;

    // @notice exponential weight requirement retargeting factor
    uint256 public retargetingFactorWei;

    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[44] private __GAP;

    event MinimumWeightChanged(uint256 newValue);

    /** 
     * @dev setting the `_epochZeroStart` to be in the past is disallowed.
     * If you try to do so, the current block.timestamp will be used instead.
     * Future times are allowed, with no safety check in place.
     */
    constructor(
        IServiceManager _serviceManager,
        IDelegationManager _delegationManager,
        uint256 _epochLengthSeconds,
        uint256 _epochZeroStart,
        uint256 _minimumWeightRequirementInitValue,
        uint256 _targetOperatorSetSize,
        uint256 _maxRegisteredOperators,
        uint256 _defaultWeightRequirement,
        uint256 _retargetingFactorWei
    )
        EcdsaEpochRegistry_Modular(_serviceManager, _delegationManager, _epochLengthSeconds, _epochZeroStart)
    {
        require(_targetOperatorSetSize != 0, "no.");
        require(_maxRegisteredOperators > _targetOperatorSetSize, "max must be above target");
        minimumWeightRequirement = _minimumWeightRequirementInitValue;
        emit MinimumWeightChanged(_minimumWeightRequirementInitValue);
        targetOperatorSetSize = _targetOperatorSetSize;
        maxRegisteredOperators = _maxRegisteredOperators;
        defaultWeightRequirement = _defaultWeightRequirement;
        retargetingFactorWei = _retargetingFactorWei;
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
    ) public virtual override {
        address operator = msg.sender;
        _registerOperator(operator, operatorSignature);
    }

    // @notice Deregisters the msg.sender.
    function deregisterOperator() public virtual override {
        address operator = msg.sender;
        _deregisterOperator(operator);
    }

    // TODO: documentation
    // evaluates the operator set for the current epoch
    function evaluateOperatorSet(
        address[] memory /*operatorsToEvaluate*/,
        uint256 /*minimumWeightRequirement*/
    ) public virtual override {
        uint256 _currentEpoch = currentEpoch();
        require(operatorsForEpoch[_currentEpoch].length == 0, "operator set already calculated for current epoch");

        uint256 _numberRegisteredOperators = numberRegisteredOperators();
        uint256 _realizedMinimumWeight = type(uint256).max;

        for (uint256 i = 0; i < _numberRegisteredOperators; ++i) {
            address operator = registeredOperators[i];
            uint256 operatorWeight = weightOfOperator(operator);
            // add any registered operator that meets the weight requirement to the current epoch's operator set
            if (operatorWeight >= minimumWeightRequirement) {
                operatorsForEpoch[_currentEpoch].push(operator);
                _operatorStakeHistory[operator][_currentEpoch] = operatorWeight;
                // TODO: add event
                if (operatorWeight < _realizedMinimumWeight) {
                    _realizedMinimumWeight = operatorWeight;
                }
            // otherwise, evict the operator
            } else {
                _deregisterOperator(operator);
            }
        }

        // require(operatorsForEpoch[_currentEpoch].length != 0, "no operators found for current epoch");
        realizedMinimumWeight[_currentEpoch] = _realizedMinimumWeight;

        // perform exponential retargeting -- adjust `minimumWeightRequirement` to target the desired number of operators
        if (_currentEpoch != 0) {
            _adjustMinimumWeight({previousEpoch: _currentEpoch - 1});
        }
    }

    /*******************************************************************************
                            INTERNAL FUNCTIONS
    *******************************************************************************/
    // TODO: documentation
    function _registerOperator(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) internal virtual override {
        if (operatorStatus[operator] != OperatorStatus.REGISTERED) {
            require(weightOfOperator(operator) >= minimumWeightRequirement,
                "insufficient weight to register");
            operatorStatus[operator] = OperatorStatus.REGISTERED;

            // Register the operator with the EigenLayer via this AVS's ServiceManager
            serviceManager.registerOperatorToAVS(operator, operatorSignature);

            // TODO: event
            // emit OperatorRegistered(operator, operatorId);

            operatorIndex[operator] = numberRegisteredOperators();
            registeredOperators.push(operator);
        }
    }

    // TODO: documentation
    function _deregisterOperator(
        address operator
    ) internal virtual override {
        if (operatorStatus[operator] == OperatorStatus.REGISTERED) {

            operatorStatus[operator] = OperatorStatus.DEREGISTERED;
            serviceManager.deregisterOperatorFromAVS(operator);

            // TODO: event
            // emit OperatorDeregistered(operator, operatorId);

            // swap-and-pop routine to keep indices correct
            uint256 numRegisteredOperators = numberRegisteredOperators();
            uint256 deregisteredIndex = operatorIndex[operator];
            address lastOperatorInArray = registeredOperators[numRegisteredOperators - 1];
            registeredOperators[deregisteredIndex] = lastOperatorInArray;
            operatorIndex[lastOperatorInArray] = deregisteredIndex;
            delete operatorIndex[operator];
            registeredOperators.pop();
        }
    }

    // TODO: documentation
    // only called if `currentEpoch() != 0`
    function _adjustMinimumWeight(uint256 previousEpoch) internal virtual {
        uint256 currentOperatorSetSize = numberRegisteredOperators();
        uint256 newWeightRequirement;
        if (currentOperatorSetSize == 0) {
            newWeightRequirement = defaultWeightRequirement;
        } else {
            // store values in memory
            uint256 previousWeightRequirement = minimumWeightRequirement;
            uint256 _targetOperatorSetSize = targetOperatorSetSize;

            // start with "adjustment" of 1 (leaving the value unchanged)
            uint256 adjustmentFactor = 1e18;
            if (currentOperatorSetSize >= _targetOperatorSetSize) {
                // when current = target, no change
                // when current = max, add the retargetingFactorWei
                // when current is halfway between target and max, add half of retargetingFactorWei
                adjustmentFactor += retargetingFactorWei * (currentOperatorSetSize - _targetOperatorSetSize) / (maxRegisteredOperators - _targetOperatorSetSize);
            } else {
                // when current = target, no change
                // when current = 0, add the retargetingFactorWei
                // when current is halfway between 0 and target, add half of retargetingFactorWei
                adjustmentFactor += retargetingFactorWei * (_targetOperatorSetSize - currentOperatorSetSize) / _targetOperatorSetSize;
            }

            // calculate intermediate values
            uint256 previousEpochOperatorSetSize = operatorsForEpoch[previousEpoch].length;
            uint256 previousEpochAverageWeight = totalStakeHistory[previousEpoch] / previousEpochOperatorSetSize;
            uint256 previousEpochMinimumWeight = realizedMinimumWeight[previousEpoch];

            // find new values -- adjust requirement up if subscriptionFactor < 1, down if > 1
            if (currentOperatorSetSize >= _targetOperatorSetSize) {
                uint256 newMinFromAverage = previousEpochAverageWeight * adjustmentFactor / 1e18;
                uint256 newMinFromPreviousMin = previousEpochMinimumWeight * adjustmentFactor / 1e18;
                // TODO: determine if useful
                uint256 newMinFromPreviousRequirement = previousWeightRequirement * adjustmentFactor / 1e18;
                newWeightRequirement = max(newMinFromAverage, newMinFromPreviousMin);            
            } else {
                uint256 newMinFromAverage = previousEpochAverageWeight * 1e18 / adjustmentFactor;
                uint256 newMinFromPreviousMin = previousEpochMinimumWeight * 1e18 / adjustmentFactor;
                // TODO: determine if useful
                uint256 newMinFromPreviousRequirement = previousWeightRequirement * 1e18 / adjustmentFactor;
                newWeightRequirement = min(newMinFromAverage, newMinFromPreviousMin);            
            }
        }

        minimumWeightRequirement = newWeightRequirement;
        emit MinimumWeightChanged(newWeightRequirement);
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a >= b ? a : b);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a <= b ? a : b);
    }
}
