# v2.0.0 UX Improvements

This release brings 2 UX improvements to the middleware repo. We increment the major release due to the new `createSlashableStakeQuorum` interface. 

🚀 New Features

- NonSigner View Function for Bn254 Table Calculator: Constructs nonsigner witness onchain by passing in a list of signers

⛔ Breaking Changes
- Update `createSlashableStakeQuorum` to take in a slasher address

🔧 Improvements
- Move to foundry v1.5.0 and update formatting
- Upgrade solc to 0.8.29

## Changelog


- feat: update registry coordinator for new createOperatorSets  [PR #548](https://github.com/layr-labs/eigenlayer-middleware/pull/548)
- feat: nonsigner view and operator index [PR #545](https://github.com/Layr-Labs/eigenlayer-middleware/pull/542)
- chore: update readMe for middlewarev2 deployment [PR #539](https://github.com/layr-labs/eigenlayer-middleware/pull/539)