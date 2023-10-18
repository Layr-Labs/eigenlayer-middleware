if [[ "$2" ]]
then
    RULE="--rule $2"
fi

solc-select use 0.8.12

certoraRun certora/harnesses/BLSRegistryCoordinatorWithIndicesHarness.sol \
    lib/eigenlayer-contracts/lib/openzeppelin-contracts/contracts/mocks/ERC1271WalletMock.sol \
    certora/munged/StakeRegistry.sol certora/munged/BLSPubkeyRegistry.sol certora/munged/IndexRegistry.sol \
    lib/eigenlayer-contracts/src/contracts/core/Slasher.sol \
    --verify BLSRegistryCoordinatorWithIndicesHarness:certora/specs/BLSRegistryCoordinatorWithIndices.spec \
    --optimistic_loop \
    --optimistic_hashing \
    --prover_args '-optimisticFallback true -recursionEntryLimit 2 ' \
    $RULE \
    --loop_iter 2 \
    --packages @openzeppelin=lib/eigenlayer-contracts/lib/openzeppelin-contracts @openzeppelin-upgrades=lib/eigenlayer-contracts/lib/openzeppelin-contracts-upgradeable \
    --msg "BLSRegistryCoordinatorWithIndices $1 $2" \

# TODO: import a ServiceManager contract