#!/bin/bash

# Homebase Starknet Deployment Script
# This script deploys all contracts in the correct order

set -e

echo "🚀 Starting Homebase Starknet deployment..."

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | xargs)
fi

# Configuration
NETWORK=${NETWORK:-"testnet"}
ACCOUNT_ADDRESS=${ACCOUNT_ADDRESS:-""}
PRIVATE_KEY=${PRIVATE_KEY:-""}

if [ -z "$ACCOUNT_ADDRESS" ] || [ -z "$PRIVATE_KEY" ]; then
    echo "❌ Error: ACCOUNT_ADDRESS and PRIVATE_KEY must be set in .env file"
    exit 1
fi

echo "📋 Deployment Configuration:"
echo "Network: $NETWORK"
echo "Account: $ACCOUNT_ADDRESS"
echo ""

# Build all contracts
echo "🔨 Building contracts..."
scarb build

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo "✅ Build successful!"
echo ""

# Deploy contracts in order
echo "📦 Deploying contracts..."

# 1. Deploy HNXZ Token Contract
echo "1️⃣ Deploying Hancoin Token (HNXZ)..."
TOKEN_RESULT=$(starkli deploy \
    --network $NETWORK \
    --account $ACCOUNT_ADDRESS \
    --private-key $PRIVATE_KEY \
    target/dev/homebase_starknet_HancoinToken.contract_class.json \
    $ACCOUNT_ADDRESS)

TOKEN_ADDRESS=$(echo $TOKEN_RESULT | grep -o "0x[0-9a-fA-F]*" | head -1)
echo "✅ Token deployed at: $TOKEN_ADDRESS"
echo ""

# 2. Deploy Paymaster Contract
echo "2️⃣ Deploying Paymaster Contract..."
PAYMASTER_RESULT=$(starkli deploy \
    --network $NETWORK \
    --account $ACCOUNT_ADDRESS \
    --private-key $PRIVATE_KEY \
    target/dev/homebase_starknet_Paymaster.contract_class.json \
    $ACCOUNT_ADDRESS \
    $TOKEN_ADDRESS \
    1000000000000000)

PAYMASTER_ADDRESS=$(echo $PAYMASTER_RESULT | grep -o "0x[0-9a-fA-F]*" | head -1)
echo "✅ Paymaster deployed at: $PAYMASTER_ADDRESS"
echo ""

# 3. Deploy Loan Contract
echo "3️⃣ Deploying Loan Contract..."
LOAN_RESULT=$(starkli deploy \
    --network $NETWORK \
    --account $ACCOUNT_ADDRESS \
    --private-key $PRIVATE_KEY \
    target/dev/homebase_starknet_LoanContract.contract_class.json \
    $ACCOUNT_ADDRESS \
    $TOKEN_ADDRESS \
    15000 \
    1000)

LOAN_ADDRESS=$(echo $LOAN_RESULT | grep -o "0x[0-9a-fA-F]*" | head -1)
echo "✅ Loan contract deployed at: $LOAN_ADDRESS"
echo ""

# 4. Deploy Escrow Contract
echo "4️⃣ Deploying Escrow Contract..."
ADMIN_WALLET=${ADMIN_WALLET:-$ACCOUNT_ADDRESS}
ESCROW_RESULT=$(starkli deploy \
    --network $NETWORK \
    --account $ACCOUNT_ADDRESS \
    --private-key $PRIVATE_KEY \
    target/dev/homebase_starknet_EscrowContract.contract_class.json \
    $ACCOUNT_ADDRESS \
    $TOKEN_ADDRESS \
    $ADMIN_WALLET \
    250)

ESCROW_ADDRESS=$(echo $ESCROW_RESULT | grep -o "0x[0-9a-fA-F]*" | head -1)
echo "✅ Escrow contract deployed at: $ESCROW_ADDRESS"
echo ""

# 5. Deploy Swap Contract
echo "5️⃣ Deploying Swap Contract..."
JEDISWAP_ROUTER=${JEDISWAP_ROUTER:-"0x041fd22b238fa21cfcf5dd45a8548974d8263b3a531a60388411c5e230f97023"}
SWAP_RESULT=$(starkli deploy \
    --network $NETWORK \
    --account $ACCOUNT_ADDRESS \
    --private-key $PRIVATE_KEY \
    target/dev/homebase_starknet_SwapContract.contract_class.json \
    $ACCOUNT_ADDRESS \
    $TOKEN_ADDRESS \
    $JEDISWAP_ROUTER)

SWAP_ADDRESS=$(echo $SWAP_RESULT | grep -o "0x[0-9a-fA-F]*" | head -1)
echo "✅ Swap contract deployed at: $SWAP_ADDRESS"
echo ""

# 6. Deploy Credit Card Simulator
echo "6️⃣ Deploying Credit Card Simulator..."
CREDIT_CARD_RESULT=$(starkli deploy \
    --network $NETWORK \
    --account $ACCOUNT_ADDRESS \
    --private-key $PRIVATE_KEY \
    target/dev/homebase_starknet_CreditCardSimulator.contract_class.json \
    $ACCOUNT_ADDRESS \
    $TOKEN_ADDRESS)

CREDIT_CARD_ADDRESS=$(echo $CREDIT_CARD_RESULT | grep -o "0x[0-9a-fA-F]*" | head -1)
CREDIT_CARD_ADDRESS=$(echo $CREDIT_CARD_RESULT | grep -o "0x[0-9a-fA-F]*" | head -1)
echo "✅ Credit Card Simulator deployed at: $CREDIT_CARD_ADDRESS"
echo ""

# Post-deployment configuration
echo "⚙️ Configuring contracts..."

# Set paymaster in token contract
echo "Setting paymaster authorization..."
starkli invoke \
    --network $NETWORK \
    --account $ACCOUNT_ADDRESS \
    --private-key $PRIVATE_KEY \
    $TOKEN_ADDRESS \
    set_paymaster \
    $PAYMASTER_ADDRESS \
    1

echo "✅ Paymaster authorized"

# Configure supported tokens in swap contract (using placeholder addresses)
echo "Configuring supported tokens in swap contract..."
USDT_ADDRESS=${USDT_ADDRESS:-"0x068f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8"}
USDC_ADDRESS=${USDC_ADDRESS:-"0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8"}
WETH_ADDRESS=${WETH_ADDRESS:-"0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"}

starkli invoke \
    --network $NETWORK \
    --account $ACCOUNT_ADDRESS \
    --private-key $PRIVATE_KEY \
    $SWAP_ADDRESS \
    set_supported_token \
    'USDT' \
    $USDT_ADDRESS

starkli invoke \
    --network $NETWORK \
    --account $ACCOUNT_ADDRESS \
    --private-key $PRIVATE_KEY \
    $SWAP_ADDRESS \
    set_supported_token \
    'USDC' \
    $USDC_ADDRESS

starkli invoke \
    --network $NETWORK \
    --account $ACCOUNT_ADDRESS \
    --private-key $PRIVATE_KEY \
    $SWAP_ADDRESS \
    set_supported_token \
    'WETH' \
    $WETH_ADDRESS

echo "✅ Supported tokens configured"

# Save deployment addresses
echo "💾 Saving deployment addresses..."
cat > deployment_addresses.json << EOF
{
  "network": "$NETWORK",
  "deployer": "$ACCOUNT_ADDRESS",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "contracts": {
    "hancoin_token": "$TOKEN_ADDRESS",
    "paymaster": "$PAYMASTER_ADDRESS",
    "loan_contract": "$LOAN_ADDRESS",
    "escrow_contract": "$ESCROW_ADDRESS",
    "swap_contract": "$SWAP_ADDRESS",
    "credit_card_simulator": "$CREDIT_CARD_ADDRESS"
  },
  "external_tokens": {
    "usdt": "$USDT_ADDRESS",
    "usdc": "$USDC_ADDRESS",
    "weth": "$WETH_ADDRESS"
  }
}
EOF

echo "✅ Deployment addresses saved to deployment_addresses.json"
echo ""

# Display summary
echo "🎉 Deployment Complete!"
echo "======================"
echo ""
echo "📋 Contract Addresses:"
echo "┌─────────────────────────┬──────────────────────────────────────────────────────────────────┐"
echo "│ Contract                │ Address                                                          │"
echo "├─────────────────────────┼──────────────────────────────────────────────────────────────────┤"
echo "│ Hancoin Token (HNXZ)    │ $TOKEN_ADDRESS │"
echo "│ Paymaster               │ $PAYMASTER_ADDRESS │"
echo "│ Loan Contract           │ $LOAN_ADDRESS │"
echo "│ Escrow Contract         │ $ESCROW_ADDRESS │"
echo "│ Swap Contract           │ $SWAP_ADDRESS │"
echo "│ Credit Card Simulator   │ $CREDIT_CARD_ADDRESS │"
echo "└─────────────────────────┴──────────────────────────────────────────────────────────────────┘"
echo ""
echo "📝 Next Steps:"
echo "1. Update your frontend with these contract addresses"
echo "2. Test contract interactions using the provided scripts"
echo "3. Add liquidity to swap pairs for DEX functionality"
echo "4. Configure additional paymasters if needed"
echo ""
echo "🔗 Useful Commands:"
echo "# Check token balance:"
echo "starkli call $TOKEN_ADDRESS balance_of <address>"
echo ""
echo "# Get loan details:"
echo "starkli call $LOAN_ADDRESS get_loan <loan_id>"
echo ""
echo "# Check escrow status:"
echo "starkli call $ESCROW_ADDRESS get_escrow_status <order_id>"
echo ""
echo "# Get swap quote:"
echo "starkli call $SWAP_ADDRESS get_swap_quote <token_in> <token_out> <amount>"
echo ""
echo "🚀 Homebase deployment successful!"