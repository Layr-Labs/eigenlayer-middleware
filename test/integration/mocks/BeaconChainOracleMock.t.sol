// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "eigenlayer-contracts/src/test/integration/deprecatedInterfaces/mainnet/IBeaconChainOracle.sol";

// NOTE: There's a copy of this file in the core repo, but importing that was causing
// the compiler to complain for an unfathomable reason. Apparently reimplementing it
// here fixes the issue.
contract BeaconChainOracleMock is IBeaconChainOracle_DeprecatedM1 {
  mapping(uint64 => bytes32) blockRoots;

  function timestampToBlockRoot(uint timestamp) public view returns (bytes32) {
    return blockRoots[uint64(timestamp)];
  }

  function setBlockRoot(uint64 timestamp, bytes32 blockRoot) public {
    blockRoots[timestamp] = blockRoot;
  }

  function latestConfirmedOracleBlockNumber()
    external
    view
    override
    returns (uint64)
  {}

  function beaconStateRootAtBlockNumber(
    uint64 blockNumber
  ) external view override returns (bytes32) {}

  function isOracleSigner(
    address _oracleSigner
  ) external view override returns (bool) {}

  function hasVoted(
    uint64 blockNumber,
    address oracleSigner
  ) external view override returns (bool) {}

  function stateRootVotes(
    uint64 blockNumber,
    bytes32 stateRoot
  ) external view override returns (uint256) {}

  function totalOracleSigners() external view override returns (uint256) {}

  function threshold() external view override returns (uint256) {}

  function setThreshold(uint256 _threshold) external override {}

  function addOracleSigners(
    address[] memory _oracleSigners
  ) external override {}

  function removeOracleSigners(
    address[] memory _oracleSigners
  ) external override {}

  function voteForBeaconChainStateRoot(
    uint64 blockNumber,
    bytes32 stateRoot
  ) external override {}
}
