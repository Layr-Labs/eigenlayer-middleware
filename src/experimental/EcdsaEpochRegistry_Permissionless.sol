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

    // @notice minimum weight for operators to register
    uint256 minimumWeight;

    // @notice the `minimumWeight` is adjusted each epoch, to help target the `targetOperatorSetSize`
    uint256 targetOperatorSetSize;

    // @notice upper bound on length of `registeredOperators` array
    uint256 maxRegisteredOperators;

    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[46] private __GAP;

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
        uint256 _minimumWeightInitValue,
        uint256 _targetOperatorSetSize,
        uint256 _maxRegisteredOperators
    )
        EcdsaEpochRegistry_Modular(_serviceManager, _delegationManager, _epochLengthSeconds, _epochZeroStart)
    {
        require(_targetOperatorSetSize != 0, "no.");
        require(_maxRegisteredOperators >= _targetOperatorSetSize, "cannot target above max size");
        minimumWeight = _minimumWeightInitValue;
        emit MinimumWeightChanged(_minimumWeightInitValue);
        targetOperatorSetSize = _targetOperatorSetSize;
        maxRegisteredOperators = _maxRegisteredOperators;
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
        uint256 /*minimumWeight*/
    ) public virtual override {
        _adjustMinimumWeight();
        uint256 _currentEpoch = currentEpoch();
        uint256 _numberRegisteredOperators = numberRegisteredOperators();
        require(operatorsForEpoch[_currentEpoch].length == 0, "operator set already set for epoch");
        for (uint256 i = 0; i < _numberRegisteredOperators; ++i) {
            address operator = registeredOperators[i];
            uint256 operatorWeight = weightOfOperator(operator);
            // add any registered operator that meets the weight requirement to the current epoch's operator set
            if (operatorWeight >= minimumWeight) {
                operatorsForEpoch[_currentEpoch].push(operator);
                _operatorStakeHistory[operator][_currentEpoch] = operatorWeight;
                // TODO: add event
            // otherwise, evict the operator
            } else {
                _deregisterOperator(operator);
            }
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
            require(weightOfOperator(operator) >= minimumWeight,
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
    function _adjustMinimumWeight() internal virtual {
        uint256 currentOperatorSetSize = numberRegisteredOperators();
        uint256 previousMinimumWeight = minimumWeight;
        uint256 _currentEpoch = currentEpoch();
        uint256 previousEpoch = (_currentEpoch != 0) ? _currentEpoch - 1 : _currentEpoch;

        uint256 subscriptionFactor = (1e18 * currentOperatorSetSize) / targetOperatorSetSize;
        uint256 previousEpochOperatorSetSize = operatorsForEpoch[previousEpoch].length;
        uint256 previousEpochAverageWeight = totalStakeHistory[previousEpoch] / previousEpochOperatorSetSize;

        uint256 newMinFromAverage = (previousEpochAverageWeight * 1e18) / subscriptionFactor;
        uint256 newMinFromPreviousMin = (previousMinimumWeight * 1e18) / subscriptionFactor;

        uint256 newMinimumWeight = max(newMinFromAverage, newMinFromPreviousMin);
        minimumWeight = newMinimumWeight;
        emit MinimumWeightChanged(newMinimumWeight);
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a >= b ? a : b);
    }
}
