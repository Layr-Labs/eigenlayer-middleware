// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {ISlasher} from "../../interfaces/ISlasher.sol";
contract SlasherStorage is ISlasher {
    address public serviceManager;

    uint256[49] private __gap;
}