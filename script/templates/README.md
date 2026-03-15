# AVS Deployment

Deploy AVS middleware components (registrars and table calculators) with maximum flexibility using a single script.

## Quick Start

### 1. Configure

Edit `../AVSDeployment.s.sol`:

```solidity
// Choose what to deploy
uint8 constant REGISTRAR_TYPE = 1; // Registrar type (1-4, or 0 to skip):
// 1 = Basic, 2 = WithAllowlist, 3 = AsIdentifier, 4 = WithSocket

bool constant DEPLOY_TABLE_CALCULATOR = false; // Set true to deploy calculator
uint8 constant TABLE_CALCULATOR_TYPE = 1; // Calculator type (1-4):
// 1 = BN254Basic, 2 = BN254Weighted, 3 = BN254WithCaps, 4 = ECDSA

// Set your addresses
address constant AVS_ADDRESS = 0x...; // Required for registrar
address constant KEY_REGISTRAR = 0x...;
address constant ALLOCATION_MANAGER = 0x...;
address constant PERMISSION_CONTROLLER = 0x...; // Needed for registrar type 3 or calculator types 2,3
```

### 2. Deploy

```bash
forge script script/AVSDeployment.s.sol --rpc-url $RPC_URL --broadcast
```

### 3. Configure (If Required)

**For Weighted Calculator (Type 2):**
```solidity
tableCalculator.setStrategyMultipliers(operatorSet, strategies, multipliers);
```

**For Allowlist Registrar (Type 2):**
```solidity
registrar.initialize(admin);
```

**For AsIdentifier Registrar (Type 3):**
```solidity
registrar.initialize(admin, metadataURI);
```

## Deployment Options

**Registrar Only** (most common): Set `DEPLOY_TABLE_CALCULATOR = false`  
**Calculator Only**: Set `REGISTRAR_TYPE = 0`  
**Both Together**: Enable both components  
**Custom Calculator**: Skip deployment and use your own

## Component Types

### AVSDeployment.s.sol (located in script/)
Unified deployment script with options for:

**Registrar Types:**
- **Type 1**: AVSRegistrar (basic)
- **Type 2**: AVSRegistrarWithAllowlist (operator allowlist)
- **Type 3**: AVSRegistrarAsIdentifier (identifier-based)
- **Type 4**: AVSRegistrarWithSocket (socket management)

**Table Calculator Types (Optional):**
- **Type 1**: BN254TableCalculator (basic, equal weights)
- **Type 2**: BN254WeightedTableCalculator (custom strategy multipliers)
- **Type 3**: BN254TableCalculatorWithCaps (weight caps per operator)
- **Type 4**: ECDSATableCalculator (ECDSA signatures)



## Customization

For custom table calculator logic, extend the base contracts:

```solidity
contract MyCustomTableCalculator is BN254TableCalculatorBase {
    function _getOperatorWeights(
        OperatorSet calldata operatorSet
    ) internal view override returns (address[] memory, uint256[][] memory) {
        // Custom weight calculation logic
    }
}
```

Deploy separately, then reference the address in your configuration.

## Advanced Configuration

### Configuration Parameters

**REGISTRAR_TYPE**: Which registrar to deploy (1-4, or 0 to skip)  
**DEPLOY_TABLE_CALCULATOR**: Whether to deploy a new table calculator  
**TABLE_CALCULATOR_TYPE**: Which calculator to deploy (1-4, if enabled)  
**AVS_ADDRESS**: The address representing your AVS  
**LOOKAHEAD_BLOCKS**: Blocks to look ahead for stake calculations  

### Result

You'll get:
- ✅ Components deployed and configured for your AVS
- ✅ Complete deployment info displayed in console
- ✅ Type-specific next steps and instructions
- ✅ Ready to integrate and use 