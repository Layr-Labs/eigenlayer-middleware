// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {IAllowlist} from "./IAllowlist.sol";

interface IAVSRegistrarWithAllowlist is IAVSRegistrar, IAllowlist {}
