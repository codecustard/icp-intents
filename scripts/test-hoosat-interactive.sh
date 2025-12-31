#!/bin/bash
# Interactive test script for Hoosat (UTXO-based chain) integration
# Allows manual verification of real Hoosat transactions

set -e

echo "========================================="
echo "ICP Intents - Hoosat Interactive Test"
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
echo "🔧 Step 1: Setup token and balances..."
dfx canister call BasicIntentCanister registerToken "(\"TST\", principal \"$LEDGER\")" > /dev/null 2>&1 || true
echo "  ✓ Registered TST token (or already exists)"

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

# Step 2: Create Hoosat intent
echo "💡 Step 2: Create Hoosat intent..."
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
echo "  ✓ Intent #$INTENT_ID created"
echo ""

# Step 3: Submit quote
echo "💰 Step 3: Submit solver quote..."
dfx canister call BasicIntentCanister submitQuote "(record {
  intent_id = $INTENT_ID : nat;
  output_amount = 60_000_000 : nat;
  fee = 10_000 : nat;
  expiry = ${EXPIRY_NS} : int;
  solver_dest_address = null;
})" > /dev/null
echo "  ✓ Quote submitted"
echo ""

# Step 4: Confirm quote (generates Hoosat deposit address)
echo "🔐 Step 4: Confirm quote and generate Hoosat address..."
RESULT=$(dfx canister call BasicIntentCanister confirmQuote "($INTENT_ID : nat, 0 : nat)")
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

echo "  ✓ Locked escrow"
echo "  ✓ Generated deposit address: $DEPOSIT_ADDRESS"
echo ""

# Step 5: Wait for user to send Hoosat
echo "💸 Step 5: Send Hoosat to deposit address"
echo ""
echo "  📍 Deposit Address: $DEPOSIT_ADDRESS"
echo "  💰 Expected Amount: 60,000,000 hootas (0.6 HOO)"
echo "  ℹ️  Amount doesn't need to be exact - any amount ≥ 60,000,000 will work"
echo ""
echo "  🌐 Hoosat Explorer: https://explorer.hoosat.fi/"
echo "  🌐 Hoosat Testnet Faucet: (check Hoosat Discord)"
echo ""
read -p "  ⏸  Press Enter after sending the transaction..."
echo ""
read -p "  📝 Enter transaction hash: " TX_HASH
echo ""

# Optionally ask for output index (usually 0 or 1)
echo "  ℹ️  Which output in the transaction sends to your deposit address?"
read -p "  📝 Enter output index (default 0): " OUTPUT_INDEX
OUTPUT_INDEX=${OUTPUT_INDEX:-0}
echo ""

# Step 6: Claim fulfillment (verify UTXO and release escrow)
echo "✅ Step 6: Verifying Hoosat UTXO and claiming fulfillment..."
echo ""
echo "  🔍 Calling Hoosat API to verify transaction..."
echo "  📋 Transaction: $TX_HASH"
echo "  📋 Address: $DEPOSIT_ADDRESS"
echo "  📋 Output Index: $OUTPUT_INDEX"
echo ""

RESULT=$(dfx canister call BasicIntentCanister claimFulfillment "($INTENT_ID : nat, opt \"$TX_HASH\")" 2>&1)

echo ""
if echo "$RESULT" | grep -q "variant { ok }"; then
  echo "  ✓ UTXO verification successful!"
  echo "  ✓ Escrow released to solver"
  echo ""

  # Show final intent state
  echo "📊 Final Intent State:"
  dfx canister call BasicIntentCanister getIntent "($INTENT_ID : nat)" | grep -E "(status|solver_tx_hash|verified_at)"
  echo ""

  echo "========================================="
  echo "✅ HOOSAT TEST PASSED"
  echo "========================================="
  echo ""
  echo "Successfully verified:"
  echo "  ✓ Hoosat intent creation"
  echo "  ✓ tECDSA Hoosat address generation"
  echo "  ✓ Real Hoosat UTXO verification via API"
  echo "  ✓ Intent fulfillment and escrow release"
  exit 0
else
  echo "  ✗ Verification failed:"
  echo "$RESULT"
  echo ""
  echo "Possible reasons:"
  echo "  • Transaction not yet confirmed (needs ~10 confirmations)"
  echo "  • Transaction hash incorrect"
  echo "  • Amount sent is less than expected"
  echo "  • Wrong output index"
  echo "  • Canister out of cycles for HTTP outcalls"
  echo ""
  echo "========================================="
  echo "❌ HOOSAT TEST FAILED"
  echo "========================================="
  exit 1
fi
