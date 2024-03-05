// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import {BitmapUtils} from "./libraries/BitmapUtils.sol"; 
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";

import {IServiceManager} from "./interfaces/IServiceManager.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";

/**
 * @title Minimal implementation of a ServiceManager-type contract.
 * This contract can be inherited from or simply used as a point-of-reference.
 * @author Layr Labs, Inc.
 */
abstract contract ServiceManagerBase is IServiceManager, OwnableUpgradeable {
    using BitmapUtils for *;

    IRegistryCoordinator internal immutable _registryCoordinator;
    IStakeRegistry internal immutable _stakeRegistry;
    IIndexRegistry internal immutable _indexRegistry;
    IBLSApkRegistry internal immutable _blsApkRegistry;
    IAVSDirectory internal immutable _avsDirectory;

    IClaimingManager internal immutable claimingManager;

    /// @notice when applied to a function, only allows the RegistryCoordinator to call it
    modifier onlyRegistryCoordinator() {
        require(
            msg.sender == address(_registryCoordinator),
            "ServiceManagerBase.onlyRegistryCoordinator: caller is not the registry coordinator"
        );
        _;
    }

    /// @notice Sets the (immutable) `_registryCoordinator` address
    constructor(
        IAVSDirectory __avsDirectory,
        IRegistryCoordinator __registryCoordinator,
        IStakeRegistry __stakeRegistry
    ) {
        _avsDirectory = __avsDirectory;
        _registryCoordinator = __registryCoordinator;
        _stakeRegistry = __stakeRegistry;
        _disableInitializers();
    }

    function __ServiceManagerBase_init(address initialOwner) internal virtual onlyInitializing {
        _transferOwnership(initialOwner);
    }

    /**
     * @notice Sets the metadata URI for the AVS
     * @param _metadataURI is the metadata URI for the AVS
     * @dev only callable by the owner
     */
    function setMetadataURI(string memory _metadataURI) public virtual onlyOwner {
        _avsDirectory.updateAVSMetadataURI(_metadataURI);
    }

    /**
     * @notice Forwards a call to EigenLayer's AVSDirectory contract to confirm operator registration with the AVS
     * @param operator The address of the operator to register.
     * @param operatorSignature The signature, salt, and expiry of the operator's signature.
     */
    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) public virtual onlyRegistryCoordinator {
        _avsDirectory.registerOperatorToAVS(operator, operatorSignature);
    }

    /**
     * @notice Forwards a call to EigenLayer's AVSDirectory contract to confirm operator deregistration from the AVS
     * @param operator The address of the operator to deregister.
     */
    function deregisterOperatorFromAVS(address operator) public virtual onlyRegistryCoordinator {
        _avsDirectory.deregisterOperatorFromAVS(operator);
    }

    enum Payee {
        INVALID,
        REGISTERED_OPERATORS,
        FROM_CALLBACK,
        ALL_OPERATORS
    }

    struct Range {
        uint startTime;
        uint numDays;
    }

    struct Payment {
        IERC20 token;
        uint amount;
    }

    struct Weight {
        IStrategy strategy;
        uint96 multiplier;
    }

    struct PaymentRequest {
        Payee payee;
        Range range;
        Payment payment;
        StrategyParams[] weights;
    }

    /**
     * Submit a payment to be processed by the core claimingManager. 
     *
     * Payments are made out to any operator registered for this AVS holding shares
     * in any of the restakable strategies accepted by `quorum`.
     *
     * @param quorum Used to pull strategies/multipliers to weigh payment amounts
     * @param payFrom The address from which the tokens will be transferred
     * @param range The startTime and numDays
     */
    function payRegisteredOperators(
        uint8 quorum,
        address payFrom,
        IClaimingManager.Range memory range,
        IClaimingManager.Payment memory payment
    ) public onlyOwner {
        StrategyParams[] memory strategyParams = _stakeRegistry.getStrategyParams(quorum);
        require(strategyParams.length != 0, "invalid quorum selected");

        require(payment.token.transferFrom({
            from: payFrom,
            to: address(claimingManager),
            amount: payment.amount
        }), "token transfer failed");

        /// Send payment request to offchain service
        claimingManager.payForRange(IClaimingManager.PaymentRequest({
            payee: IClaimingManager.Payee.REGISTERED_OPERATORS,
            timeRange: range,
            payment: payment,
            weights: strategyParams
        }));
    }

    /**
     * Submit a payment to be processed by the core claimingManager.
     * 
     * Payments are made out to operators registered to a specific quorum at block numbers
     * determined by our offchain infra that span the date range given by `range`
     *
     * Our offchain infra can get these weighted operator sets by calling the
     * `getWeightedOperatorSet` method below and passing in the `callbackData`
     * supplied with the request
     */
    function payQuorumOperators(
        uint8 quorum,
        address payFrom,
        IClaimingManager.Range memory range,
        IClaimingManager.Payment memory payment
    ) public onlyOwner {
        require(payment.paymentToken.transferFrom({
            from: payFrom,
            to: address(claimingManager),
            amount: payment.paymentAmount
        }), "token transfer failed");

        /// Sends payment request to offchain service
        claimingManager.payForRange(IClaimingManager.PaymentRequest({
            payee: IClaimingManager.Payee.FROM_CALLBACK,
            callbackData: abi.encode(quorum),
            timeRange: range,
            payment: payment
        }));
    }

    interface IPayeeQuery {
        function getWeightedOperatorSet(bytes memory query) public view returns (address[] memory, uint96[] memory);
    }

    /// Callback used by offchain code to retrieve weighted operator set at a specific block number
    function getWeightedOperatorSet(uint blockNumber, bytes memory data) public view returns (address[] memory, uint96[] memory) {
        uint8 quorum = abi.decode(data, (uint8));

        bytes32[] memory operatorIds = _indexRegistry.getOperatorListAtBlockNumber(quorum, blockNumber);

        address[] memory operators = new address[](operatorIds.length);
        uint96[] memory weights = new uint96[](operatorIds.length);

        for (uint i = 0; i < operators.length; i++) {
            operators[i] = _blsApkRegistry.getOperatorFromPubkeyHash(operatorsIds[i]);
            weights[i] = _stakeRegistry.getStakeAtBlockNumber({
                operatorId: operatorIds[i],
                quorumNumber: quorum,
                blockNumber: blockNumber
            });
        }

        return (operators, weights);
    }

    /**
     * @notice Returns the list of strategies that the AVS supports for restaking
     * @dev This function is intended to be called off-chain
     * @dev No guarantee is made on uniqueness of each element in the returned array. 
     *      The off-chain service should do that validation separately
     */
    function getRestakeableStrategies() external view returns (address[] memory) {
        uint256 quorumCount = _registryCoordinator.quorumCount();

        if (quorumCount == 0) {
            return new address[](0);
        }
        
        uint256 strategyCount;
        for(uint256 i = 0; i < quorumCount; i++) {
            strategyCount += _stakeRegistry.strategyParamsLength(uint8(i));
        }

        address[] memory restakedStrategies = new address[](strategyCount);
        uint256 index = 0;
        for(uint256 i = 0; i < _registryCoordinator.quorumCount(); i++) {
            uint256 strategyParamsLength = _stakeRegistry.strategyParamsLength(uint8(i));
            for (uint256 j = 0; j < strategyParamsLength; j++) {
                restakedStrategies[index] = address(_stakeRegistry.strategyParamsByIndex(uint8(i), j).strategy);
                index++;
            }
        }
        return restakedStrategies;
    }

    /**
     * @notice Returns the list of strategies that the operator has potentially restaked on the AVS
     * @param operator The address of the operator to get restaked strategies for
     * @dev This function is intended to be called off-chain
     * @dev No guarantee is made on whether the operator has shares for a strategy in a quorum or uniqueness 
     *      of each element in the returned array. The off-chain service should do that validation separately
     */
    function getOperatorRestakedStrategies(address operator) external view returns (address[] memory) {
        bytes32 operatorId = _registryCoordinator.getOperatorId(operator);
        uint192 operatorBitmap = _registryCoordinator.getCurrentQuorumBitmap(operatorId);

        if (operatorBitmap == 0 || _registryCoordinator.quorumCount() == 0) {
            return new address[](0);
        }

        // Get number of strategies for each quorum in operator bitmap
        bytes memory operatorRestakedQuorums = BitmapUtils.bitmapToBytesArray(operatorBitmap);
        uint256 strategyCount;
        for(uint256 i = 0; i < operatorRestakedQuorums.length; i++) {
            strategyCount += _stakeRegistry.strategyParamsLength(uint8(operatorRestakedQuorums[i]));
        }

        // Get strategies for each quorum in operator bitmap
        address[] memory restakedStrategies = new address[](strategyCount);
        uint256 index = 0;
        for(uint256 i = 0; i < operatorRestakedQuorums.length; i++) {
            uint8 quorum = uint8(operatorRestakedQuorums[i]);
            uint256 strategyParamsLength = _stakeRegistry.strategyParamsLength(quorum);
            for (uint256 j = 0; j < strategyParamsLength; j++) {
                restakedStrategies[index] = address(_stakeRegistry.strategyParamsByIndex(quorum, j).strategy);
                index++;
            }
        }
        return restakedStrategies;        
    }

    /// @notice Returns the EigenLayer AVSDirectory contract.
    function avsDirectory() external view override returns (address) {
        return address(_avsDirectory);
    }
    
    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[50] private __GAP;
}
