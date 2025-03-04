// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

// import "eigenlayer-contracts/src/contracts/interfaces/IBeaconChainOracle.sol";

// NOTE: There's a copy of this file in the core repo, but importing that was causing
// the compiler to complain for an unfathomable reason. Apparently reimplementing it
// here fixes the issue.
contract BeaconChainOracleMock {
    // contract BeaconChainOracleMock is IBeaconChainOracle {

    mapping(uint64 => bytes32) blockRoots;
}
