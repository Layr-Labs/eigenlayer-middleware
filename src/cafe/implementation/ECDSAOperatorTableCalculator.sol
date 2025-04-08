// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./interfaces/IECDSATypes.sol";
import "./interfaces/IECDSAOperatorTableCalculator.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

/**
 * @title ECDSAOperatorTableCalculator
 * @notice Calculates operator tables with ECDSA keys and stake weights
 * @dev Default implementation that returns operators with their ECDSA keys and 
 *      stake weights fetched from EigenLayer contracts
 */
contract ECDSAOperatorTableCalculator is IECDSAOperatorTableCalculator, Ownable {
    using Address for address;

    /* ========== CUSTOM ERRORS ========== */
    
    /// @notice Error thrown when the weight calculation fails
    error WeightCalculationFailed(address operator, string reason);

    /// @notice Error thrown when an operator set is not found
    error OperatorSetNotFound(address avs, uint32 id);
    
    /// @notice Error thrown when weights array length is invalid
    error InvalidWeightsLength(uint256 provided, uint256 expected);
    
    /// @notice Error thrown when strategy configuration is invalid
    error InvalidStrategyConfiguration(string reason);
    
    /// @notice Error thrown when allocation manager is not set
    error AllocationManagerNotSet();

    /* ========== STATE VARIABLES ========== */
    
    /// @notice The allocation manager contract for accessing slashable stakes
    IAllocationManager public allocationManager;
    
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
    
    /// @dev Constants for weight array indices
    uint8 private constant SLASHABLE_WEIGHT_INDEX = 0;
    uint8 private constant DELEGATED_WEIGHT_INDEX = 1;

    /* ========== EVENTS ========== */
    
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
     * @notice Emitted when allocation manager is updated
     * @param previousAllocationManager The previous allocation manager address
     * @param newAllocationManager The new allocation manager address
     */
    event AllocationManagerUpdated(
        address indexed previousAllocationManager,
        address indexed newAllocationManager
    );

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructs the calculator with initial weight configuration
     * @param weightCount_ Number of weight values per operator
     * @param allocationManager_ The allocation manager contract address
     */
    constructor(uint256 weightCount_, address allocationManager_) {
        setWeightCount(weightCount_);
        _setAllocationManager(allocationManager_);
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @inheritdoc IECDSAOperatorTableCalculator
     */
    function calculateOperatorTable(IECDSATypes.OperatorSet calldata operatorSet) 
        external view override returns(IECDSATypes.ECDSAOperatorInfo[] memory operatorInfos) 
    {
        address avs = operatorSet.avs;
        uint32 id = operatorSet.id;
        
        // Get the list of operators for this AVS/ID
        address[] memory operators = _operators[avs][id];
        if (operators.length == 0) {
            revert OperatorSetNotFound(avs, id);
        }
        
        // Check if allocation manager is set
        if (address(allocationManager) == address(0)) {
            revert AllocationManagerNotSet();
        }
        
        // Create operator info array
        operatorInfos = new IECDSATypes.ECDSAOperatorInfo[](operators.length);
        
        // Get all strategies for this AVS/operator set
        address[] memory strategies = _strategies[avs][id];
        
        // Calculate weights for each operator
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
        if (weightCount_ == 0) {
            revert InvalidWeightsLength(weightCount_, 1);
        }
        _weightCount = weightCount_;
    }
    
    /**
     * @notice Updates the allocation manager contract address
     * @param newAllocationManager The new allocation manager address
     * @dev Only the owner can call this function
     */
    function setAllocationManager(address newAllocationManager) external onlyOwner {
        _setAllocationManager(newAllocationManager);
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
        if (strategies_.length != multipliers.length) {
            revert InvalidStrategyConfiguration("Length mismatch");
        }
        
        if (strategies_.length == 0) {
            revert InvalidStrategyConfiguration("No strategies provided");
        }
        
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
            // Check for address zero
            if (strategies_[i] == address(0)) {
                revert InvalidStrategyConfiguration("Zero strategy address");
            }
            
            // Check for duplicate strategies
            for (uint256 j = 0; j < i; j++) {
                if (strategies_[j] == strategies_[i]) {
                    revert InvalidStrategyConfiguration("Duplicate strategy");
                }
            }
            
            // Check for zero multiplier
            if (multipliers[i] == 0) {
                revert InvalidStrategyConfiguration("Zero multiplier");
            }
            
            _strategyMultipliers[avs][id][strategies_[i]] = multipliers[i];
            totalMultiplier += multipliers[i];
        }
        
        // Ensure multipliers sum to 100%
        if (totalMultiplier != BPS_DENOMINATOR) {
            revert InvalidStrategyConfiguration("Multipliers must sum to 10000");
        }
        
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
        if (operators_.length == 0) {
            revert InvalidStrategyConfiguration("No operators provided");
        }
        
        // Check for duplicate operators
        for (uint256 i = 0; i < operators_.length; i++) {
            if (operators_[i] == address(0)) {
                revert InvalidStrategyConfiguration("Zero operator address");
            }
            
            for (uint256 j = 0; j < i; j++) {
                if (operators_[j] == operators_[i]) {
                    revert InvalidStrategyConfiguration("Duplicate operator");
                }
            }
        }
        
        // Replace existing operators
        _operators[avs][id] = operators_;
        
        emit OperatorsRegistered(avs, id, operators_);
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    
    /**
     * @notice Sets the allocation manager
     * @param newAllocationManager The new allocation manager address
     */
    function _setAllocationManager(address newAllocationManager) internal {
        if (newAllocationManager == address(0)) {
            revert InvalidStrategyConfiguration("Zero allocation manager address");
        }
        
        address previousAllocationManager = address(allocationManager);
        allocationManager = IAllocationManager(newAllocationManager);
        
        emit AllocationManagerUpdated(previousAllocationManager, newAllocationManager);
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
            weights[SLASHABLE_WEIGHT_INDEX] = _calculateCombinedWeight(avs, id, operator, strategies);
        } 
        else if (_weightCount == 2) {
            // Dual weight configuration: [slashable_weight, delegated_weight]
            weights[SLASHABLE_WEIGHT_INDEX] = _calculateCombinedWeight(avs, id, operator, strategies);
            weights[DELEGATED_WEIGHT_INDEX] = _calculateDelegatedWeight(operator, strategies);
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
        // Create single-element arrays for operator and strategy
        address[] memory operators = new address[](1);
        operators[0] = operator;
        
        // Create IStrategy array with the strategy
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(strategy);
        
        // Get current block number for stakes
        uint32 futureBlock = uint32(block.number);
        
        try allocationManager.getMinimumSlashableStake(
            OperatorSet({avs: strategy, id: 0}), // Strategy represents AVS and ID 0
            operators,
            strategies,
            futureBlock
        ) returns (uint256[][] memory slashableStake) {
            // If we have results, use the first operator's first strategy stake
            if (slashableStake.length > 0 && slashableStake[0].length > 0) {
                slashableWeight = uint96(slashableStake[0][0]);
            } else {
                slashableWeight = 0;
            }
            
            // In a real implementation, this would also fetch delegated stake
            // For this example, we'll set delegated to double the slashable
            delegatedWeight = uint96(uint256(slashableWeight) * 2);
            
            return (slashableWeight, delegatedWeight);
        } catch Error(string memory reason) {
            revert WeightCalculationFailed(operator, reason);
        } catch {
            revert WeightCalculationFailed(operator, "Unknown error fetching stake");
        }
    }
    
    /**
     * @notice Sorts operator infos by pubkey (address) in ascending order
     * @param operatorInfos The operator infos to sort
     */
    function _sortOperatorInfos(IECDSATypes.ECDSAOperatorInfo[] memory operatorInfos) internal pure {
        // Simple insertion sort for operator infos (gas efficient for small arrays)
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