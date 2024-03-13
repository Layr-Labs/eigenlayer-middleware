// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

/**
 * @notice Allows operators to delegate their signing to a different address, e.g. to separate
 * "hot keys" from "cold keys" as well as to generally support separation of concerns.
 * @dev Deployable as a stand-alone contract, or can be used as a mix-in.
 */
contract OperatorAddressDelegation {

    // @notice Mapping: operator => signing key
    mapping(address => address) public operatorSigningKeys;

    // storage gap for upgradeability
    // slither-disable-next-line shadowing-state
    uint256[49] private __GAP;

    event OperatorSigningKeySet(address indexed operator, address indexed signingKey);

    /*******************************************************************************
                    EXTERNAL FUNCTIONS - unpermissioned
    *******************************************************************************/
    // @notice allows the `operator` or their current `signingKey` to set a new signingKey
    function setSigningKey(
        address operator,
        address signingKey
    ) public virtual {
        require(msg.sender == operator || msg.sender == signingKey,
            "OperatorAddressDelegation.setSigningKey: unauthorized caller");
        operatorSigningKeys[operator] = signingKey;
        emit OperatorSigningKeySet(operator, signingKey);
    }

}
