# AVS Middleware Deployment Scripts

This directory contains comprehensive deployment scripts for AVS middleware contracts, designed to work with the EigenLayer UAM (Unified Account Management) system.

## Overview

The key insight is that **key management is now entirely handled by the core EigenLayer protocol**. AVS operators only need to deploy and configure:

1. **AVSRegistrar** - Manages operator registration/deregistration for your AVS
2. **OperatorTableCalculator** - Calculates stake weights for operators in your operator sets

## Quick Start

1. **Choose your configuration** based on your AVS needs:
   - `avs-basic.example.json` - Simple AVS with basic functionality
   - `avs-weighted.example.json` - Advanced AVS with custom strategy weights
   - `avs-allowlist.example.json` - Permissioned AVS with operator allowlists

2. **Copy and customize** the appropriate config file:
   ```bash
   cp script/config/avs-basic.example.json script/config/my-avs.json
   # Edit my-avs.json with your specific addresses and parameters
   ```

3. **Deploy your middleware**:
   ```bash
   # Option 1: Using forge directly
   CONFIG_FILE=script/config/my-avs.json forge script script/AVSMiddlewareDeploy.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
   
   # Option 2: Using the convenience script
   CONFIG_FILE=script/config/my-avs.json ./script/examples/deploy-simple-avs.sh
   ```

## Configuration Guide

### Core Addresses (Required)

Update these addresses for your target network:

```json
{
  "allocationManager": "0x...",    // Core EigenLayer AllocationManager
  "keyRegistrar": "0x...",         // Core EigenLayer KeyRegistrar  
  "avsDirectory": "0x...",         // Core EigenLayer AVSDirectory
  "permissionController": "0x...", // Core EigenLayer PermissionController
  "proxyAdmin": ""                 // Leave empty to deploy new one
}
```

### Registrar Types

Choose the registrar type that fits your AVS model:

| Type | Value | Description | Use Case |
|------|-------|-------------|----------|
| `BASIC` | 0 | Simple operator registration | Open AVS with minimal restrictions |
| `WITH_ALLOWLIST` | 1 | Permissioned operator registration | Curated operator sets |
| `WITH_SOCKET` | 2 | Socket-based communication | AVS requiring operator endpoints |
| `AS_IDENTIFIER` | 3 | Registrar acts as AVS identifier | Full AVS protocol integration |

### Calculator Types

Choose the table calculator based on your staking model:

| Type | Value | Description | Use Case |
|------|-------|-------------|----------|
| `BN254_BASIC` | 0 | Equal weight for all strategies | Simple staking model |
| `BN254_WEIGHTED` | 1 | Custom multipliers per strategy | Preferred assets/strategies |
| `BN254_WITH_CAPS` | 2 | Stake caps per strategy | Risk management |
| `ECDSA_BASIC` | 3 | ECDSA-based validation | ECDSA signature schemes |

## Example Configurations

### Basic AVS Setup

```json
{
  "registrarType": 0,        // Basic registrar
  "calculatorType": 0,       // Basic BN254 calculator
  "useProxy": true,          // Upgradeable registrar
  "lookaheadBlocks": 100     // Finality buffer
}
```

### Advanced Weighted Setup

```json
{
  "registrarType": 3,        // AS_IDENTIFIER for full integration
  "calculatorType": 1,       // Weighted calculator
  "strategies": [
    "0x...",                 // ETH strategy
    "0x..."                  // BTC strategy  
  ],
  "multipliers": [
    20000,                   // 2x weight for ETH
    15000                    // 1.5x weight for BTC
  ]
}
```

## Post-Deployment Configuration

After deployment, use the utility scripts for additional configuration:

### 1. Configure Operator Sets

```bash
forge script script/utils/AVSDeployUtils.sol:AVSDeployUtils \
  --sig "configureOperatorSets(address,address,OperatorSetConfig[])" \
  $ALLOCATION_MANAGER $AVS_ADDRESS $OPERATOR_SET_CONFIGS \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

### 2. Set Strategy Multipliers (Weighted Calculators)

```bash
forge script script/utils/AVSDeployUtils.sol:AVSDeployUtils \
  --sig "configureWeightedCalculators(WeightedCalculatorConfig[])" \
  $WEIGHTED_CONFIGS \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

### 3. Configure Allowlists (Allowlist Registrars)

```bash
forge script script/utils/AVSDeployUtils.sol:AVSDeployUtils \
  --sig "configureAllowlists(AllowlistConfig[])" \
  $ALLOWLIST_CONFIGS \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

## Common Deployment Patterns

### Pattern 1: Simple Open AVS

1. Use `BASIC` registrar with `BN254_BASIC` calculator
2. Create operator sets with your strategies
3. Operators can register directly

### Pattern 2: Curated AVS with Preferred Assets

1. Use `WITH_ALLOWLIST` registrar with `BN254_WEIGHTED` calculator
2. Set custom multipliers for preferred strategies
3. Maintain allowlist of approved operators

### Pattern 3: Full Protocol Integration

1. Use `AS_IDENTIFIER` registrar (registrar becomes the AVS)
2. Choose appropriate calculator for your needs
3. Registrar handles full EigenLayer protocol integration

## Network Addresses

### Preprod (Chain ID: 17000)
```json
{
  "allocationManager": "0x75dfE5B44C2E530568001400D3f704bC8AE350CC",
  "avsDirectory": "0x141d6995556135D4997b2ff72EB443Be300353bC",
  "permissionController": "0xa2348c77802238Db39f0CefAa500B62D3FDD682b"
}
```

*Note: Update `keyRegistrar` address based on your network deployment*

## Troubleshooting

### Common Issues

1. **Config parsing errors**: Ensure JSON is valid and all required fields are present
2. **Address verification failed**: Double-check core protocol addresses for your network
3. **Initialization failed**: Verify AVS owner has proper permissions

### Verification

Use the verification utility:

```bash
forge script script/utils/AVSDeployUtils.sol:AVSDeployUtils \
  --sig "verifyDeployment(address,address,address,address)" \
  $REGISTRAR $TABLE_CALCULATOR $ALLOCATION_MANAGER $AVS \
  --rpc-url $RPC_URL
```

## Integration with Core Protocol

After deployment, you'll need to:

1. **Register with AllocationManager**: Set your registrar as the AVS registrar
2. **Configure CrossChainRegistry**: If using multichain features
3. **Set up Operator Sets**: Define strategies and thresholds
4. **Configure Slashing**: Set up slashing parameters if needed

## Security Considerations

- Use proxy patterns for upgradeability
- Verify all core protocol addresses before deployment
- Test configurations on testnets first
- Consider operator allowlists for sensitive AVS operations
- Review strategy multipliers for economic security

## Support

For questions or issues:
- Review the [middleware documentation](../docs/middlewareV2/README.md)
- Check existing tests for usage examples
- Consult EigenLayer core protocol documentation 