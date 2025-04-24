// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IBLSCertificateVerifier} from "../interfaces/IBLSCertificateVerifier.sol";

import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

contract BLSCertificateVerifier is Ownable, IBLSCertificateVerifier {
    /// Storage

    // Basic State
    OperatorSet private _operatorSet;
    address public operatorTableUpdater;
    uint32 public maxOperatorTableStaleness;
    uint32 public latestReferenceTimestamp;

    // Operator Table
    
    /// @notice The operator set info for each reference timestamp
    mapping(uint32 referenceTimestamp => BN254OperatorSetInfo operatorSetInfo) internal _operatorSetInfos;

    /// @notice The operator info tree root for each reference timestamp
    mapping(uint32 referenceTimestamp => bytes32 operatorInfoTreeRoot) internal _operatorInfoTreeRoots;

    /// @notice Mapping from referenceTimestamp => index => operatorInfo
    mapping(uint32 referenceTimestamp => mapping(uint32 index => BN254OperatorInfo operatorInfo)) internal _operatorInfos;

    // Caching

    // Events
    event OperatorTableUpdaterSet(address indexed operatorTableUpdater);
    event MaxOperatorTableStalenessSet(uint32 indexed maxOperatorTableStaleness);

    modifier onlyOperatorTableUpdater() {
        require(msg.sender == operatorTableUpdater, OnlyTableUpdater());
        _;
    }

    constructor(OperatorSet memory _initialOperatorSet, address _operatorTableUpdater, uint32 _maxOperatorTableStaleness, address owner) {
        _operatorSet = _initialOperatorSet;
        operatorTableUpdater = _operatorTableUpdater;
        maxOperatorTableStaleness = _maxOperatorTableStaleness;
        _transferOwnership(owner);
    }

    // Global State Update Functions

    function updateOperatorTable(
        uint32 referenceTimestamp,
        BN254OperatorSetInfo memory operatorSetInfo,
        bytes32 operatorInfoTreeRoot
    ) external override onlyOperatorTableUpdater {

        // Update state
        _operatorSetInfos[referenceTimestamp] = operatorSetInfo;
        _operatorInfoTreeRoots[referenceTimestamp] = operatorInfoTreeRoot;
        latestReferenceTimestamp = referenceTimestamp;

        emit TableUpdated(referenceTimestamp, operatorSetInfo.aggregatePubkey, operatorInfoTreeRoot);
    }

    /// @inheritdoc IBLSCertificateVerifier
    function ejectOperators(
        uint32 referenceTimestamp,
        uint32[] calldata operatorIndices,
        BN254OperatorInfoWitness[] calldata witnesses
    ) external onlyOperatorTableUpdater {
        // TODO: Implement
    }

    // Verification

    /// @inheritdoc IBLSCertificateVerifier
    function verifyCertificate(BN254Certificate calldata certificate) external view returns (uint96[] memory) {
        // Placeholder implementation
        uint96[] memory signedStakes = new uint96[](1);
        signedStakes[0] = 100;
        return signedStakes;
    }

    /// @inheritdoc IBLSCertificateVerifier
    function verifyCertificateProportion(BN254Certificate calldata certificate, uint16[] memory totalStakeProportionThresholds) external view returns (bool) {
        return true;
    }

    /// @inheritdoc IBLSCertificateVerifier
    function verifyCertificateNominal(BN254Certificate calldata certificate, uint96[] memory totalStakeNominalThresholds) external view returns (bool) {
        return true;
    }

    // Setters

    /// @inheritdoc IBLSCertificateVerifier
    function setOperatorTableUpdater(address _operatorTableUpdater) external onlyOwner {
        operatorTableUpdater = _operatorTableUpdater;
        emit OperatorTableUpdaterSet(_operatorTableUpdater);
    }

    /// @inheritdoc IBLSCertificateVerifier
    function setMaxOperatorTableStaleness(uint32 _maxOperatorTableStaleness) external onlyOwner {
        maxOperatorTableStaleness = _maxOperatorTableStaleness;
        emit MaxOperatorTableStalenessSet(_maxOperatorTableStaleness);
    }

    // View Functions

    /// @inheritdoc IBLSCertificateVerifier
    function operatorSet() external view returns (OperatorSet memory) {
        return _operatorSet;
    }
}