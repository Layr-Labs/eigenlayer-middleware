
╭----------------------------+-----------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------------╮
| Name                       | Type                                                      | Slot | Offset | Bytes | Contract                                                              |
+========================================================================================================================================================================================+
| _totalOperators            | uint256                                                   | 0    | 0      | 32    | src/unaudited/ECDSAStakeRegistryStorage.sol:ECDSAStakeRegistryStorage |
|----------------------------+-----------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------------|
| _quorum                    | struct Quorum                                             | 1    | 0      | 32    | src/unaudited/ECDSAStakeRegistryStorage.sol:ECDSAStakeRegistryStorage |
|----------------------------+-----------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------------|
| _minimumWeight             | uint256                                                   | 2    | 0      | 32    | src/unaudited/ECDSAStakeRegistryStorage.sol:ECDSAStakeRegistryStorage |
|----------------------------+-----------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------------|
| _serviceManager            | address                                                   | 3    | 0      | 20    | src/unaudited/ECDSAStakeRegistryStorage.sol:ECDSAStakeRegistryStorage |
|----------------------------+-----------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------------|
| _stakeExpiry               | uint256                                                   | 4    | 0      | 32    | src/unaudited/ECDSAStakeRegistryStorage.sol:ECDSAStakeRegistryStorage |
|----------------------------+-----------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------------|
| _operatorSigningKeyHistory | mapping(address => struct CheckpointsUpgradeable.History) | 5    | 0      | 32    | src/unaudited/ECDSAStakeRegistryStorage.sol:ECDSAStakeRegistryStorage |
|----------------------------+-----------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------------|
| _totalWeightHistory        | struct CheckpointsUpgradeable.History                     | 6    | 0      | 32    | src/unaudited/ECDSAStakeRegistryStorage.sol:ECDSAStakeRegistryStorage |
|----------------------------+-----------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------------|
| _thresholdWeightHistory    | struct CheckpointsUpgradeable.History                     | 7    | 0      | 32    | src/unaudited/ECDSAStakeRegistryStorage.sol:ECDSAStakeRegistryStorage |
|----------------------------+-----------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------------|
| _operatorWeightHistory     | mapping(address => struct CheckpointsUpgradeable.History) | 8    | 0      | 32    | src/unaudited/ECDSAStakeRegistryStorage.sol:ECDSAStakeRegistryStorage |
|----------------------------+-----------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------------|
| _operatorRegistered        | mapping(address => bool)                                  | 9    | 0      | 32    | src/unaudited/ECDSAStakeRegistryStorage.sol:ECDSAStakeRegistryStorage |
|----------------------------+-----------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------------|
| __gap                      | uint256[40]                                               | 10   | 0      | 1280  | src/unaudited/ECDSAStakeRegistryStorage.sol:ECDSAStakeRegistryStorage |
╰----------------------------+-----------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------------╯

