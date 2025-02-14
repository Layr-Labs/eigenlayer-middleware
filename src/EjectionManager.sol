// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {
    EjectionManagerStorage,
    IEjectionManager,
    ISlashingRegistryCoordinator,
    IStakeRegistry
} from "./EjectionManagerStorage.sol";

/**
 * @title Used for automated ejection of operators from the SlashingRegistryCoordinator under a ratelimit
 * @author Layr Labs, Inc.
 */
contract EjectionManager is OwnableUpgradeable, EjectionManagerStorage {
    constructor(
        ISlashingRegistryCoordinator _slashingRegistryCoordinator,
        IStakeRegistry _stakeRegistry
    ) EjectionManagerStorage(_slashingRegistryCoordinator, _stakeRegistry) {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address[] memory _ejectors,
        QuorumEjectionParams[] memory _quorumEjectionParams
    ) external initializer {
        _transferOwnership(_owner);
        for (uint8 i = 0; i < _ejectors.length; i++) {
            _setEjector(_ejectors[i], true);
        }
        for (uint8 i = 0; i < _quorumEjectionParams.length; i++) {
            _setQuorumEjectionParams(i, _quorumEjectionParams[i]);
        }
    }

    /// @inheritdoc IEjectionManager
    function ejectOperators(
        bytes32[][] memory operatorIds
    ) external {
        require(isEjector[msg.sender] || msg.sender == owner(), OnlyOwnerOrEjector());

        for (uint256 i = 0; i < operatorIds.length; ++i) {
            uint8 quorumNumber = uint8(i);

            uint256 amountEjectable = amountEjectableForQuorum(quorumNumber);
            uint256 stakeForEjection;
            uint32 ejectedOperators;

            bool ratelimitHit;
            if (amountEjectable > 0 || msg.sender == owner()) {
                for (uint8 j = 0; j < operatorIds[i].length; ++j) {
                    uint256 operatorStake =
                        stakeRegistry.getCurrentStake(operatorIds[i][j], quorumNumber);

                    //if caller is ejector enforce ratelimit
                    if (
                        isEjector[msg.sender]
                            && quorumEjectionParams[quorumNumber].rateLimitWindow > 0
                            && stakeForEjection + operatorStake > amountEjectable
                    ) {
                        ratelimitHit = true;

                        stakeForEjection += operatorStake;
                        ++ejectedOperators;

                        slashingRegistryCoordinator.ejectOperator(
                            slashingRegistryCoordinator.getOperatorFromId(operatorIds[i][j]),
                            abi.encodePacked(quorumNumber)
                        );

                        emit OperatorEjected(operatorIds[i][j], quorumNumber);

                        break;
                    }

                    stakeForEjection += operatorStake;
                    ++ejectedOperators;

                    slashingRegistryCoordinator.ejectOperator(
                        slashingRegistryCoordinator.getOperatorFromId(operatorIds[i][j]),
                        abi.encodePacked(quorumNumber)
                    );

                    emit OperatorEjected(operatorIds[i][j], quorumNumber);
                }
            }

            //record the stake ejected if ejector and ratelimit enforced
            if (isEjector[msg.sender] && stakeForEjection > 0) {
                stakeEjectedForQuorum[quorumNumber].push(
                    StakeEjection({timestamp: block.timestamp, stakeEjected: stakeForEjection})
                );
            }

            emit QuorumEjection(ejectedOperators, ratelimitHit);
        }
    }

    /// @inheritdoc IEjectionManager
    function setQuorumEjectionParams(
        uint8 quorumNumber,
        QuorumEjectionParams memory _quorumEjectionParams
    ) external onlyOwner {
        _setQuorumEjectionParams(quorumNumber, _quorumEjectionParams);
    }

    /// @inheritdoc IEjectionManager
    function setEjector(address ejector, bool status) external onlyOwner {
        _setEjector(ejector, status);
    }

    ///@dev internal function to set the quorum ejection params
    function _setQuorumEjectionParams(
        uint8 quorumNumber,
        QuorumEjectionParams memory _quorumEjectionParams
    ) internal {
        require(quorumNumber < MAX_QUORUM_COUNT, MaxQuorumCount());
        quorumEjectionParams[quorumNumber] = _quorumEjectionParams;
        emit QuorumEjectionParamsSet(
            quorumNumber,
            _quorumEjectionParams.rateLimitWindow,
            _quorumEjectionParams.ejectableStakePercent
        );
    }

    ///@dev internal function to set the ejector
    function _setEjector(address ejector, bool status) internal {
        isEjector[ejector] = status;
        emit EjectorUpdated(ejector, status);
    }

    /// @inheritdoc IEjectionManager
    function amountEjectableForQuorum(
        uint8 quorumNumber
    ) public view returns (uint256) {
        uint256 totalEjectable = uint256(quorumEjectionParams[quorumNumber].ejectableStakePercent)
            * uint256(stakeRegistry.getCurrentTotalStake(quorumNumber)) / uint256(BIPS_DENOMINATOR);

        if (stakeEjectedForQuorum[quorumNumber].length == 0) {
            return totalEjectable;
        }

        uint256 cutoffTime = block.timestamp - quorumEjectionParams[quorumNumber].rateLimitWindow;
        uint256 totalEjected = 0;
        uint256 i = stakeEjectedForQuorum[quorumNumber].length - 1;

        while (stakeEjectedForQuorum[quorumNumber][i].timestamp > cutoffTime) {
            totalEjected += stakeEjectedForQuorum[quorumNumber][i].stakeEjected;
            if (i == 0) {
                break;
            } else {
                --i;
            }
        }

        if (totalEjected >= totalEjectable) {
            return 0;
        }
        return totalEjectable - totalEjected;
    }
}
