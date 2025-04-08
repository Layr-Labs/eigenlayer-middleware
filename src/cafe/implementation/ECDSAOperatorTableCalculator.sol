// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./interfaces/IECDSATypes.sol";
import "./interfaces/IECDSAOperatorTableCalculator.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title ECDSAOperatorTableCalculator
 * @notice Calculates operator tables with ECDSA keys and stake weights
 * @dev Default implementation that returns operators with their ECDSA keys and 
 *      linearly combined weights. AVSs can extend this for custom behavior.
 */
contract ECDSAOperatorTableCalculator is IECDSAOperatorTableCalculator, Ownable {
    using Address for address;

    /// @notice Error thrown when the weight calculation fails
    error WeightCalculationFailed(address operator, string reason);

    /// @notice Error thrown when an operator set is not found
    error OperatorSetNotFound(address avs, uint32 id);
    
    /// @notice Error thrown when weights array length is invalid
    error InvalidWeightsLength(uint256 provided, uint256 expected);

    /// @dev AVS to strategy multiplier mapping
    mapping(address => mapping(uint32 => mapping(address => uint16))) private _strategyMultipliers;
    
    /// @dev AVS to strategy addresses
    mapping(address => mapping(uint32 => address[])) private _strategies;
    
    /// @dev AVS to operator set to registered operator addresses
    mapping(address => mapping(uint32 => address[])) private _operators;
    
    /// @dev Basis points denominator for strategy weight calculations
    uint16 private constant BPS_DENOMINATOR = 10000;
    
    /// @dev Weight array configuration - number of weight values per operator 
    uint256 private _weightCount;

    /**
     * @notice Emitted when strategy configuration is updated
     * @param avs The AVS address
     * @param id The operator set ID
     * @param strategies The configured strategies
     * @param multipliers The multipliers for each strategy
     */
    event StrategiesConfigured(
        address indexed avs, 
        uint32 indexed id, 
        address[] strategies,
        uint16[] multipliers
    );
    
    /**
     * @notice Emitted when operators are registered to a set
     * @param avs The AVS address
     * @param id The operator set ID
     * @param operators The registered operators
     */
    event OperatorsRegistered(
        address indexed avs, 
        uint32 indexed id, 
        address[] operators
    );

    /**
     * @notice Constructs the calculator with initial weight configuration
     * @param weightCount_ Number of weight values per operator
     */
    constructor(uint256 weightCount_) {
        setWeightCount(weightCount_);
    }

    /**
     * @notice Calculates operator table for a given operator set
     * @param operatorSet The operator set to calculate for
     * @return operatorInfos Array of operator infos with pubkeys and weights
     */
    function calculateOperatorTable(IECDSATypes.OperatorSet calldata operatorSet) 
        external view override returns(IECDSATypes.ECDSAOperatorInfo[] memory operatorInfos) 
    {
        address avs = operatorSet.avs;
        uint32 id = operatorSet.id;
        
        address[] memory operators = _operators[avs][id];
        if (operators.length == 0) {
            revert OperatorSetNotFound(avs, id);
        }
        
        operatorInfos = new IECDSATypes.ECDSAOperatorInfo[](operators.length);
        
        // Get all strategies for this AVS/operator set
        address[] memory strategies = _strategies[avs][id];
        
        for (uint256 i = 0; i < operators.length; i++) {
            address operator = operators[i];
            
            // Set the pubkey (in this case, just the operator address since we're using ECDSA)
            operatorInfos[i].pubkey = operator;
            
            // Calculate weights based on strategies
            operatorInfos[i].weights = _calculateWeights(avs, id, operator, strategies);
        }
        
        // Sort operators by pubkey address (for efficient binary search during verification)
        _sortOperatorInfos(operatorInfos);
        
        return operatorInfos;
    }
    
    /**
     * @notice Sets the number of weight values per operator
     * @param weightCount_ New weight count
     * @dev Only the owner can call this function
     */
    function setWeightCount(uint256 weightCount_) public onlyOwner {
        require(weightCount_ > 0, "Weight count must be positive");
        _weightCount = weightCount_;
    }
    
    /**
     * @notice Gets the current weight count configuration
     * @return Current weight count
     */
    function getWeightCount() external view returns (uint256) {
        return _weightCount;
    }
    
    /**
     * @notice Configures strategies and multipliers for an operator set
     * @param avs The AVS address
     * @param id The operator set ID
     * @param strategies_ The strategy addresses
     * @param multipliers The multipliers for each strategy
     * @dev Only the owner can call this function
     */
    function configureStrategies(
        address avs,
        uint32 id,
        address[] calldata strategies_,
        uint16[] calldata multipliers
    ) external onlyOwner {
        require(strategies_.length == multipliers.length, "Length mismatch");
        require(strategies_.length > 0, "No strategies provided");
        
        // Remove old strategy configurations
        address[] memory oldStrategies = _strategies[avs][id];
        for (uint256 i = 0; i < oldStrategies.length; i++) {
            delete _strategyMultipliers[avs][id][oldStrategies[i]];
        }
        
        // Store new strategies
        _strategies[avs][id] = strategies_;
        
        // Store multipliers
        uint16 totalMultiplier = 0;
        for (uint256 i = 0; i < strategies_.length; i++) {
            _strategyMultipliers[avs][id][strategies_[i]] = multipliers[i];
            totalMultiplier += multipliers[i];
        }
        
        require(totalMultiplier == BPS_DENOMINATOR, "Multipliers must sum to 10000");
        
        emit StrategiesConfigured(avs, id, strategies_, multipliers);
    }
    
    /**
     * @notice Registers operators to an operator set
     * @param avs The AVS address
     * @param id The operator set ID
     * @param operators_ The operator addresses
     * @dev Only the owner can call this function
     */
    function registerOperators(
        address avs,
        uint32 id,
        address[] calldata operators_
    ) external onlyOwner {
        require(operators_.length > 0, "No operators provided");
        
        // Replace existing operators
        _operators[avs][id] = operators_;
        
        emit OperatorsRegistered(avs, id, operators_);
    }
    
    /**
     * @notice Calculates weights for an operator based on strategies
     * @param avs The AVS address
     * @param id The operator set ID
     * @param operator The operator address
     * @param strategies The strategy addresses
     * @return Array of weights
     */
    function _calculateWeights(
        address avs,
        uint32 id,
        address operator,
        address[] memory strategies
    ) internal view returns (uint96[] memory) {
        uint96[] memory weights = new uint96[](_weightCount);
        
        if (_weightCount == 1) {
            // Single weight configuration: [slashable_weight]
            weights[0] = _calculateCombinedWeight(avs, id, operator, strategies);
        } 
        else if (_weightCount == 2) {
            // Dual weight configuration: [slashable_weight, delegated_weight]
            weights[0] = _calculateCombinedWeight(avs, id, operator, strategies);
            weights[1] = _calculateDelegatedWeight(operator, strategies);
        }
        else {
            // Multi-strategy configuration
            for (uint256 i = 0; i < strategies.length && i*2 < _weightCount; i++) {
                (uint96 slashableWeight, uint96 delegatedWeight) = _calculateStrategyWeights(operator, strategies[i]);
                weights[i*2] = slashableWeight;
                if (i*2+1 < _weightCount) {
                    weights[i*2+1] = delegatedWeight;
                }
            }
        }
        
        return weights;
    }
    
    /**
     * @notice Calculates combined weight across all strategies
     * @param avs The AVS address
     * @param id The operator set ID
     * @param operator The operator address
     * @param strategies The strategy addresses
     * @return Combined weight
     */
    function _calculateCombinedWeight(
        address avs,
        uint32 id,
        address operator,
        address[] memory strategies
    ) internal view returns (uint96) {
        uint256 totalWeight = 0;
        
        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            uint16 multiplier = _strategyMultipliers[avs][id][strategy];
            
            (uint96 slashableWeight,) = _calculateStrategyWeights(operator, strategy);
            
            // Apply multiplier and add to total
            totalWeight += uint256(slashableWeight) * multiplier / BPS_DENOMINATOR;
        }
        
        return uint96(totalWeight);
    }
    
    /**
     * @notice Calculates delegated weight across all strategies
     * @param operator The operator address
     * @param strategies The strategy addresses
     * @return Delegated weight
     */
    function _calculateDelegatedWeight(
        address operator,
        address[] memory strategies
    ) internal view returns (uint96) {
        uint256 totalWeight = 0;
        
        for (uint256 i = 0; i < strategies.length; i++) {
            (, uint96 delegatedWeight) = _calculateStrategyWeights(operator, strategies[i]);
            totalWeight += delegatedWeight;
        }
        
        return uint96(totalWeight);
    }
    
    /**
     * @notice Calculates slashable and delegated weights for a specific strategy
     * @param operator The operator address
     * @param strategy The strategy address
     * @return slashableWeight The slashable weight
     * @return delegatedWeight The delegated weight
     */
    function _calculateStrategyWeights(
        address operator,
        address strategy
    ) internal view returns (uint96 slashableWeight, uint96 delegatedWeight) {
        // In a real implementation, this would query the Eigenlayer contracts
        // or any other source of stake information.
        // For simplicity, we're returning mock values here.
        
        try this.mockExternalWeightCall(operator, strategy) returns (uint96 slashable, uint96 delegated) {
            return (slashable, delegated);
        } catch Error(string memory reason) {
            revert WeightCalculationFailed(operator, reason);
        }
    }
    
    /**
     * @notice Mock external call to simulate weight calculation
     * @dev This simulates an external call that might fail
     */
    function mockExternalWeightCall(address operator, address strategy) external view returns (uint96, uint96) {
        // Simulate querying external contracts for weights
        // In production, this would call into Eigenlayer or other stake sources
        
        // Simple deterministic weight based on addresses
        uint256 operatorValue = uint256(uint160(operator));
        uint256 strategyValue = uint256(uint160(strategy));
        
        uint96 slashableWeight = uint96((operatorValue ^ strategyValue) % 1000000);
        uint96 delegatedWeight = uint96((operatorValue & strategyValue) % 2000000);
        
        return (slashableWeight, delegatedWeight);
    }
    
    /**
     * @notice Sorts operator infos by pubkey (address) in ascending order
     * @param operatorInfos The operator infos to sort
     */
    function _sortOperatorInfos(IECDSATypes.ECDSAOperatorInfo[] memory operatorInfos) internal pure {
        // Simple insertion sort for operator infos
        for (uint i = 1; i < operatorInfos.length; i++) {
            IECDSATypes.ECDSAOperatorInfo memory temp = operatorInfos[i];
            int j = int(i) - 1;
            
            while (j >= 0 && operatorInfos[uint(j)].pubkey > temp.pubkey) {
                operatorInfos[uint(j + 1)] = operatorInfos[uint(j)];
                j--;
            }
            
            operatorInfos[uint(j + 1)] = temp;
        }
    }
} 