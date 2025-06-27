[elip-008]: https://github.com/eigenfoundation/ELIPs/blob/main/ELIPs/ELIP-008.md
[core-multichain-docs]: https://github.com/Layr-Labs/eigenlayer-contracts/tree/release-dev/multichain/docs/multichain

## MiddlewareV2

The middlewareV2 architecture utilizes EigenLayer core contracts as a base for new multichain contracts. 

---

### Contents

* [System Diagram](#system-diagram)
* [AVS Registrar](#avs-registrar)
* [Operator Table Calculator](#operator-table-calculator)
    * [`ECSDATableCalculator`](#ecdsatablecalculator)
    * [`BN254TableCalculator`](#bn254tablecalculator)
* [Core Contract Integrations](#core-contract-integrations)
    * [`KeyRegistrar`](#key-registrar)
    * [`AllocationManager`](#allocation-manager)
    * [`CertificateVerifier`](#certificate-verifier)
* [Roles and Actors](#roles-and-actors)
* [Migration](#migration)

---

### System Diagram

---

### AVS Registrar

---

### Operator Table Calculator

| File | Type |
| -------- | -------- |
| [`BN254TableCalculatorBase.sol`](../../src/middlewareV2/tableCalculator/BN254TableCalculatorBase.sol) | Abstract Contract |
| [`BN254TableCalculator.sol`](../../src/middlewareV2/tableCalculator/BN254TableCalculator.sol) | Basic table calculator that sums slashable stake across all strategies | 
| [`ECDSATableCalculatorBase.sol`](../../src/middlewareV2/tableCalculator/ECDSATableCalculator.sol) | Abstract Contract |
| [`ECDSATableCalculator.sol`](../../src/middlewareV2/tableCalculator/ECDSATableCalculator.sol) | Basic table calculator that sums slashable stake across all strategies | 


These contracts define custom stake weights of operators in an operatorSet. They are segmented by key-type. 

See full documentation in [`/operatorTableCalculator.md`](./OperatorTableCalculator.md).

---

### Core Contract Integrations

#### Key Registrar

#### Allocation Manager

#### Certificate Verifier

---

### Roles and Actors

---

### Migration