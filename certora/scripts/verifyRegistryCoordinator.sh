if [[ "$2" ]]
then
    RULE="--rule $2"
fi

solc-select use 0.8.12

certoraRun certora/harnesses/RegistryCoordinatorHarness.sol \
    lib/openzeppelin-contracts/contracts/mocks/ERC1271WalletMock.sol \
    src/StakeRegistry.sol src/BLSApkRegistry.sol src/IndexRegistry.sol \
    lib/eigenlayer-contracts/src/contracts/core/Slasher.sol \
    lib/eigenlayer-contracts/src/contracts/core/AVSDirectory.sol \
    --verify RegistryCoordinatorHarness:certora/specs/RegistryCoordinator.spec \
    --optimistic_loop \
    --optimistic_hashing \
    --prover_args '-optimisticFallback true -recursionEntryLimit 2 ' \
    $RULE \
    --loop_iter 2 \
    --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable eigenlayer-contracts=lib/eigenlayer-contracts \
    --msg "RegistryCoordinator $1 $2" \

# TODO: import a ServiceManager contract
