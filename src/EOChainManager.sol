// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import { OwnableUpgradeable } from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin-upgrades/contracts/access/AccessControlUpgradeable.sol";
import { IEOChainManager} from "./interfaces/IEOChainManager.sol";

/// @title EOChainManager
/// @notice Contract for managing the integration with the EOracle chain.
///         This contract is used to de/register validators and update their stake weights.
///         It is called by the registry coordinator contract
/// @dev In this perliminary version, the contract only checks if the operator is whitelisted. The actual integration
///         with the EOracle chain will be implemented in the future.
/// @dev Inherits IEOChainManager, Ownable2StepUpgradeable, and AccessControlUpgradeable for access control functionalities
contract EOChainManager is IEOChainManager, OwnableUpgradeable, AccessControlUpgradeable {
    /*******************************************************************************
                               CONSTANTS AND IMMUTABLES 
    *******************************************************************************/

    /// @notice Public constants for the roles
    bytes32 public constant CHAIN_VALIDATOR_ROLE = keccak256("CHAIN_VALIDATOR");
    bytes32 public constant DATA_VALIDATOR_ROLE = keccak256("DATA_VALIDATOR");
    
    /*******************************************************************************
                                       STATE 
    *******************************************************************************/
    
    // @notice The address of eoracle middleware RegistryCoordinator
    address public registryCoordinator; 

    /// @dev Modifier for registry coordinator
    modifier onlyRegistryCoordinator() {
        require(msg.sender == address(registryCoordinator), "NotRegistryCoordinator");
        _;
    }

    /// @dev Initializes the contract by setting up roles and ownership
    function initialize() public initializer {
        __AccessControl_init();
        __Ownable_init();

        // Grant the owner the default admin role enabling him to grant and revoke roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @dev Sets the registry coordinator which will be the only contract allowed to call the register functions
    function setRegistryCoordinator(
        address _registryCoordinator
    ) external onlyOwner {
        registryCoordinator = _registryCoordinator;
    }

    /*******************************************************************************
                      EXTERNAL FUNCTIONS - IEOChainManager
    *******************************************************************************/

    /// @inheritdoc IEOChainManager
    /// @dev for now there is no state change so the function is view
    function registerDataValidator(
        address operator,
        uint96[] calldata /* stakes */
    ) external view onlyRegistryCoordinator {
        require(hasRole(DATA_VALIDATOR_ROLE, operator), "NotWhitelisted");
        // For now just whitelisting. EO chain integration to come.
    }

    /// @inheritdoc IEOChainManager
    /// @dev for now there is no state change so the function is view
    function registerChainValidator(
        address operator,
        uint96[] calldata /* stakes */,
        uint256[2] calldata /* signature */,
        uint256[4] calldata /* pubkey */
    ) external view onlyRegistryCoordinator {
        require(hasRole(CHAIN_VALIDATOR_ROLE, operator), "NotWhitelisted");
        // For now just whitelisting. EO chain integration to come.
    }

    /// @inheritdoc IEOChainManager
    /// @dev for now there is no state change so the function is view
    function deregisterValidator(
        address operator
    ) external view onlyRegistryCoordinator {
        // For now just whitelisting. EO chain integration to come.
    }

    /// @inheritdoc IEOChainManager
    /// @dev for now there is no state change so the function is view
    function updateOperator(
        address operator,
        uint96[] calldata newStakeWeights
    ) external view onlyRegistryCoordinator {
        // For now just whitelisting. EO chain integration to come.
    }

    // Placeholder for upgradeable contracts
    uint256[50] private __gap;
}
