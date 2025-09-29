# 1.5.0-testnet-final

The below release notes cover the updated version release candidate for multichain and hourglass

# Release Manager

@ypatil12 @eigenmikem @rajathalex

# Multichain

## Highlights

🚀 New Features – Highlight major new functionality
- Add new table calculator modules - with stake caps and custom stake weights. **These contracts are unaudited.**. See [PR #514](https://github.com/layr-labs/eigenlayer-middleware/pull/514)

⛔ Breaking Changes – Call out backward-incompatible changes.
- The `BN254CertificateVerifier` now salts the `operatorInfoleaf` via the core [`LeafCalculatorMixin`](https://github.com/Layr-Labs/eigenlayer-contracts/blob/main/src/contracts/mixins/LeafCalculatorMixin.sol) contract. **BN254 OperatorSets MUST update their table calculators to use the new `BN254TableCalculatorBase`. Failure to do so can result in certificates unable to be confirmed.**
- All AVSs in the [presets](../src/middlewareV2/registrar/presets/) now take in the `avs` as a parameter in the `initialize` function, rather than the constructor

🔧 Improvements – Enhancements to existing features.
- Added add UAM support to `SocketRegistry`. See [PR #532](https://github.com/layr-labs/eigenlayer-middleware/pull/532)
- Updated core contract submodule to point to `v1.8.0-testnet-final` RC. See [PR #534](https://github.com/layr-labs/eigenlayer-middleware/pull/534)
- Clear up natspec and docs. See [PR #526](https://github.com/layr-labs/eigenlayer-middleware/pull/526)
- Remove unused imports. See [PR #513](https://github.com/layr-labs/eigenlayer-middleware/pull/513)

🐛 Bug Fixes – List resolved issues.
- Fix array indexing in `BN254TableCalculatorBase`. See [PR #504](https://github.com/layr-labs/eigenlayer-middleware/pull/504)
- Make `avs` var stateful instead of immutable. See [PR #512](https://github.com/layr-labs/eigenlayer-middleware/pull/512)

# Hourglass

## Changelog

- chore: update core submodule + ReadMe [PR #534](https://github.com/layr-labs/eigenlayer-middleware/pull/534)
- fix: add allowlist to TaskAVSRegistarBase [PR #533](https://github.com/layr-labs/eigenlayer-middleware/pull/533)
- feat: add UAM to `SocketRegistry` [PR #532](https://github.com/layr-labs/eigenlayer-middleware/pull/532)
- chore: bump core submodule [PR #531](https://github.com/layr-labs/eigenlayer-middleware/pull/531)
- chore: rev submodule
- fix(m-01): add salt to merkle leaf hashing [PR #527](https://github.com/layr-labs/eigenlayer-middleware/pull/527)
- docs: natspec review updates [PR #526](https://github.com/layr-labs/eigenlayer-middleware/pull/526)
- fix(I-05): remove unused import [PR #529](https://github.com/layr-labs/eigenlayer-middleware/pull/529)
- feat: tablecalc modules [PR #514](https://github.com/layr-labs/eigenlayer-middleware/pull/514)
- fix(I-07): add onlyInitializing modifier to initializing function [PR #525](https://github.com/layr-labs/eigenlayer-middleware/pull/525)
- fix: make storage variable internal due to existing getter [PR #524](https://github.com/layr-labs/eigenlayer-middleware/pull/524)
- chore: update taskavsregistrar base forpt1 findings
- chore: rev submodule
- fix(I-04): make avs var stateful [PR #512](https://github.com/layr-labs/eigenlayer-middleware/pull/512)
- fix(I5): natspec [PR #516](https://github.com/layr-labs/eigenlayer-middleware/pull/516)
- fix(I-07): clarify expectation on `weights` array structure [PR #510](https://github.com/layr-labs/eigenlayer-middleware/pull/510)
- fix(I-03): rename `ISocketRegistry` -> `ISocketRegistryV2` [PR #511](https://github.com/layr-labs/eigenlayer-middleware/pull/511)
- fix(I-06): remove many unused imports [PR #513](https://github.com/layr-labs/eigenlayer-middleware/pull/513)
- chore: updated core contracts dependencies
- chore: bump up core deps
- docs: changelog
- chore: bump up core deps
- feat: hourglass [PR #507](https://github.com/layr-labs/eigenlayer-middleware/pull/507)
- fix(H-1): correct array indexing for BN254TableCalculatorBase._calculateOperatorTable [PR #504](https://github.com/layr-labs/eigenlayer-middleware/pull/504)
- docs: add new table calculators [PR #508](https://github.com/layr-labs/eigenlayer-middleware/pull/508)