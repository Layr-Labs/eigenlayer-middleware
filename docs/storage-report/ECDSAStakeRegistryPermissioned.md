
╭----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------╮
| Name                       | Type                                                      | Slot | Offset | Bytes | Contract                                                                                 |
+===========================================================================================================================================================================================================+
| _initialized               | uint8                                                     | 0    | 0      | 1     | src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol:ECDSAStakeRegistryPermissioned |
|----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------|
| _initializing              | bool                                                      | 0    | 1      | 1     | src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol:ECDSAStakeRegistryPermissioned |
|----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------|
| __gap                      | uint256[50]                                               | 1    | 0      | 1600  | src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol:ECDSAStakeRegistryPermissioned |
|----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------|
| _owner                     | address                                                   | 51   | 0      | 20    | src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol:ECDSAStakeRegistryPermissioned |
|----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------|
| __gap                      | uint256[49]                                               | 52   | 0      | 1568  | src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol:ECDSAStakeRegistryPermissioned |
|----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------|
| _totalOperators            | uint256                                                   | 101  | 0      | 32    | src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol:ECDSAStakeRegistryPermissioned |
|----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------|
| _quorum                    | struct Quorum                                             | 102  | 0      | 32    | src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol:ECDSAStakeRegistryPermissioned |
|----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------|
| _minimumWeight             | uint256                                                   | 103  | 0      | 32    | src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol:ECDSAStakeRegistryPermissioned |
|----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------|
| _serviceManager            | address                                                   | 104  | 0      | 20    | src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol:ECDSAStakeRegistryPermissioned |
|----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------|
| _stakeExpiry               | uint256                                                   | 105  | 0      | 32    | src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol:ECDSAStakeRegistryPermissioned |
|----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------|
| _operatorSigningKeyHistory | mapping(address => struct CheckpointsUpgradeable.History) | 106  | 0      | 32    | src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol:ECDSAStakeRegistryPermissioned |
|----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------|
| _totalWeightHistory        | struct CheckpointsUpgradeable.History                     | 107  | 0      | 32    | src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol:ECDSAStakeRegistryPermissioned |
|----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------|
| _thresholdWeightHistory    | struct CheckpointsUpgradeable.History                     | 108  | 0      | 32    | src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol:ECDSAStakeRegistryPermissioned |
|----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------|
| _operatorWeightHistory     | mapping(address => struct CheckpointsUpgradeable.History) | 109  | 0      | 32    | src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol:ECDSAStakeRegistryPermissioned |
|----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------|
| _operatorRegistered        | mapping(address => bool)                                  | 110  | 0      | 32    | src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol:ECDSAStakeRegistryPermissioned |
|----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------|
| __gap                      | uint256[40]                                               | 111  | 0      | 1280  | src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol:ECDSAStakeRegistryPermissioned |
|----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------|
| allowlistedOperators       | mapping(address => bool)                                  | 151  | 0      | 32    | src/unaudited/examples/ECDSAStakeRegistryPermissioned.sol:ECDSAStakeRegistryPermissioned |
╰----------------------------+-----------------------------------------------------------+------+--------+-------+------------------------------------------------------------------------------------------╯

