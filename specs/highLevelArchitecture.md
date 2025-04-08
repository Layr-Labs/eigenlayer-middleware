# High-Level Architecture for Certificate Verification

## Key Components

Our certificate verification prototype consists of two main contracts that work together to verify certificates issued by operators in an AVS (Actively Validated Service).

### 1. OperatorTableCalculator

This contract is responsible for producing operator tables with cryptographic keys and stake weights:

- **Keys**: ECDSA keys will be used for signature verification
- **Stake Weights**: Flexible array of `uint96` values that can be customized by the AVS:
  - Single value array: `[slashable_weight]` - Evaluates purely on slashable stake
  - Two value array: `[slashable_weight, delegated_weight]` - Evaluates on both slashable and delegated stake
  - Multiple value array: `[slashable_weight_i, delegated_weight_i, slashable_weight_{i+1}, delegated_weight_{i+1}, ...]` - Supports multiple strategies (e.g., ETH and EIGEN)

The default ECDSA implementation will return all operators in order from the AllocationManager, along with a set of linearly combined weights using strategies and multipliers configured by the deployer. AVSs can extend or modify this contract to suit their specific needs, but must maintain the same return type to ensure compatibility with the verification stack.

### 2. CertificateVerifier

This contract verifies certificates based on the operator table provided by the OperatorTableCalculator. It supports two types of confirmation conditions:

- **Proportional**: Requires certificates to be signed by operators representing more than a configurable proportion of the total stake for each stake value
  - Example: "66% of the slashable stake must sign every certificate"

- **Nominal**: Requires certificates to be signed by operators representing more than a configurable nominal amount of each stake value
  - Example: "10 million ZRO must sign every certificate"

## Architecture Flow

1. An AVS assigns operators to produce and sign certificates for specific statements
2. The OperatorTableCalculator generates an operator table with keys and stake weights
3. When a certificate needs verification, the CertificateVerifier:
   - Uses the operator table to identify signers
   - Calculates the total stake represented by the signers
   - Applies the confirmation condition (proportional or nominal)
   - Returns whether the certificate meets the required threshold

## Extensibility

While providing these default implementations, the architecture is designed to be extensible:

- AVSs can create custom OperatorTableCalculator implementations to support different key types or stake calculation methods
- The confirmation conditions can be configured to match the specific security requirements of each AVS
- The stake weight array structure allows for future extensions without changing the interface 