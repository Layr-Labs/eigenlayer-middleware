// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ISlasher} from "../../interfaces/ISlasher.sol";
contract SlasherStorage is ISlasher {
    address public serviceManager;
    address public slasher;
    uint256 public nextRequestId;

    uint256[47] private __gap;
}