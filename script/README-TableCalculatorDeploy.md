# Table Calculator Deployment Script

This script deploys both `BN254TableCalculator` and `ECDSATableCalculator` contracts.

## Overview

The table calculators are responsible for calculating operator weights and tables for different cryptographic key types:

- **BN254TableCalculator**: Handles BN254 cryptographic operations and aggregate key calculations
- **ECDSATableCalculator**: Handles ECDSA cryptographic operations

Both calculators extend their respective base contracts and implement weight calculations based on slashable stake across all strategies.

## Prerequisites

Before deploying, ensure you have:

1. **KeyRegistrar contract address**: The core EigenLayer KeyRegistrar contract
2. **AllocationManager contract address**: The core EigenLayer AllocationManager contract  
3. **Lookahead blocks**: Number of blocks to look ahead for slashable stake calculations (default: 64)

## Deployment Options

### Option 1: Using Environment Variables

Set the required environment variables and run the script:

```bash
export KEY_REGISTRAR=0x1234567890123456789012345678901234567890
export ALLOCATION_MANAGER=0x0987654321098765432109876543210987654321
export LOOKAHEAD_BLOCKS=64

forge script script/TableCalculatorDeploy.s.sol:TableCalculatorDeploy \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast
```

### Option 2: Using Custom Parameters

Use the `deployWithParams` function to deploy with specific parameters:

```bash
forge script script/TableCalculatorDeploy.s.sol:TableCalculatorDeploy \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --sig "deployWithParams(address,address,uint256)" \
    -- 0x1234567890123456789012345678901234567890 0x0987654321098765432109876543210987654321 64
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `KEY_REGISTRAR` | Yes | - | Address of the KeyRegistrar contract |
| `ALLOCATION_MANAGER` | Yes | - | Address of the AllocationManager contract |
| `LOOKAHEAD_BLOCKS` | No | 64 | Number of blocks for lookahead in stake calculations |

## Constructor Parameters

Both contracts require the same constructor parameters:

1. **IKeyRegistrar _keyRegistrar**: Interface to the KeyRegistrar contract for managing operator keys
2. **IAllocationManager _allocationManager**: Interface to the AllocationManager contract for managing operator allocations
3. **uint256 _LOOKAHEAD_BLOCKS**: Number of blocks to look ahead when fetching minimum slashable stake

## Expected Output

The script will output deployment addresses and confirmation:

```
=== Table Calculator Deployment ===
Key Registrar: 0x1234567890123456789012345678901234567890
Allocation Manager: 0x0987654321098765432109876543210987654321
Lookahead Blocks: 64
Deployer: 0xYourDeployerAddress

Deploying BN254TableCalculator...
BN254TableCalculator deployed at: 0xNewBN254Address

Deploying ECDSATableCalculator...
ECDSATableCalculator deployed at: 0xNewECDSAAddress

=== Deployment Summary ===
BN254TableCalculator: 0xNewBN254Address
ECDSATableCalculator: 0xNewECDSAAddress
Deployment completed successfully!
```

## Gas Estimation

To estimate gas costs before deployment:

```bash
forge script script/TableCalculatorDeploy.s.sol:TableCalculatorDeploy \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY
```

## Verification

After deployment, you can verify the contracts on Etherscan:

```bash
# For BN254TableCalculator
forge verify-contract \
    --chain-id $CHAIN_ID \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --constructor-args $(cast abi-encode "constructor(address,address,uint256)" $KEY_REGISTRAR $ALLOCATION_MANAGER $LOOKAHEAD_BLOCKS) \
    $BN254_TABLE_CALCULATOR_ADDRESS \
    src/middlewareV2/tableCalculator/BN254TableCalculator.sol:BN254TableCalculator

# For ECDSATableCalculator  
forge verify-contract \
    --chain-id $CHAIN_ID \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --constructor-args $(cast abi-encode "constructor(address,address,uint256)" $KEY_REGISTRAR $ALLOCATION_MANAGER $LOOKAHEAD_BLOCKS) \
    $ECDSA_TABLE_CALCULATOR_ADDRESS \
    src/middlewareV2/tableCalculator/ECDSATableCalculator.sol:ECDSATableCalculator
```

## Common Issues

1. **Missing required parameters**: Ensure `KEY_REGISTRAR` and `ALLOCATION_MANAGER` environment variables are set
2. **Invalid addresses**: Verify that the provided contract addresses are correct and deployed
3. **Insufficient funds**: Ensure the deployer account has enough ETH for gas costs
4. **Network connectivity**: Verify RPC URL is accessible and responsive

## Integration

After deployment, you can integrate these contracts with your AVS by:

1. Configuring operator sets in the KeyRegistrar to use the appropriate curve type (BN254 or ECDSA)
2. Setting up your AVSRegistrar to validate keys against the deployed calculators
3. Using the table calculators in your service manager to compute operator weights and aggregate keys 