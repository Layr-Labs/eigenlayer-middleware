// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";
import {ISocketRegistryV2} from "./ISocketRegistryV2.sol";

interface IAVSRegistrarWithSocket is IAVSRegistrar, ISocketRegistryV2 {}
