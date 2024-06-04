// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {
    IOperatorSetManager,
    ISignatureUtils,
    IStrategy
} from "../../src/interfaces/IOperatorSetManager.sol";

contract OperatorSetManagerMock is IOperatorSetManager {

    /**
     * @notice updates the registration parameters for an operator for a set of 
     * operator sets. whether or not the AVS is allowed to add them to the given 
     * operator set if they are not registered for it
     *
     * @param operator the operator whom the registration parameters are being 
     * changed
     * @param registrationParams the new registration parameters
     * @param allocatorSignature if non-empty is the signature of the allocator on 
     * the modification. if empty, the msg.sender must be the allocator for the 
     * operator
     *
     * @dev changes take effect immediately
     */
    function updateRegistrationParams(
        address operator,
        RegistrationParam[] calldata registrationParams,
        SignatureWithExpiry calldata allocatorSignature
    ) external {}
    
    /**
     * @notice updates the slashing magnitudes for an operator for a set of 
     * operator sets
     * 
     * @param operator the operator whom the slashing parameters are being 
     * changed
     * @param slashingMagnitudeParams the new slashing parameters
     * @param allocatorSignature if non-empty is the signature of the allocator on 
     * the modification. if empty, the msg.sender must be the allocator for the 
     * operator
     *
     * @dev changes take effect in 3 epochs for when this function is called
     */
    function updateSlashingMagnitudes(
        address operator,
        SlashingMagnitudeParam[] calldata slashingMagnitudeParams,
        SignatureWithExpiry calldata allocatorSignature
    ) external returns(uint32 effectEpoch) {}
    
    /// @notice a batch call of updateRegistrationParams and updateSlashingMagnitudes
    function updateRegistrationParamsAndSlashingMagnitudes(
        address operator,
        RegistrationParam[] calldata registrationParams,
        SlashingMagnitudeParam[] calldata slashingMagnitudeParams,
        SignatureWithExpiry calldata allocatorSignature
    ) external returns(uint32 effectEpoch) {}

	function registerOperatorToOperatorSets(
		address operator,
		uint32[] calldata operatorSetIDs,
		ISignatureUtils.SignatureWithSaltAndExpiry memory signature
	) external {}

	function deregisterOperatorFromOperatorSets(
		address operator, 
		uint32[] calldata operatorSetIDs
	) external {}

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
	) external {}

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
	) external {}

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
    ) external returns (bool allowedToRegister) {}

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
    ) external returns (uint16 slashableBips) {}



    /**
     * @notice Called by an avs to register an operator with the avs.
     * @param operator The address of the operator to register.
     * @param operatorSignature The signature, salt, and expiry of the operator's signature.
     */
    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external {}

    /**
     * @notice Called by an avs to deregister an operator with the avs.
     * @param operator The address of the operator to deregister.
     */
    function deregisterOperatorFromAVS(address operator) external {}

    /**
     * @notice Called by an AVS to emit an `AVSMetadataURIUpdated` event indicating the information has updated.
     * @param metadataURI The URI for metadata associated with an AVS
     * @dev Note that the `metadataURI` is *never stored * and is only emitted in the `AVSMetadataURIUpdated` event
     */
    function updateAVSMetadataURI(string calldata metadataURI) external {}

    /**
     * @notice Returns whether or not the salt has already been used by the operator.
     * @dev Salts is used in the `registerOperatorToAVS` function.
     */
    function operatorSaltIsSpent(address operator, bytes32 salt) external view returns (bool) {}

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
    ) external view returns (bytes32) {}

    /// @notice The EIP-712 typehash for the Registration struct used by the contract
    function OPERATOR_AVS_REGISTRATION_TYPEHASH() external view returns (bytes32) {}
} 
