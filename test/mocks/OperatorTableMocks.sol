// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {OperatorSet} from "../../lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IStrategy} from "../../lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {BN254} from "../../src/libraries/BN254.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IAVSRegistrar
 * @notice Simple interface for AVSRegistrar mock
 */
interface IAVSRegistrar {
    function registerOperator(address operator, bytes calldata data) external;
    function deregisterOperator(address operator) external;
}

/**
 * @title MockStrategy
 * @notice Mock implementation of IStrategy for testing
 */
contract MockStrategy {
    string public name;
    IERC20 public underlyingToken_;
    uint256 public depositLimit_;
    uint256 public withdrawalLimit_;
    
    constructor(string memory _name) {
        name = _name;
        // Use a dummy address for the token
        underlyingToken_ = IERC20(address(0x1234));
    }
    
    // Custom IStrategy-like methods with renamed parameters
    function deposit(uint256 amount) external pure returns (uint256 sharesAmt) {
        return amount;
    }
    
    function deposit(IERC20 token, uint256 amount) external pure returns (uint256) {
        return amount;
    }
    
    function withdraw(uint256 sharesAmt) external pure returns (uint256 assetsAmt) {
        return sharesAmt;
    }
    
    function withdraw(address recipient, IERC20 token, uint256 amountShares) external pure {
        // No-op for mock
    }
    
    function sharesToUnderlyingView(address account, uint256 sharesAmt) external pure returns (uint256 assetsAmt) {
        return sharesAmt;
    }
    
    function sharesToUnderlying(address account, uint256 sharesAmt) external pure returns (uint256) {
        return sharesAmt;
    }
    
    function underlyingToSharesView(uint256 assets) external pure returns (uint256 sharesAmt) {
        return assets;
    }
    
    function underlyingToShares(uint256 amount) external pure returns (uint256) {
        return amount;
    }
    
    function userUnderlyingView(address user) external pure returns (uint256) {
        return 0;
    }
    
    function userUnderlying(address user) external pure returns (uint256) {
        return 0;
    }
    
    function shares(address account) external pure returns (uint256) {
        return 0;
    }
    
    function userUnderlyingView(address user, IERC20 token) external pure returns (uint256) {
        return 0;
    }
    
    function totalShares() external pure returns (uint256) {
        return 0;
    }
    
    function underlyingToken() external view returns (IERC20) {
        return underlyingToken_;
    }
    
    function explanation() external pure returns (string memory) {
        return "Mock Strategy for testing";
    }
    
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}

/**
 * @title MockAVSRegistrar
 * @notice Mock implementation of IAVSRegistrar
 */
contract MockAVSRegistrar is IAVSRegistrar {
    function registerOperator(address operator, bytes calldata data) external {
        // No-op for mock
    }
    
    function deregisterOperator(address operator) external {
        // No-op for mock
    }
}

/**
 * @title MockAllocationManager
 * @notice Mock implementation of IAllocationManager for testing operator tables
 */
contract MockAllocationManager {
    // Map operator set key to a list of operators
    mapping(bytes32 => address[]) public operatorSetMembers;
    
    // Map operator + operator set key + strategy to stake amount
    mapping(address => mapping(bytes32 => mapping(IStrategy => uint256))) public operatorStakes;
    
    // Map operator + strategy to max magnitude
    mapping(address => mapping(IStrategy => uint64)) public operatorMaxMagnitudes;
    
    // Map AVS to registrar
    mapping(address => IAVSRegistrar) public avsRegistrars;
    
    // Custom structs to avoid importing from full interface
    struct AllocateParams {
        OperatorSet operatorSet;
        IStrategy strategy;
        uint64 magnitude;
    }
    
    struct RegisterParams {
        address avs;
        uint32[] operatorSetIds;
    }
    
    struct DeregisterParams {
        address avs;
        uint32[] operatorSetIds;
    }
    
    struct CreateSetParams {
        uint32 operatorSetId;
        IStrategy[] strategies;
    }
    
    struct Allocation {
        uint64 magnitude;
        uint64 rebalanceTimestamp;
        uint128 nextMagnitude;
    }
    
    /**
     * @notice Add an operator to an operator set
     */
    function addOperatorToSet(OperatorSet memory operatorSet, address operator) external {
        bytes32 key = keccak256(abi.encode(operatorSet.avs, operatorSet.id));
        operatorSetMembers[key].push(operator);
    }
    
    /**
     * @notice Set stake for an operator in an operator set for a strategy
     */
    function setOperatorStake(
        address operator, 
        OperatorSet memory operatorSet, 
        IStrategy strategy, 
        uint256 stake
    ) external {
        bytes32 key = keccak256(abi.encode(operatorSet.avs, operatorSet.id));
        operatorStakes[operator][key][strategy] = stake;
    }
    
    /**
     * @notice Set max magnitude for an operator's strategy
     */
    function setOperatorMaxMagnitude(
        address operator,
        IStrategy strategy,
        uint64 maxMagnitude
    ) external {
        operatorMaxMagnitudes[operator][strategy] = maxMagnitude;
    }
    
    /**
     * @notice Get members of an operator set
     */
    function getMembers(OperatorSet memory operatorSet) external view returns (address[] memory) {
        bytes32 key = keccak256(abi.encode(operatorSet.avs, operatorSet.id));
        return operatorSetMembers[key];
    }
    
    /**
     * @notice Get allocated stake for operators in an operator set
     */
    function getAllocatedStake(
        OperatorSet memory operatorSet,
        address[] memory operators,
        IStrategy[] memory strategies
    ) external view returns (uint256[][] memory allocatedStake) {
        bytes32 key = keccak256(abi.encode(operatorSet.avs, operatorSet.id));
        allocatedStake = new uint256[][](operators.length);
        
        for (uint256 i = 0; i < operators.length; i++) {
            allocatedStake[i] = new uint256[](strategies.length);
            for (uint256 j = 0; j < strategies.length; j++) {
                allocatedStake[i][j] = operatorStakes[operators[i]][key][strategies[j]];
            }
        }
        
        return allocatedStake;
    }
    
    /**
     * @notice Get max magnitudes for operator strategies
     */
    function getMaxMagnitudes(
        address operator,
        IStrategy[] calldata strategies
    ) external view returns (uint64[] memory) {
        uint64[] memory maxMagnitudes = new uint64[](strategies.length);
        
        for (uint256 i = 0; i < strategies.length; i++) {
            maxMagnitudes[i] = operatorMaxMagnitudes[operator][strategies[i]];
        }
        
        return maxMagnitudes;
    }
    
    /**
     * @notice Set AVS registrar
     */
    function setAVSRegistrarMock(address avs, IAVSRegistrar registrar) external {
        avsRegistrars[avs] = registrar;
    }
    
    /**
     * @notice Get AVS registrar
     */
    function getAVSRegistrarMock(address avs) external view returns (IAVSRegistrar) {
        return avsRegistrars[avs];
    }
    
    /**
     * @notice For mocking the IAllocationManager operations - these all do nothing and are just stubs
     */
    function initialize(address initialOwner, uint256 initialPausedStatus) external {}
    function slashOperator(address avs, bytes calldata params) external {}
    function modifyAllocations(address operator, AllocateParams[] calldata params) external {}
    function clearDeallocationQueue(address operator, IStrategy[] calldata strategies, uint16[] calldata numToClear) external {}
    function registerForOperatorSets(address operator, RegisterParams calldata params) external {}
    function deregisterFromOperatorSets(DeregisterParams calldata params) external {}
    function setAllocationDelay(address operator, uint32 delay) external {}
    function updateAVSMetadataURI(address avs, string calldata metadataURI) external {}
    function createOperatorSets(address avs, CreateSetParams[] calldata params) external {}
    function addStrategiesToOperatorSet(address avs, uint32 operatorSetId, IStrategy[] calldata strategies) external {}
    function removeStrategiesFromOperatorSet(address avs, uint32 operatorSetId, IStrategy[] calldata strategies) external {}
    
    // Simple view functions
    function getOperatorSetCount(address avs) external pure returns (uint256) { return 0; }
    function getAllocatedSets(address operator) external pure returns (OperatorSet[] memory) { return new OperatorSet[](0); }
    function getAllocatedStrategies(address operator, OperatorSet memory operatorSet) external pure returns (IStrategy[] memory) { return new IStrategy[](0); }
    function getAllocation(address operator, OperatorSet memory operatorSet, IStrategy strategy) external pure returns (Allocation memory) { return Allocation(0, 0, 0); }
    function getAllocations(address[] memory operators, OperatorSet memory operatorSet, IStrategy strategy) external pure returns (Allocation[] memory) { return new Allocation[](0); }
    function getStrategyAllocations(address operator, IStrategy strategy) external pure returns (OperatorSet[] memory, Allocation[] memory) { return (new OperatorSet[](0), new Allocation[](0)); }
    function getEncumberedMagnitude(address operator, IStrategy strategy) external pure returns (uint64) { return 0; }
    function getAllocatableMagnitude(address operator, IStrategy strategy) external pure returns (uint64) { return 0; }
    function getMaxMagnitude(address operator, IStrategy strategy) external view returns (uint64) { return operatorMaxMagnitudes[operator][strategy]; }
    function getMaxMagnitudes(address[] calldata operators, IStrategy strategy) external pure returns (uint64[] memory) { return new uint64[](0); }
    function getMaxMagnitudesAtBlock(address operator, IStrategy[] calldata strategies, uint32 blockNumber) external pure returns (uint64[] memory) { return new uint64[](0); }
    function getAllocationDelay(address operator) external pure returns (bool isSet, uint32 delay) { return (false, 0); }
    function getRegisteredSets(address operator) external pure returns (OperatorSet[] memory operatorSets) { return new OperatorSet[](0); }
    
    function isMemberOfOperatorSet(address operator, OperatorSet memory operatorSet) external view returns (bool) { 
        bytes32 key = keccak256(abi.encode(operatorSet.avs, operatorSet.id));
        address[] memory members = operatorSetMembers[key];
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i] == operator) {
                return true;
            }
        }
        return false;
    }
    
    function isOperatorSet(OperatorSet memory operatorSet) external view returns (bool) { 
        bytes32 key = keccak256(abi.encode(operatorSet.avs, operatorSet.id));
        return operatorSetMembers[key].length > 0;
    }
    
    function getMemberCount(OperatorSet memory operatorSet) external view returns (uint256) {
        bytes32 key = keccak256(abi.encode(operatorSet.avs, operatorSet.id));
        return operatorSetMembers[key].length;
    }
    
    function getStrategiesInOperatorSet(OperatorSet memory operatorSet) external pure returns (IStrategy[] memory strategies) { return new IStrategy[](0); }
    function getMinimumSlashableStake(OperatorSet memory operatorSet, address[] memory operators, IStrategy[] memory strategies, uint32 futureBlock) external pure returns (uint256[][] memory slashableStake) { return new uint256[][](0); }
    function isOperatorSlashable(address operator, OperatorSet memory operatorSet) external pure returns (bool) { return false; }
}

/**
 * @title MockECDSAOperatorRegistry
 * @notice Mock registry for operator ECDSA keys
 */
contract MockECDSAOperatorRegistry {
    mapping(address => uint256) public operatorPrivateKeys;
    
    function setOperatorPrivateKey(address operator, uint256 privateKey) external {
        operatorPrivateKeys[operator] = privateKey;
    }
    
    function getOperatorPrivateKey(address operator) external view returns (uint256) {
        return operatorPrivateKeys[operator];
    }
}

/**
 * @title MockBN254OperatorRegistry
 * @notice Mock registry for operator BN254 keys
 */
contract MockBN254OperatorRegistry {
    mapping(address => BN254.G1Point) public operatorPubkeys;
    
    function setOperatorPubkey(address operator, BN254.G1Point calldata pubkey) external {
        operatorPubkeys[operator] = pubkey;
    }
    
    function getOperatorPubkey(address operator) external view returns (BN254.G1Point memory) {
        return operatorPubkeys[operator];
    }
}