// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

abstract contract SimpleLinearWeightQuorum is OwnableUpgradeable {
    
    /// @notice Constant used as a divisor in calculating weights.
    uint256 public constant WEIGHTING_DIVISOR = 1e18;
    /// @notice Maximum length of dynamic arrays in the `quorum`.
    uint8 public constant MAX_WEIGHING_FUNCTION_LENGTH = 32;

    /// @notice The address of the Delegation contract for EigenLayer.
    IDelegationManager public immutable delegation;

    /**
     * @notice In weighing a particular strategy, the amount of delegated shares for that strategy is
     * multiplied by its weight, then divided by WEIGHTING_DIVISOR
     */
    struct Quorum {
        IStrategy[] strategies;
        uint256[] weights;
    }

    // @notice list of strategies considered and their corresponding weights for this AVS     
    Quorum internal _quorum;

    /// @notice list of strategies considered and their corresponding weights for this AVS  
    /// @dev this getter function is necessary since Solidity will not create a built-in getter for the Quorum struct    
    function quorum() public view virtual returns (Quorum memory) {
        return _quorum;
    }

    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[49] private __GAP;

    constructor(
        IDelegationManager _delegationManager
    ) {
        delegation = _delegationManager;
    }

    event QuorumConfigUpdated(Quorum);

    /*******************************************************************************
                    EXTERNAL FUNCTIONS -- permissioned
    *******************************************************************************/
    /** 
     * @notice Adds strategies and weights
     * @dev Checks against duplicate strategies by ensuring that strategies are ordered in ascending address order
     * @dev This function has no check to make sure that the strategies for a single quorum have the same underlying asset.
     * This is a conscious choice, since an AVS may want, e.g., a stablecoin quorum that accepts USDC, USDT, DAI, etc. as
     * underlying assets and treats them as "equivalent".
     * @dev Will revert if the quorum exceeds max length or does not have consistent length arrays
     */
    function setQuorumConfig(
        Quorum memory newQuorumConfig
    ) onlyOwner public virtual {
        // sanitize inputs
        require(newQuorumConfig.strategies.length == newQuorumConfig.weights.length,
            "setQuorumConfig: array lengths must match");
        require(newQuorumConfig.strategies.length <= MAX_WEIGHING_FUNCTION_LENGTH,
            "setQuorumConfig: array length exceeds max");
        address lastStrategy = address(0);
        for (uint256 i = 0; i < newQuorumConfig.strategies.length; ++i) {
            require(address(newQuorumConfig.strategies[i]) > lastStrategy,
            "setQuorumConfig: strategy array must be in ascending order");
            lastStrategy = address(newQuorumConfig.strategies[i]);
        }

        // update the storage and emit event
        delete _quorum;
        _quorum = newQuorumConfig;
        emit QuorumConfigUpdated(newQuorumConfig);
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
        uint256 stratsLength = quorumLength();

        // TODO: update to use new DelegationManager method which queries + returns an array
        for (uint256 i = 0; i < stratsLength; i++) {
            // shares of the operator in the i-th strategy
            uint256 sharesAmount = delegation.operatorShares(operator, _quorum.strategies[i]);

            // add the weight from the shares for this strategy to the total weight
            if (sharesAmount > 0) {
                weight += (sharesAmount * _quorum.weights[i]) / WEIGHTING_DIVISOR;
            }
        }
        return weight;
    }

    /// @notice Returns the length of the dynamic arrays stored in `quorum`.
    function quorumLength() public view returns (uint256) {
        return _quorum.strategies.length;
    }

    /// @notice Returns the `index`'th strategy in `quorum`
    function strategyByIndex(
        uint256 index
    ) public view returns (IStrategy)
    {
        return _quorum.strategies[index];
    }

    /// @notice Returns the `index`'th weight in `quorum`
    function weightByIndex(
        uint256 index
    ) public view returns (uint256)
    {
        return _quorum.weights[index];
    }
}
