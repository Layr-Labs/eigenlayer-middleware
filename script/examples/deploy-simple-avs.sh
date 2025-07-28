#!/bin/bash

# Simple AVS Deployment Example
# This script demonstrates deploying AVS middleware using a pre-configured config file

set -e

# Configuration
NETWORK=${NETWORK:-"preprod"}
RPC_URL=${RPC_URL:-"https://rpc.preprod.eigenlayer.xyz"}
PRIVATE_KEY=${PRIVATE_KEY:-""}
CONFIG_FILE=${CONFIG_FILE:-"script/config/avs-basic.example.json"}

# Validate required environment variables
if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY environment variable is required"
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    echo ""
    echo "Please copy and customize one of the example configs:"
    echo "  cp script/config/avs-basic.example.json script/config/my-avs.json"
    echo "  # Edit my-avs.json with your addresses"
    echo "  CONFIG_FILE=script/config/my-avs.json $0"
    exit 1
fi

echo "=== AVS Middleware Deployment ==="
echo "Network: $NETWORK"
echo "Config: $CONFIG_FILE"
echo "RPC URL: $RPC_URL"
echo ""

# Deploy contracts
echo "Deploying AVS middleware contracts..."
CONFIG_FILE=$CONFIG_FILE forge script script/AVSMiddlewareDeploy.s.sol:AVSMiddlewareDeploy \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    $([[ -n "$ETHERSCAN_API_KEY" ]] && echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY" || echo "") \
    -vvvv

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Next steps:"
echo "1. Configure operator sets in AllocationManager"
echo "2. Set your registrar in AllocationManager.setAVSRegistrar()"
echo "3. Register operators to your AVS"
echo ""
echo "Deployment details are logged above." 