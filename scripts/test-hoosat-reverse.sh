#!/bin/bash
# Test script for Hoosat → ICP reverse flow
# User deposits Hoosat, solver provides ICP, canister releases Hoosat to solver

set -e

echo "========================================="
echo "Hoosat → ICP Reverse Flow Test"
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

# Step 1: Setup - Solver needs ICP tokens to provide
echo "🔧 Step 1: Setup (solver has ICP tokens ready)..."
dfx canister call BasicIntentCanister registerToken "(\"TST\", principal \"$LEDGER\")" > /dev/null 2>&1 || true
echo "  ✓ Registered TST token"

# Mint tokens to solver (simulating solver liquidity)
dfx canister call MockICRC1Ledger mint "(principal \"$PRINCIPAL\", 100_000_000 : nat)" > /dev/null
echo "  ✓ Minted 100M TST to solver"
echo ""

# Step 2: Create Hoosat → ICP intent
echo "💡 Step 2: User creates Hoosat → ICP intent..."
echo "  (User wants to sell Hoosat, receive ICP)"
echo ""

DEADLINE=$(($(date +%s) + 86400))
DEADLINE_NS=$((DEADLINE * 1000000000))

# Get solver's ICP address for receiving tokens
SOLVER_ICP_ADDRESS="$PRINCIPAL"

RESULT=$(dfx canister call BasicIntentCanister postIntent "(record {
  source = record {
    chain = \"hoosat\";
    chain_id = null;
    token = \"native\";
    network = \"testnet\";
  };
  destination = record {
    chain = \"icp\";
    chain_id = null;
    token = \"TST\";
    network = \"mainnet\";
  };
  dest_recipient = \"$SOLVER_ICP_ADDRESS\";
  source_amount = 2_000_000 : nat;
  min_output = 1_000_000 : nat;
  deadline = ${DEADLINE_NS} : int;
  custom_rpc_urls = null;
  verification_hints = null;
  metadata = null;
})")

INTENT_ID=$(echo "$RESULT" | grep -oE '[0-9]+ : nat' | grep -oE '[0-9]+')
echo "  ✓ Intent #$INTENT_ID created"
echo ""

# Step 3: Solver submits quote to provide ICP
echo "💰 Step 3: Solver submits quote..."
echo "  (Solver needs to provide their Hoosat address to receive funds)"
echo ""
read -p "  📝 Enter solver's Hoosat address: " SOLVER_HOOSAT_ADDRESS
echo ""

EXPIRY=$(($(date +%s) + 3600))
EXPIRY_NS=$((EXPIRY * 1000000000))

dfx canister call BasicIntentCanister submitQuote "(record {
  intent_id = $INTENT_ID : nat;
  output_amount = 2_000_000 : nat;
  fee = 10_000 : nat;
  expiry = ${EXPIRY_NS} : int;
  solver_dest_address = opt \"$SOLVER_HOOSAT_ADDRESS\";
})" > /dev/null
echo "  ✓ Quote submitted (solver offers 2M TST for 100M HTN)"
echo "  ✓ Solver will receive Hoosat at: $SOLVER_HOOSAT_ADDRESS"
echo ""

# Step 4: User confirms quote
echo "🔐 Step 4: User confirms quote..."
RESULT=$(dfx canister call BasicIntentCanister confirmQuote "($INTENT_ID : nat, 0 : nat)")
echo ""
echo "📍 Confirmation Response:"
echo "$RESULT"
echo ""

# Extract Hoosat address for USER to deposit to
DEPOSIT_ADDRESS=$(echo "$RESULT" | grep -oE '[Hh]oosat:[a-z0-9]+')
if [ -z "$DEPOSIT_ADDRESS" ]; then
  echo "❌ Failed to extract Hoosat deposit address"
  exit 1
fi

echo "  ✓ Hoosat Deposit Address (for user): $DEPOSIT_ADDRESS"
echo ""

# Step 5: User sends Hoosat to deposit address
echo "💸 Step 5: User deposits Hoosat"
echo ""
echo "  📍 Deposit Address: $DEPOSIT_ADDRESS"
echo "  💰 Expected Amount: 2,000,000 hootas (2 HTN)"
echo ""
echo "  Please send Hoosat to this address from your wallet"
echo ""
read -p "  ⏸  Press Enter after sending the transaction..."
echo ""
read -p "  📝 Enter transaction hash: " USER_TX_HASH
echo ""

# Step 6: Release Hoosat to solver (verifies, builds, broadcasts, fulfills)
echo "🚀 Step 6: Release Hoosat to solver..."
echo "  This will:"
echo "    1. Verify user's Hoosat deposit (verifyUTXO)"
echo "    2. Build signed Hoosat transaction"
echo "    3. Broadcast transaction to Hoosat network"
echo "    4. Mark intent as fulfilled"
echo ""

RESULT=$(dfx canister call BasicIntentCanister releaseHoosatToSolver "($INTENT_ID : nat, \"$USER_TX_HASH\")" 2>&1)

echo ""
if echo "$RESULT" | grep -q "variant { ok"; then
  # Extract tx hash from result
  BROADCAST_TX_HASH=$(echo "$RESULT" | grep -oE '[a-fA-F0-9]{64}' | head -1)

  echo "  ✓ User's Hoosat deposit verified!"
  echo "  ✓ Hoosat transaction built and signed!"
  echo "  ✓ Transaction broadcast to network!"
  echo "  ✓ Intent marked as fulfilled!"
  echo ""
  echo "  📋 Broadcast Transaction Hash: $BROADCAST_TX_HASH"
  echo ""

  # Show final intent state
  echo "📊 Final Intent State:"
  dfx canister call BasicIntentCanister getIntent "($INTENT_ID : nat)" | grep -E "(status|solver_tx_hash|verified_at)"
  echo ""

  echo "========================================="
  echo "✅ REVERSE FLOW TEST PASSED"
  echo "========================================="
  echo ""
  echo "Successfully completed:"
  echo "  ✓ Hoosat → ICP intent creation"
  echo "  ✓ Generated Hoosat deposit address for user"
  echo "  ✓ Verified user's Hoosat deposit via API"
  echo "  ✓ Built and signed Hoosat transaction"
  echo "  ✓ Broadcast Hoosat transaction to network"
  echo "  ✓ Intent fulfillment complete"
  echo ""
  echo "Verify on Hoosat Explorer:"
  echo "  https://explorer.hoosat.fi/txs/$BROADCAST_TX_HASH"
  exit 0
else
  echo "  ✗ Release failed:"
  echo "$RESULT"
  echo ""
  echo "Possible reasons:"
  echo "  • User's Hoosat transaction not confirmed yet"
  echo "  • Transaction hash incorrect"
  echo "  • Amount sent is less than expected"
  echo "  • Solver didn't provide destination address"
  echo "  • Transaction building/signing failed"
  echo "  • Broadcast to Hoosat network failed"
  echo ""
  echo "========================================="
  echo "❌ REVERSE FLOW TEST FAILED"
  echo "========================================="
  exit 1
fi
