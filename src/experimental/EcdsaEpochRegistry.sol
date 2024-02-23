// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IServiceManager} from "../interfaces/IServiceManager.sol";

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

/**
 * @notice A simplified AVS 'Registry' contract, which uses the concept of epochs, somewhat analagously to
 * a tendermint blockchain.
 * Operators can register or deregister *at any time*, which sets a flag and passes a call onto the ServiceManager.
 * Regardless of these actions, the operator set (you can think of this as the "active" operators) for an epoch does
 * not change -- it is established once for the epoch, and after that the set and the weights of operators are fixed
 * for the remainder of the epoch.
 * @dev For establishing the operator set:
 * The call is permissioned, which is perhaps one of the main shortcomings of this design.
 * At the start of each epoch, the contract owner provides a list of operator addresses, and a minimum weight requirement.
 * Any operators in that list which are actively registered + meet the requirement go into the set of operators for the epoch.
 * See the `evaluateOperatorSet` function for more details.
 */
contract EcdsaEpochRegistry is OwnableUpgradeable {
    
    /// @notice Constant used as a divisor in calculating weights.
    uint256 public constant WEIGHTING_DIVISOR = 1e18;
    /// @notice Maximum length of dynamic arrays in the `strategiesConsideredAndMultipliers` mapping.
    uint8 public constant MAX_WEIGHING_FUNCTION_LENGTH = 32;

    /// @notice the ServiceManager for this AVS, which forwards calls onto EigenLayer's core contracts
    IServiceManager public immutable serviceManager;
    /// @notice The address of the Delegation contract for EigenLayer.
    IDelegationManager public immutable delegation;

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

    /**
     * @notice In weighing a particular strategy, the amount of underlying asset for that strategy is
     * multiplied by its multiplier, then divided by WEIGHTING_DIVISOR
     */
    struct StrategyParams {
        IStrategy strategy;
        uint96 multiplier;
    }

    // @notice list of strategies considered and their corresponding multipliers for this AVS     
    StrategyParams[] public strategyParams;

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
    uint256[45] private __GAP;

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
    ) {
        serviceManager = _serviceManager;
        delegation = _delegationManager;
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
        if (operatorStatus[operator] != OperatorStatus.REGISTERED) {
            operatorStatus[operator] = OperatorStatus.REGISTERED;

            // Register the operator with the EigenLayer via this AVS's ServiceManager
            serviceManager.registerOperatorToAVS(operator, operatorSignature);

            // TODO: event
            // emit OperatorRegistered(operator, operatorId);
        }
    }

    // @notice Deregisters the msg.sender.
    function deregisterOperator() public virtual {
        address operator = msg.sender;
        if (operatorStatus[operator] == OperatorStatus.REGISTERED) {

            operatorStatus[operator] = OperatorStatus.DEREGISTERED;
            serviceManager.deregisterOperatorFromAVS(operator);

            // TODO: event
            // emit OperatorDeregistered(operator, operatorId);
        }
    }


    /*******************************************************************************
                    EXTERNAL FUNCTIONS -- permissioned
    *******************************************************************************/
    /** 
     * @notice Adds strategies and weights
     * @dev Checks to make sure that the *same* strategy cannot be added multiple times (checks against both against existing and new strategies).
     * @dev This function has no check to make sure that the strategies for a single quorum have the same underlying asset. This is a concious choice,
     * since a middleware may want, e.g., a stablecoin quorum that accepts USDC, USDT, DAI, etc. as underlying assets and treats them as "equivalent".
     */
    function addStrategies(
        StrategyParams[] memory _strategyParams
    ) public virtual onlyOwner {
        _addStrategyParams(_strategyParams);
    }

    /**
     * @notice Remove strategies and their associated weights from the considered strategies
     * @dev higher indices should be *first* in the list of @param indicesToRemove, since otherwise
     * the removal of lower index entries will cause a shift in the indices of the other strategies to remove
     */
    function removeStrategies(
        uint256[] memory indicesToRemove
    ) public virtual onlyOwner {
        uint256 toRemoveLength = indicesToRemove.length;
        require(toRemoveLength > 0, "StakeRegistry.removeStrategies: no indices to remove provided");
        for (uint256 i = 0; i < toRemoveLength; i++) {
            // TODO: events
            // emit StrategyRemovedFromQuorum(quorumNumber, _strategyParams[indicesToRemove[i]].strategy);
            // emit StrategyMultiplierUpdated(quorumNumber, _strategyParams[indicesToRemove[i]].strategy, 0);

            // Replace index to remove with the last item in the list, then pop the last item
            strategyParams[indicesToRemove[i]] = strategyParams[strategyParams.length - 1];
            strategyParams.pop();
        }
    }

    /**
     * @notice Modifies the weights of existing strategies for a specific quorum
     * @param strategyIndices are the indices of the strategies to change
     * @param newMultipliers are the new multipliers for the strategies
     */
    function modifyStrategyParams(
        uint256[] calldata strategyIndices,
        uint96[] calldata newMultipliers
    ) public virtual onlyOwner {
        uint256 numStrats = strategyIndices.length;
        require(numStrats > 0, "StakeRegistry.modifyStrategyParams: no strategy indices provided");
        require(newMultipliers.length == numStrats, "StakeRegistry.modifyStrategyParams: input length mismatch");

        for (uint256 i = 0; i < numStrats; i++) {
            // Change the strategy's associated multiplier
            strategyParams[strategyIndices[i]].multiplier = newMultipliers[i];
            // TODO: events
            // emit StrategyMultiplierUpdated(quorumNumber, strategyParams[strategyIndices[i]].strategy, newMultipliers[i]);
        }
    }

    // @notice TODO: proper documentation
    function evaluateOperatorSet(
        address[] calldata operatorsToEvaluate,
        uint256 minimumWeight
    ) public virtual onlyOwner {
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
                            INTERNAL FUNCTIONS
    *******************************************************************************/
    /** 
     * @notice Adds `_strategyParams` to consideration.
     * @dev Checks to make sure that the *same* strategy cannot be added multiple times (checks against both against existing and new strategies).
     * @dev This function has no check to make sure that the strategies for a single quorum have the same underlying asset. This is a concious choice,
     * since a middleware may want, e.g., a stablecoin quorum that accepts USDC, USDT, DAI, etc. as underlying assets and treats them as "equivalent".
     */
    function _addStrategyParams(
        StrategyParams[] memory _strategyParams
    ) internal {
        require(_strategyParams.length > 0, "StakeRegistry._addStrategyParams: no strategies provided");
        uint256 numStratsToAdd = _strategyParams.length;
        uint256 numStratsExisting = strategyParams.length;
        require(
            numStratsExisting + numStratsToAdd <= MAX_WEIGHING_FUNCTION_LENGTH,
            "StakeRegistry._addStrategyParams: exceed MAX_WEIGHING_FUNCTION_LENGTH"
        );
        for (uint256 i = 0; i < numStratsToAdd; i++) {
            // fairly gas-expensive internal loop to make sure that the *same* strategy cannot be added multiple times
            for (uint256 j = 0; j < (numStratsExisting + i); j++) {
                require(
                    strategyParams[j].strategy != _strategyParams[i].strategy,
                    "StakeRegistry._addStrategyParams: cannot add same strategy 2x"
                );
            }
            require(
                _strategyParams[i].multiplier > 0,
                "StakeRegistry._addStrategyParams: cannot add strategy with zero weight"
            );
            strategyParams.push(_strategyParams[i]);
            // TODO: events
            // emit StrategyAddedToQuorum(quorumNumber, _strategyParams[i].strategy);
            // emit StrategyMultiplierUpdated(_strategyParams[i].strategy, _strategyParams[i].multiplier);
        }
    }

    /*******************************************************************************
                            VIEW FUNCTIONS
    *******************************************************************************/

    /**
     * @notice This function computes the total weight of the @param operator.
     * @return `uint256` The weighted sum of the operator's shares across each strategy considered
     */
    function weightOfOperator(address operator) public virtual view returns (uint256) {
        uint256 weight;
        uint256 stratsLength = strategyParamsLength();
        StrategyParams memory strategyAndMultiplier;

        for (uint256 i = 0; i < stratsLength; i++) {
            // accessing i^th StrategyParams struct
            strategyAndMultiplier = strategyParams[i];

            // shares of the operator in the strategy
            uint256 sharesAmount = delegation.operatorShares(operator, strategyAndMultiplier.strategy);

            // add the weight from the shares for this strategy to the total weight
            if (sharesAmount > 0) {
                weight += uint96(sharesAmount * strategyAndMultiplier.multiplier / WEIGHTING_DIVISOR);
            }
        }
        return weight;
    }

    /// @notice Returns the length of the dynamic array stored in `strategyParams`.
    function strategyParamsLength() public view returns (uint256) {
        return strategyParams.length;
    }

    /// @notice Returns the strategy and weight multiplier for the `index`'th strategy
    function strategyParamsByIndex(
        uint256 index
    ) public view returns (StrategyParams memory)
    {
        return strategyParams[index];
    }

    /// @notice converts a UTC timestamp to an epoch number. Reverts if the timestamp is prior to the initial epoch
    function timestampToEpoch(uint256 timestamp) public view returns (uint256) {
        require(timestamp >= epochZeroStart, "TODO: informative revert message");
        return (timestamp - epochZeroStart) / epochLengthSeconds;
    }

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
