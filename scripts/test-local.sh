#!/bin/bash

# Local Testing Script for ICP Intents
# This script sets up a complete local test environment with mock tokens

set -e

echo "🚀 Starting local ICP Intents test environment..."

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}📦 Step 1: Starting local replica...${NC}"
dfx start --clean --background

echo -e "${BLUE}📦 Step 2: Deploying canisters...${NC}"
dfx deploy MockICRC1Ledger
dfx deploy BasicIntentCanister

echo -e "${GREEN}✅ Canisters deployed!${NC}"

# Get canister IDs
LEDGER_ID=$(dfx canister id MockICRC1Ledger)
INTENT_ID=$(dfx canister id BasicIntentCanister)

echo ""
echo -e "${YELLOW}📋 Canister IDs:${NC}"
echo "  MockICRC1Ledger:      $LEDGER_ID"
echo "  BasicIntentCanister:  $INTENT_ID"
echo ""

# Get current principal
PRINCIPAL=$(dfx identity get-principal)
echo -e "${YELLOW}👤 Your Principal:${NC} $PRINCIPAL"
echo ""

echo -e "${BLUE}📦 Step 3: Setting up test environment...${NC}"

# Register the mock token with the intent canister
echo "  - Registering token 'TST' in BasicIntentCanister..."
dfx canister call BasicIntentCanister registerToken "(\"TST\", principal \"$LEDGER_ID\")"

# Mint some test tokens
echo "  - Minting 1,000,000,000 TST tokens to your account..."
dfx canister call MockICRC1Ledger mint "(principal \"$PRINCIPAL\", 1_000_000_000)"

# Check balance
BALANCE=$(dfx canister call MockICRC1Ledger icrc1_balance_of "(record { owner = principal \"$PRINCIPAL\"; subaccount = null })")
echo "  - Your TST balance: $BALANCE"

echo ""
echo -e "${GREEN}✅ Setup complete!${NC}"
echo ""
echo -e "${YELLOW}🧪 Quick Test Commands:${NC}"
echo ""
echo "1. Check your token balance:"
echo "   dfx canister call MockICRC1Ledger icrc1_balance_of '(record { owner = principal \"$PRINCIPAL\"; subaccount = null })'"
echo ""
echo "2. Deposit tokens to escrow (1,000,000 TST):"
echo "   dfx canister call BasicIntentCanister depositEscrow '(\"TST\", 1_000_000)'"
echo ""
echo "3. Check escrow balance:"
echo "   dfx canister call BasicIntentCanister getEscrowBalance '(\"TST\")'"
echo ""
echo "4. Post an intent:"
echo "   dfx canister call BasicIntentCanister postIntent '(record {"
echo "     source = record { chain = \"icp\"; chain_id = null; token = \"TST\"; network = \"mainnet\" };"
echo "     destination = record { chain = \"ethereum\"; chain_id = opt 11155111; token = \"native\"; network = \"sepolia\" };"
echo "     dest_recipient = \"0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0\";"
echo "     source_amount = 1_000_000;"
echo "     min_output = 900_000;"
echo "     deadline = 9999999999000000000;"
echo "     custom_rpc_urls = null;"
echo "     verification_hints = null;"
echo "     metadata = null;"
echo "   })'"
echo ""
echo "5. View all intents:"
echo "   dfx canister call BasicIntentCanister getIntents '(0, 10)'"
echo ""
echo "6. Get registered tokens:"
echo "   dfx canister call BasicIntentCanister getRegisteredTokens '()'"
echo ""
echo -e "${BLUE}📚 For more info, see TESTING.md${NC}"
echo ""
