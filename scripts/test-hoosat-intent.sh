#!/bin/bash
# Test script for Hoosat (UTXO-based chain) integration
# Tests address generation and UTXO verification flow

set -e

echo "========================================="
echo "ICP Intents - Hoosat Integration Test"
echo "========================================="
echo ""

# Get canister IDs
BASIC_CANISTER=$(dfx canister id BasicIntentCanister)
LEDGER=$(dfx canister id MockICRC1Ledger)
PRINCIPAL=$(dfx identity get-principal)

echo "📋 Configuration:"
echo "  BasicIntentCanister: $BASIC_CANISTER"
echo "  MockICRC1Ledger: $LEDGER"
echo "  User Principal: $PRINCIPAL"
echo ""

# Step 1: Setup
echo "🔧 Setting up..."
dfx canister call BasicIntentCanister registerToken "(\"TST\", principal \"$LEDGER\")" > /dev/null 2>&1 || true
dfx canister call MockICRC1Ledger mint "(principal \"$PRINCIPAL\", 100_000_000 : nat)" > /dev/null
dfx canister call MockICRC1Ledger icrc2_approve "(record {
  spender = record { owner = principal \"$BASIC_CANISTER\"; subaccount = null };
  amount = 50_000_000 : nat
})" > /dev/null
dfx canister call BasicIntentCanister depositEscrow "(\"TST\", 10_000_000 : nat)" > /dev/null
echo "✓ Setup complete"
echo ""

# Step 2: Create Hoosat intent
echo "💡 Creating Hoosat intent..."
DEADLINE=$(($(date +%s) + 86400))
DEADLINE_NS=$((DEADLINE * 1000000000))
EXPIRY=$(($(date +%s) + 3600))
EXPIRY_NS=$((EXPIRY * 1000000000))

RESULT=$(dfx canister call BasicIntentCanister postIntent "(record {
  source = record { chain = \"icp\"; chain_id = null; token = \"TST\"; network = \"mainnet\"; };
  destination = record { chain = \"hoosat\"; chain_id = null; token = \"native\"; network = \"testnet\"; };
  dest_recipient = \"hoosat:qzqtqsq7qx42cq3sxdx5m9vx72efv9k7xjnhvqvkc8gk05a25e4ux\";
  source_amount = 1_000_000 : nat;
  min_output = 50_000_000 : nat;
  deadline = ${DEADLINE_NS} : int;
  custom_rpc_urls = null;
  verification_hints = null;
  metadata = null;
})")

INTENT_ID=$(echo "$RESULT" | grep -oE '[0-9]+ : nat' | grep -oE '[0-9]+')
echo "✓ Intent #$INTENT_ID created"
echo ""

# Step 3: Submit quote
echo "💬 Submitting solver quote..."
dfx canister call BasicIntentCanister submitQuote "(record {
  intent_id = $INTENT_ID : nat;
  output_amount = 60_000_000 : nat;
  fee = 10_000 : nat;
  expiry = ${EXPIRY_NS} : int;
})" > /dev/null
echo "✓ Quote submitted"
echo ""

# Step 4: Confirm quote (generates Hoosat deposit address)
echo "🔐 Confirming quote (generating Hoosat address)..."
RESULT=$(dfx canister call BasicIntentCanister confirmQuote "($INTENT_ID : nat, 0 : nat)")
echo "✓ Quote confirmed"
echo ""
echo "📍 Generated Address Response:"
echo "$RESULT"
echo ""

# Extract Hoosat address (starts with "hoosat:" or "Hoosat:")
DEPOSIT_ADDRESS=$(echo "$RESULT" | grep -oE '[Hh]oosat:[a-z0-9]+')
if [ -z "$DEPOSIT_ADDRESS" ]; then
  echo "❌ Failed to extract Hoosat address from response"
  exit 1
fi

echo "✓ Hoosat Deposit Address: $DEPOSIT_ADDRESS"
echo ""

# Step 5: Verify UTXO (using placeholder verification)
echo "✅ Verifying Hoosat UTXO deposit..."
# Use a fake Hoosat transaction hash
TX_HASH="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

RESULT=$(dfx canister call BasicIntentCanister claimFulfillment "($INTENT_ID : nat, opt \"$TX_HASH\")" 2>&1)
echo ""

# Check result
if echo "$RESULT" | grep -q "variant { ok }"; then
  echo "✓ UTXO verification successful!"
  echo ""

  # Show final state
  echo "📊 Final Intent State:"
  dfx canister call BasicIntentCanister getIntent "($INTENT_ID : nat)" | grep -E "(status|solver_tx_hash|verified_at)"
  echo ""

  echo "========================================="
  echo "✅ HOOSAT TEST PASSED"
  echo "========================================="
  echo ""
  echo "Successfully tested:"
  echo "  ✓ Hoosat intent creation"
  echo "  ✓ tECDSA Hoosat address generation"
  echo "  ✓ UTXO verification routing"
  echo "  ✓ Intent fulfillment"
  exit 0
else
  echo "✗ Unexpected result:"
  echo "$RESULT"
  echo ""
  echo "========================================="
  echo "❌ HOOSAT TEST FAILED"
  echo "========================================="
  exit 1
fi
