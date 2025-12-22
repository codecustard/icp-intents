#!/bin/bash
# Test script for complete intent flow with EVM verification
# This tests the full cross-chain intent system locally

set -e

echo "========================================="
echo "ICP Intents - Full Flow Test"
echo "========================================="
echo ""

# Get canister IDs
BASIC_CANISTER=$(dfx canister id BasicIntentCanister)
LEDGER=$(dfx canister id MockICRC1Ledger)
PRINCIPAL=$(dfx identity get-principal)

# Check if Alchemy API key is provided
if [ -z "$ALCHEMY_API_KEY" ]; then
  echo "ERROR: Please set ALCHEMY_API_KEY environment variable"
  echo "Example: export ALCHEMY_API_KEY='your-key-here'"
  exit 1
fi

echo "📋 Configuration:"
echo "  BasicIntentCanister: $BASIC_CANISTER"
echo "  MockICRC1Ledger: $LEDGER"
echo "  User Principal: $PRINCIPAL"
echo "  Alchemy API Key: ${ALCHEMY_API_KEY:0:10}..."
echo ""

# Step 1: Setup
echo "🔧 Step 1: Setup token and balances..."
dfx canister call BasicIntentCanister registerToken "(\"TST\", principal \"$LEDGER\")" > /dev/null
echo "  ✓ Registered TST token"

dfx canister call MockICRC1Ledger mint "(principal \"$PRINCIPAL\", 100_000_000 : nat)" > /dev/null
echo "  ✓ Minted 100M TST tokens"

dfx canister call MockICRC1Ledger icrc2_approve "(record {
  spender = record { owner = principal \"$BASIC_CANISTER\"; subaccount = null };
  amount = 50_000_000 : nat
})" > /dev/null
echo "  ✓ Approved canister to spend tokens"

dfx canister call BasicIntentCanister depositEscrow "(\"TST\", 10_000_000 : nat)" > /dev/null
echo "  ✓ Deposited 10M TST to escrow"
echo ""

# Step 2: Create intent
echo "💡 Step 2: Create intent..."
DEADLINE=$(($(date +%s) + 86400))
DEADLINE_NS=$((DEADLINE * 1000000000))

RESULT=$(dfx canister call BasicIntentCanister postIntent "(record {
  source = record {
    chain = \"icp\";
    chain_id = null;
    token = \"TST\";
    network = \"mainnet\";
  };
  destination = record {
    chain = \"ethereum\";
    chain_id = opt (11155111 : nat);
    token = \"ETH\";
    network = \"sepolia\";
  };
  dest_recipient = \"0xcb645a676f278b4cd063f16621669910c0a332f5\";
  source_amount = 1_000_000 : nat;
  min_output = 500_000 : nat;
  deadline = ${DEADLINE_NS} : int;
  custom_rpc_urls = opt vec { \"https://eth-sepolia.g.alchemy.com/v2/${ALCHEMY_API_KEY}\" };
  verification_hints = null;
  metadata = null;
})")

INTENT_ID=$(echo "$RESULT" | grep -oE '[0-9]+ : nat' | grep -oE '[0-9]+')
echo "  ✓ Created intent #$INTENT_ID"
echo ""

# Step 3: Submit quote
echo "💰 Step 3: Submit quote..."
EXPIRY=$(($(date +%s) + 3600))
EXPIRY_NS=$((EXPIRY * 1000000000))

dfx canister call BasicIntentCanister submitQuote "(record {
  intent_id = $INTENT_ID : nat;
  output_amount = 600_000 : nat;
  fee = 50_000 : nat;
  expiry = ${EXPIRY_NS} : int;
})" > /dev/null
echo "  ✓ Submitted quote"
echo ""

# Step 4: Confirm quote (lock escrow, generate deposit address)
echo "🔒 Step 4: Confirm quote..."
RESULT=$(dfx canister call BasicIntentCanister confirmQuote "($INTENT_ID : nat, 0 : nat)")
DEPOSIT_ADDRESS=$(echo "$RESULT" | grep -oE '0x[a-fA-F0-9]{40}')
echo "  ✓ Locked escrow"
echo "  ✓ Generated deposit address: $DEPOSIT_ADDRESS"
echo ""

# Step 5: Wait for user to send ETH
echo "💸 Step 5: Send Sepolia ETH to deposit address"
echo ""
echo "  📍 Deposit Address: $DEPOSIT_ADDRESS"
echo "  💰 Expected Amount: 0.0006 ETH (600,000 wei)"
echo "  ℹ️  Amount doesn't need to be exact - any amount will be recorded"
echo ""
echo "  🌐 Get free Sepolia ETH: https://cloud.google.com/application/web3/faucet/ethereum/sepolia"
echo "  🌐 Or use: https://sepolia-faucet.pk910.de/"
echo ""
read -p "  ⏸  Press Enter after sending the transaction..."
echo ""
read -p "  📝 Enter transaction hash (0x...): " TX_HASH
echo ""

# Step 6: Claim fulfillment (verify and release)
echo "✅ Step 6: Claim fulfillment..."
RESULT=$(dfx canister call BasicIntentCanister claimFulfillment "($INTENT_ID : nat, opt \"$TX_HASH\")")

if echo "$RESULT" | grep -q "variant { ok }"; then
  echo "  ✓ Verification successful!"
  echo "  ✓ Escrow released to solver"
  echo ""

  # Show final intent state
  echo "📊 Final Intent State:"
  dfx canister call BasicIntentCanister getIntent "($INTENT_ID : nat)" | grep -E "(status|solver_tx_hash|verified_at)"
  echo ""

  echo "========================================="
  echo "✅ TEST PASSED - Intent flow complete!"
  echo "========================================="
else
  echo "  ✗ Verification failed:"
  echo "$RESULT"
  echo ""
  echo "========================================="
  echo "❌ TEST FAILED"
  echo "========================================="
  exit 1
fi
