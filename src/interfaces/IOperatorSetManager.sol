// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";


interface IOperatorSetManager is ISignatureUtils {


    /*******************************************************************************
                            OperatorSetManager Interface
    *******************************************************************************/

    /// STRUCTS

    struct OperatorSet {
        address avs;
        uint32 id;
    }
    
    /**
     * @notice this struct is used by allocators in order to specify whether they want to register for particular operator sets
     * @param operatorSet the operator set to change registration parameters for
     * @param allowedToRegister whether or not the AVS is allowed to add them to the given operator set if they are not registered for it
     */
    struct RegistrationParam {
        OperatorSet operatorSet;
        bool allowedToRegister;
    }
    
    /**
     * @notice this struct is used in SlashingMagnitudeParam in order to specify an operator's slashability for a certain operator set
     * @param operatorSet the operator set to change slashing parameters for
     * @param slashableMagnitude the proportional parts of the totalMagnitude that the operator set is getting. This ultimately determines how much slashable stake is delegated to a given AVS. (slashableMagnitude / totalMagnitude) of an operator's delegated stake.
     */
    struct OperatorSetSlashingParam {
        OperatorSet operatorSet;
        uint64 slashableMagnitude; 
    }

    /**
     * @notice A structure defining a set of operator-based slashing configurations to manage slashable stake
     * @param strategy each slashable stake is defined within a single strategy
     * @param totalMagnitude a virtual "denominator" magnitude from which to base portions of slashable stake to AVSs.
     * @param operatorSetSlashingParams the fine grained parameters deiniting the AVSs ability to slash and register the operator for the operator set
     */
    struct SlashingMagnitudeParam {
        IStrategy strategy;
        uint64 totalMagnitude;
        OperatorSetSlashingParam[] operatorSetSlashingParams; 
    }

    /// EVENTS
    
    event RegistrationParamsUpdated(
        address operator, OperatorSet operatorSet, bool allowedToRegister
    );

    event SlashableMagnitudeUpdated(
        address operator, IStrategy strategy, OperatorSet operatorSet, uint64 slashableMagnitude, uint32 effectEpoch
    );

    event TotalMagnitudeUpdated(
        address operator, IStrategy strategy, uint64 totalMagnitude, uint32 effectEpoch
    );

    /// EXTERNAL - STATE MODIFYING
    
    /**
	 * @notice Called by AVSs to add an operator to an operator set
	 * 
	 * @param operator the address of the operator to be added to the operator set
	 * @param operatorSetIDs the IDs of the operator sets
	 * @param signature the signature of the operator on their intent to register
	 * @dev msg.sender is used as the AVS
	 * @dev operator must not have a pending a deregistration from the operator sets
	 * @dev if this is the first operator set in the AVS that the operator is 
	 * registering for, a OperatorAVSRegistrationStatusUpdated event is emitted with 
	 * a REGISTERED status
	 */
	function registerOperatorToOperatorSets(
		address operator,
		uint32[] calldata operatorSetIDs,
		ISignatureUtils.SignatureWithSaltAndExpiry memory signature
	) external;

    /**
	 * @notice Called by AVSs or operators to remove an operator to from operator set
	 * 
	 * @param operator the address of the operator to be removed from the 
	 * operator set
	 * @param operatorSetIDs the ID of the operator set
	 * 
	 * @dev msg.sender is used as the AVS
	 * @dev operator must be registered for msg.sender AVS and the given 
	 * operator set
         * @dev if this removes operator from all operator sets for the msg.sender AVS
         * then an OperatorAVSRegistrationStatusUpdated event is emitted with a DEREGISTERED
         * status
	 */
	function deregisterOperatorFromOperatorSets(
		address operator, 
		uint32[] calldata operatorSetIDs
	) external;

    /**	
 	 * @notice Called by AVSs to add a strategy to its operator set
	 * 
	 * @param operatorSetID the ID of the operator set
	 * @param strategies the list strategies of the operator set to add
	 *
	 * @dev msg.sender is used as the AVS
	 * @dev no storage is updated as the event is used by off-chain services
	 */
	function addStrategiesToOperatorSet(
		uint32 operatorSetID,
		IStrategy[] calldata strategies
	) external;

    /**	
 	 * @notice Called by AVSs to remove a strategy to its operator set
	 * 
	 * @param operatorSetID the ID of the operator set
	 * @param strategies the list strategie of the operator set to remove
	 *
	 * @dev msg.sender is used as the AVS
	 * @dev no storage is updated as the event is used by off-chain services
	 */
	function removeStrategiesFromOperatorSet(
		uint32 operatorSetID,
		IStrategy[] calldata strategies
	) external;

    /// VIEW
    
    /**
     * @param operator the operator to get allowedToRegister for
     * @param operatorSet the operator set to get allowedToRegister for
     *
     * @return allowedToRegister whether or not operatorSet.avs is allowed to 
     * add them to the given operator set if they are not registered for it
     */
    function getAllowedToRegister(
        address operator,
        OperatorSet calldata operatorSet
    ) external returns (bool allowedToRegister);

    /**
     * @param operator the operator to get the slashable bips for
     * @param operatorSet the operator set to get the slashable bips for
     * @param strategy the strategy to get the slashable bips for
     * @param epoch the epoch to get the slashable bips for for
     *
     * @return slashableBips the slashable bips of the given strategy owned by
     * the given OperatorSet for the given operator and epoch
     */
    function getSlashableBips(
        address operator,
        OperatorSet calldata operatorSet,
        IStrategy strategy,
        uint32 epoch
    ) external returns (uint16 slashableBips);

    
    /*******************************************************************************
                            AVSDirectory Interface
    *******************************************************************************/



    /// @notice Enum representing the status of an operator's registration with an AVS
    enum OperatorAVSRegistrationStatus {
        UNREGISTERED,       // Operator not registered to AVS
        REGISTERED          // Operator registered to AVS
    }

    /**
     * @notice Emitted when @param avs indicates that they are updating their MetadataURI string
     * @dev Note that these strings are *never stored in storage* and are instead purely emitted in events for off-chain indexing
     */
    event AVSMetadataURIUpdated(address indexed avs, string metadataURI);

    /// @notice Emitted when an operator's registration status for an AVS is updated
    event OperatorAVSRegistrationStatusUpdated(address indexed operator, address indexed avs, OperatorAVSRegistrationStatus status);

    /**
     * @notice Called by an avs to register an operator with the avs.
     * @param operator The address of the operator to register.
     * @param operatorSignature The signature, salt, and expiry of the operator's signature.
     */
    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external;

    /**
     * @notice Called by an avs to deregister an operator with the avs.
     * @param operator The address of the operator to deregister.
     */
    function deregisterOperatorFromAVS(address operator) external;

    /**
     * @notice Called by an AVS to emit an `AVSMetadataURIUpdated` event indicating the information has updated.
     * @param metadataURI The URI for metadata associated with an AVS
     * @dev Note that the `metadataURI` is *never stored * and is only emitted in the `AVSMetadataURIUpdated` event
     */
    function updateAVSMetadataURI(string calldata metadataURI) external;

    /**
     * @notice Returns whether or not the salt has already been used by the operator.
     * @dev Salts is used in the `registerOperatorToAVS` function.
     */
    function operatorSaltIsSpent(address operator, bytes32 salt) external view returns (bool);

    /**
     * @notice Calculates the digest hash to be signed by an operator to register with an AVS
     * @param operator The account registering as an operator
     * @param avs The AVS the operator is registering to
     * @param salt A unique and single use value associated with the approver signature.
     * @param expiry Time after which the approver's signature becomes invalid
     */
    function calculateOperatorAVSRegistrationDigestHash(
        address operator,
        address avs,
        bytes32 salt,
        uint256 expiry
    ) external view returns (bytes32);

    /// @notice The EIP-712 typehash for the Registration struct used by the contract
    function OPERATOR_AVS_REGISTRATION_TYPEHASH() external view returns (bytes32);
}
