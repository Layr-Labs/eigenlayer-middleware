// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ISlashEscrowFactory} from "eigenlayer-contracts/src/contracts/interfaces/ISlashEscrowFactory.sol";
import {ISlashEscrow} from "eigenlayer-contracts/src/contracts/interfaces/ISlashEscrow.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

contract SlashEscrowFactoryMock is ISlashEscrowFactory {
    mapping(bytes32 => address) public slashEscrows;

    function initiateSlashEscrow(
        OperatorSet calldata operatorSet,
        uint256 slashId,
        IStrategy strategy
    ) external {
        bytes32 key = keccak256(abi.encode(operatorSet, slashId));
        if (slashEscrows[key] == address(0)) {
            slashEscrows[key] = address(new MockSlashEscrow());
        }
    }

    function getSlashEscrow(
        OperatorSet calldata operatorSet,
        uint256 slashId
    ) external view returns (ISlashEscrow) {
        bytes32 key = keccak256(abi.encode(operatorSet, slashId));
        return ISlashEscrow(slashEscrows[key]);
    }

    function clearSlashEscrow(OperatorSet calldata operatorSet, uint256 slashId) external {}

    function redistributeByStrategy(
        OperatorSet calldata operatorSet,
        uint256 slashId,
        IStrategy strategy
    ) external {}

    function processRedistribution(
        OperatorSet calldata operatorSet,
        uint256 slashId,
        IStrategy[] calldata strategies,
        address[] calldata operators
    ) external {}

    function initializeParams(
        address _strategyManager,
        uint256 _escrowDelay
    ) external {}

    function escrowDelay() external pure returns (uint256) {
        return 7 days;
    }

    function strategyManager() external view returns (address) {
        return address(0);
    }

    /**
     * @notice Returns the version of the contract
     * @return The version string
     */
    function version() external pure returns (string memory) {
        return "v0.0.1";
    }
    
    // Additional functions to satisfy interface - minimal implementations
    function initialize(address initialOwner, uint256 initialPausedStatus, uint32 initialGlobalDelayBlocks) external {}
    function pauseEscrow(OperatorSet calldata operatorSet, uint256 slashId) external {}
    function unpauseEscrow(OperatorSet calldata operatorSet, uint256 slashId) external {}
    function releaseSlashEscrow(OperatorSet calldata operatorSet, uint256 slashId) external {}
    function releaseSlashEscrowByStrategy(OperatorSet calldata operatorSet, uint256 slashId, IStrategy strategy) external {}
    function setStrategyEscrowDelay(IStrategy strategy, uint32 delay) external {}
    function setGlobalEscrowDelay(uint32 delay) external {}
    
    function getPendingOperatorSets() external view returns (OperatorSet[] memory) { return new OperatorSet[](0); }
    function getTotalPendingOperatorSets() external view returns (uint256) { return 0; }
    function isPendingOperatorSet(OperatorSet calldata operatorSet) external view returns (bool) { return false; }
    function getPendingSlashIds(OperatorSet calldata operatorSet) external view returns (uint256[] memory) { return new uint256[](0); }
    function getPendingEscrows() external view returns (OperatorSet[] memory, bool[] memory, uint256[][] memory, uint32[][] memory) { 
        return (new OperatorSet[](0), new bool[](0), new uint256[][](0), new uint32[][](0)); 
    }
    function getTotalPendingSlashIds(OperatorSet calldata operatorSet) external view returns (uint256) { return 0; }
    function isPendingSlashId(OperatorSet calldata operatorSet, uint256 slashId) external view returns (bool) { return false; }
    function getPendingStrategiesForSlashId(OperatorSet calldata operatorSet, uint256 slashId) external view returns (IStrategy[] memory) { return new IStrategy[](0); }
    function getPendingStrategiesForSlashIds(OperatorSet calldata operatorSet) external view returns (IStrategy[][] memory) { return new IStrategy[][](0); }
    function getTotalPendingStrategiesForSlashId(OperatorSet calldata operatorSet, uint256 slashId) external view returns (uint256) { return 0; }
    function getPendingUnderlyingAmountForStrategy(OperatorSet calldata operatorSet, uint256 slashId, IStrategy strategy) external view returns (uint256) { return 0; }
    function isEscrowPaused(OperatorSet calldata operatorSet, uint256 slashId) external view returns (bool) { return false; }
    function getEscrowStartBlock(OperatorSet calldata operatorSet, uint256 slashId) external view returns (uint256) { return 0; }
    function getEscrowCompleteBlock(OperatorSet calldata operatorSet, uint256 slashId) external view returns (uint32) { return 0; }
    function getStrategyEscrowDelay(IStrategy strategy) external view returns (uint32) { return 0; }
    function getGlobalEscrowDelay() external view returns (uint32) { return 0; }
    function computeSlashEscrowSalt(OperatorSet calldata operatorSet, uint256 slashId) external pure returns (bytes32) { return bytes32(0); }
    function isDeployedSlashEscrow(OperatorSet calldata operatorSet, uint256 slashId) external view returns (bool) { return false; }
    function isDeployedSlashEscrow(ISlashEscrow slashEscrow) external view returns (bool) { return false; }
}

contract MockSlashEscrow {
    receive() external payable {}
    
    function releaseTokens(
        address token,
        uint256 amount,
        address recipient
    ) external {}
    
    function verifyDeploymentParameters(
        OperatorSet calldata operatorSet,
        uint256 slashId
    ) external view returns (bool) {
        return true;
    }
} 