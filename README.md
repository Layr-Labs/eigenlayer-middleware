[core-docs-dev]: https://github.com/Layr-Labs/eigenlayer-contracts/tree/dev/docs
[core-repo]: https://github.com/Layr-Labs/eigenlayer-contracts

# EigenLayer Middleware

EigenLayer is a set of smart contracts deployed on Ethereum that enable restaking of assets to secure new services called AVSs (actively validated services). The core contracts that enable these features can be found in the [`eigenlayer-contracts` repo][core-repo].

## Getting Started

* [Branching](#branching)
* [Documentation](#documentation)
* [Building and Running Tests](#building-and-running-tests)
* [Deployments](#deployments)

## Branching

The main branches we use are:

* [`dev (default)`](https://github.com/Layr-Labs/eigenlayer-middleware/tree/dev): The most up-to-date branch, containing the work-in-progress code for upcoming releases
* [`testnet-holesky`](https://github.com/Layr-Labs/eigenlayer-middleware/tree/testnet-holesky): Our current testnet deployment
* [`mainnet`](https://github.com/Layr-Labs/eigenlayer-middleware/tree/mainnet): Our current mainnet deployment

## Documentation

### Basics

To get a basic understanding of EigenLayer, check out [You Could've Invented EigenLayer](https://www.blog.eigenlayer.xyz/ycie/). Note that some of the document's content describes features that do not exist yet (like the Slasher). To understand more about how restakers and operators interact with EigenLayer, check out these guides:

* [Restaking User Guide](https://docs.eigenlayer.xyz/restaking-guides/restaking-user-guide)
* [Operator Guide](https://docs.eigenlayer.xyz/operator-guides/operator-introduction)

Most of this content is intro-level and describes user interactions with the EigenLayer core contracts, but it should give you a good enough starting point.

### Deep Dive

For shadowy super-coders:

* The most up-to-date technical documentation can be found in [/docs](/docs).
* To get an idea of how users interact with these contracts, check out the integration tests: [/test/integration](./test/integration)
* To explore the EigenLayer core contracts, check out the core repo technical docs [here][core-docs-dev].

### Note On Slashing

The middleware contracts are available for testnet integration and experimentation. As with the rest of the testnet code, these contracts have not yet been fully audited. Internal security reviews are in progress, and we're preparing to engage external auditors. We're providing these now so AVSs can begin testing slashing conditions, Operator Sets, and related functionality, and so Operators can simulate slashing and test allocations. For more details, see [ELIP-002](https://github.com/eigenfoundation/ELIPs/blob/main/ELIPs/ELIP-002.md).

For Operators:

We provide scripts to deploy a mock service manager and allocate some stake to a mock Operator Set in [these scripts](https://github.com/Layr-Labs/eigenlayer-middleware/pull/335).
We've reduced various safety delays on testnet to better simulate operational flows. Additional information on these delays is in [ELIP-002](https://github.com/eigenfoundation/ELIPs/blob/main/ELIPs/ELIP-002.md).
For AVSs:

We provide a migration path for existing M2 environments (LINK). While this requires understanding the provided script, the Developer Experience will improve before Mainnet launch. Note that this is a gradual migration process to new Operator Sets, not a direct upgrade of existing Operator Sets.
We also provide scripts to spin up new service managers from scratch.
In all cases, you’ll need to register existing Operators or spin up new Operators and allocate funds to them. These testing flows will improve as we refine the scripts and contracts. Stay tuned for updates, and feel free to reach out with any questions.

## Building and Running Tests

This repository uses Foundry. See the [Foundry docs](https://book.getfoundry.sh/) for more info on installation and usage. If you already have foundry, you can build this project and run tests with these commands:

```sh
foundryup

forge build
forge test
```
