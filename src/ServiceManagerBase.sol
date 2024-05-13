// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
<<<<<<< HEAD
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
=======
>>>>>>> fixes(m2-mainnet): combined pr for all m2-mainnet fixs (#162)

import {ServiceManagerBaseStorage} from "./ServiceManagerBaseStorage.sol";
import {IServiceManager} from "./interfaces/IServiceManager.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {BitmapUtils} from "./libraries/BitmapUtils.sol";

/**
 * @title Minimal implementation of a ServiceManager-type contract.
 * This contract can be inherited from or simply used as a point-of-reference.
 * @author Layr Labs, Inc.
 */
<<<<<<< HEAD
abstract contract ServiceManagerBase is OwnableUpgradeable, ServiceManagerBaseStorage {
=======
abstract contract ServiceManagerBase is IServiceManager, OwnableUpgradeable {
>>>>>>> fixes(m2-mainnet): combined pr for all m2-mainnet fixs (#162)
    using BitmapUtils for *;

<<<<<<< HEAD
=======
    IRegistryCoordinator internal immutable _registryCoordinator;
    IStakeRegistry internal immutable _stakeRegistry;
    IAVSDirectory internal immutable _avsDirectory;

<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
    mapping(PubKey => ISignatureUtils.SignatureWithSaltAndExpiry) public signatureMap;

>>>>>>> Add a function to register operator with pubkey.
=======
>>>>>>> Add a function to register operator with pubkey.
=======
=======
    mapping(PubKey => ISignatureUtils.SignatureWithSaltAndExpiry) public signatureMap;

>>>>>>> 56e7e72 (Store the pubkeyG1 and G2 to ServiceManager instead of operatorId.)
>>>>>>> Store the pubkeyG1 and G2 to ServiceManager instead of operatorId.
=======
>>>>>>> Update eigenlayer-contract repo
=======
>>>>>>> Remove redundant variable
=======
    mapping(PubKey => ISignatureUtils.SignatureWithSaltAndExpiry) public signatureMap;

>>>>>>> Check and update BLS and ECDSA key whenever starting operator
=======
>>>>>>> Check and update BLS and ECDSA key whenever starting operator
    /// @notice when applied to a function, only allows the RegistryCoordinator to call it
    modifier onlyRegistryCoordinator() {
        require(
            msg.sender == address(_registryCoordinator),
            "ServiceManagerBase.onlyRegistryCoordinator: caller is not the registry coordinator"
        );
        _;
    }

    /// @notice only rewardsInitiator can call createAVSRewardsSubmission
    modifier onlyRewardsInitiator() {
        require(
            msg.sender == rewardsInitiator,
            "ServiceManagerBase.onlyRewardsInitiator: caller is not the rewards initiator"
        );
        _;
    }

    /// @notice Sets the (immutable) `_registryCoordinator` address
    constructor(
        IAVSDirectory __avsDirectory,
<<<<<<< HEAD
        IRewardsCoordinator __rewardsCoordinator,
        IRegistryCoordinator __registryCoordinator,
        IStakeRegistry __stakeRegistry
    )
        ServiceManagerBaseStorage(
            __avsDirectory,
            __rewardsCoordinator,
            __registryCoordinator,
            __stakeRegistry
        )
    {
        _disableInitializers();
    }

    function __ServiceManagerBase_init(
        address initialOwner,
        address _rewardsInitiator
    ) internal virtual onlyInitializing {
=======
        IRegistryCoordinator __registryCoordinator,
        IStakeRegistry __stakeRegistry
    ) {
        _avsDirectory = __avsDirectory;
        _registryCoordinator = __registryCoordinator;
        _stakeRegistry = __stakeRegistry;
        _disableInitializers();
    }

<<<<<<< HEAD
    function __ServiceManagerBase_init(address initialOwner) internal virtual onlyInitializing {
<<<<<<< HEAD
>>>>>>> fixes(m2-mainnet): combined pr for all m2-mainnet fixs (#162)
=======
>>>>>>> Check and update BLS and ECDSA key whenever starting operator
=======
    function __ServiceManagerBase_init(
        address initialOwner
    ) internal virtual onlyInitializing {
>>>>>>> Check and update BLS and ECDSA key whenever starting operator
        _transferOwnership(initialOwner);
        _setRewardsInitiator(_rewardsInitiator);
    }

    /**
     * @notice Updates the metadata URI for the AVS
     * @param _metadataURI is the metadata URI for the AVS
     * @dev only callable by the owner
     */
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
    function updateAVSMetadataURI(string memory _metadataURI) public virtual onlyOwner {
=======
    function updateAVSMetadataURI(
        string memory _metadataURI
    ) public virtual onlyOwner {
>>>>>>> Check and update BLS and ECDSA key whenever starting operator
        _avsDirectory.updateAVSMetadataURI(_metadataURI);
    }

    /**
     * @notice Creates a new rewards submission to the EigenLayer RewardsCoordinator contract, to be split amongst the
     * set of stakers delegated to operators who are registered to this `avs`
     * @param rewardsSubmissions The rewards submissions being created
     * @dev Only callabe by the permissioned rewardsInitiator address
     * @dev The duration of the `rewardsSubmission` cannot exceed `MAX_REWARDS_DURATION`
     * @dev The tokens are sent to the `RewardsCoordinator` contract
     * @dev Strategies must be in ascending order of addresses to check for duplicates
     * @dev This function will revert if the `rewardsSubmission` is malformed,
     * e.g. if the `strategies` and `weights` arrays are of non-equal lengths
     */
    function createAVSRewardsSubmission(IRewardsCoordinator.RewardsSubmission[] calldata rewardsSubmissions)
        public
        virtual
        onlyRewardsInitiator
    {
        for (uint256 i = 0; i < rewardsSubmissions.length; ++i) {
            // transfer token to ServiceManager and approve RewardsCoordinator to transfer again
            // in createAVSRewardsSubmission() call
            rewardsSubmissions[i].token.transferFrom(msg.sender, address(this), rewardsSubmissions[i].amount);
            uint256 allowance =
                rewardsSubmissions[i].token.allowance(address(this), address(_rewardsCoordinator));
            rewardsSubmissions[i].token.approve(
                address(_rewardsCoordinator), rewardsSubmissions[i].amount + allowance
            );
        }

        _rewardsCoordinator.createAVSRewardsSubmission(rewardsSubmissions);
=======
    function setMetadataURI(string memory _metadataURI) public virtual onlyOwner {
=======
    function updateAVSMetadataURI(string memory _metadataURI) public virtual onlyOwner {
>>>>>>> Fix metadata uri signature (#205)
=======
    function updateAVSMetadataURI(string memory _metadataURI) public virtual onlyOwner {
>>>>>>> Check and update BLS and ECDSA key whenever starting operator
        _avsDirectory.updateAVSMetadataURI(_metadataURI);
>>>>>>> fixes(m2-mainnet): combined pr for all m2-mainnet fixs (#162)
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
    function deregisterOperatorFromAVS(
        address operator
    ) public virtual onlyRegistryCoordinator {
        _avsDirectory.deregisterOperatorFromAVS(operator);
<<<<<<< HEAD
    }

    /**
     * @notice Sets the rewards initiator address
     * @param newRewardsInitiator The new rewards initiator address
     * @dev only callable by the owner
     */
    function setRewardsInitiator(address newRewardsInitiator) external onlyOwner {
        _setRewardsInitiator(newRewardsInitiator);
    }

    function _setRewardsInitiator(address newRewardsInitiator) internal {
        emit RewardsInitiatorUpdated(rewardsInitiator, newRewardsInitiator);
        rewardsInitiator = newRewardsInitiator;
=======
>>>>>>> fixes(m2-mainnet): combined pr for all m2-mainnet fixs (#162)
    }

    /**
     * @notice Returns the list of strategies that the AVS supports for restaking
     * @dev This function is intended to be called off-chain
     * @dev No guarantee is made on uniqueness of each element in the returned array.
     *      The off-chain service should do that validation separately
     */
    function getRestakeableStrategies()
        external
        view
        returns (address[] memory)
    {
        uint256 quorumCount = _registryCoordinator.quorumCount();

        if (quorumCount == 0) {
            return new address[](0);
        }

        uint256 strategyCount;
        for (uint256 i = 0; i < quorumCount; i++) {
            strategyCount += _stakeRegistry.strategyParamsLength(uint8(i));
        }

        address[] memory restakedStrategies = new address[](strategyCount);
        uint256 index = 0;
<<<<<<< HEAD
<<<<<<< HEAD
        for (uint256 i = 0; i < _registryCoordinator.quorumCount(); i++) {
            uint256 strategyParamsLength = _stakeRegistry.strategyParamsLength(uint8(i));
            for (uint256 j = 0; j < strategyParamsLength; j++) {
                restakedStrategies[index] =
                    address(_stakeRegistry.strategyParamsByIndex(uint8(i), j).strategy);
=======
        for(uint256 i = 0; i < _registryCoordinator.quorumCount(); i++) {
            uint256 strategyParamsLength = _stakeRegistry.strategyParamsLength(uint8(i));
            for (uint256 j = 0; j < strategyParamsLength; j++) {
                restakedStrategies[index] = address(_stakeRegistry.strategyParamsByIndex(uint8(i), j).strategy);
>>>>>>> Check and update BLS and ECDSA key whenever starting operator
=======
        for (uint256 i = 0; i < _registryCoordinator.quorumCount(); i++) {
            uint256 strategyParamsLength = _stakeRegistry.strategyParamsLength(
                uint8(i)
            );
            for (uint256 j = 0; j < strategyParamsLength; j++) {
                restakedStrategies[index] = address(
                    _stakeRegistry.strategyParamsByIndex(uint8(i), j).strategy
                );
>>>>>>> Check and update BLS and ECDSA key whenever starting operator
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
<<<<<<< HEAD
<<<<<<< HEAD
    function getOperatorRestakedStrategies(address operator)
        external
        view
        returns (address[] memory)
    {
=======
    function getOperatorRestakedStrategies(address operator) external view returns (address[] memory) {
>>>>>>> Check and update BLS and ECDSA key whenever starting operator
=======
    function getOperatorRestakedStrategies(
        address operator
    ) external view returns (address[] memory) {
>>>>>>> Check and update BLS and ECDSA key whenever starting operator
        bytes32 operatorId = _registryCoordinator.getOperatorId(operator);
        uint192 operatorBitmap = _registryCoordinator.getCurrentQuorumBitmap(
            operatorId
        );

        if (operatorBitmap == 0 || _registryCoordinator.quorumCount() == 0) {
            return new address[](0);
        }

        // Get number of strategies for each quorum in operator bitmap
        bytes memory operatorRestakedQuorums = BitmapUtils.bitmapToBytesArray(
            operatorBitmap
        );
        uint256 strategyCount;
<<<<<<< HEAD
<<<<<<< HEAD
        for (uint256 i = 0; i < operatorRestakedQuorums.length; i++) {
=======
        for(uint256 i = 0; i < operatorRestakedQuorums.length; i++) {
>>>>>>> Check and update BLS and ECDSA key whenever starting operator
            strategyCount += _stakeRegistry.strategyParamsLength(uint8(operatorRestakedQuorums[i]));
=======
        for (uint256 i = 0; i < operatorRestakedQuorums.length; i++) {
            strategyCount += _stakeRegistry.strategyParamsLength(
                uint8(operatorRestakedQuorums[i])
            );
>>>>>>> Check and update BLS and ECDSA key whenever starting operator
        }

        // Get strategies for each quorum in operator bitmap
        address[] memory restakedStrategies = new address[](strategyCount);
        uint256 index = 0;
        for (uint256 i = 0; i < operatorRestakedQuorums.length; i++) {
            uint8 quorum = uint8(operatorRestakedQuorums[i]);
            uint256 strategyParamsLength = _stakeRegistry.strategyParamsLength(
                quorum
            );
            for (uint256 j = 0; j < strategyParamsLength; j++) {
<<<<<<< HEAD
<<<<<<< HEAD
                restakedStrategies[index] =
                    address(_stakeRegistry.strategyParamsByIndex(quorum, j).strategy);
=======
                restakedStrategies[index] = address(_stakeRegistry.strategyParamsByIndex(quorum, j).strategy);
>>>>>>> Check and update BLS and ECDSA key whenever starting operator
=======
                restakedStrategies[index] = address(
                    _stakeRegistry.strategyParamsByIndex(quorum, j).strategy
                );
>>>>>>> Check and update BLS and ECDSA key whenever starting operator
                index++;
            }
        }
        return restakedStrategies;
    }

    /// @notice Returns the EigenLayer AVSDirectory contract.
    function avsDirectory() external view override returns (address) {
        return address(_avsDirectory);
    }

    /// @notice Returns the EigenLayer AVSDirectory contract.
    function avsDirectory() external view override returns (address) {
        return address(_avsDirectory);
    }
    
    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[50] private __GAP;
}
