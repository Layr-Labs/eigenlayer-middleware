// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ERC20Mock is ERC20 {
    constructor() ERC20("", "") {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}
