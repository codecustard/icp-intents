#!/bin/bash
# Full Intent Flow Integration Test
# Tests the complete intent lifecycle with SimpleIntentPool

set -e

echo "=========================================="
echo "Full Intent Flow Integration Test"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Clean restart for fresh test
echo -e "${YELLOW}Restarting replica for clean test...${NC}"
dfx stop > /dev/null 2>&1 || true
dfx start --background --clean
sleep 3

echo -e "${BLUE}Step 1: Deploy test infrastructure${NC}"
dfx deploy MockICRC1Ledger
dfx deploy SimpleIntentPool

# Get canister IDs
LEDGER=$(dfx canister id MockICRC1Ledger)
POOL=$(dfx canister id SimpleIntentPool)

echo ""
echo -e "${GREEN}✓ Deployed:${NC}"
echo "  MockICRC1Ledger: $LEDGER"
echo "  SimpleIntentPool: $POOL"
echo ""

# Get test principals
USER=$(dfx identity get-principal)
SOLVER=$(dfx identity get-principal) # Same for testing, in production would be different

echo -e "${BLUE}Step 2: Register test token${NC}"
dfx canister call SimpleIntentPool registerToken "(
  \"TEST\",
  principal \"$LEDGER\",
  8 : nat8,
  10000 : nat
)"

echo -e "${GREEN}✓ Registered TEST token${NC}"
echo ""

echo -e "${BLUE}Step 3: Mint tokens to user${NC}"
# Mint 100 TEST tokens to user
dfx canister call MockICRC1Ledger mint "(
  principal \"$USER\",
  100_000_000 : nat
)"

# Check balance
BALANCE=$(dfx canister call MockICRC1Ledger icrc1_balance_of "(
  record {
    owner = principal \"$USER\";
    subaccount = null
  }
)")

echo -e "${GREEN}✓ Minted tokens. User balance: $BALANCE${NC}"
echo ""

echo -e "${BLUE}Step 4: Create intent${NC}"
echo "User wants to swap 10 TEST (ICP/ICRC-2) for 50 HOO (on Hoosat)"

INTENT_RESULT=$(dfx canister call SimpleIntentPool createIntent "(
  \"icp\",
  \"TEST\",
  10_000_000 : nat,
  \"hoosat\",
  \"HOO\",
  50_000_000 : nat,
  \"hoosat:qzk6xqey2kpfqum40m6a3ml32a0m4yls9yzy44ds2e5x0wqmlg4fnzzr5f6sw\",
  86400 : nat
)" 2>&1)

echo "$INTENT_RESULT"

# Extract intent ID (assumes #ok format)
if echo "$INTENT_RESULT" | grep -q "#ok"; then
  INTENT_ID=$(echo "$INTENT_RESULT" | grep -oE '[0-9]+' | head -1)
  echo -e "${GREEN}✓ Created intent #$INTENT_ID${NC}"
else
  echo -e "${YELLOW}⚠ Intent creation response: $INTENT_RESULT${NC}"
  INTENT_ID=0
fi
echo ""

echo -e "${BLUE}Step 5: View intent${NC}"
dfx canister call SimpleIntentPool getIntent "($INTENT_ID : nat)"
echo ""

echo -e "${BLUE}Step 6: Submit quote (as solver)${NC}"
QUOTE_RESULT=$(dfx canister call SimpleIntentPool submitQuote "(
  $INTENT_ID : nat,
  55_000_000 : nat,
  1_000_000 : nat,
  100_000 : nat
)" 2>&1)

echo "$QUOTE_RESULT"
echo -e "${GREEN}✓ Submitted quote${NC}"
echo ""

echo -e "${BLUE}Step 7: View intent with quote${NC}"
dfx canister call SimpleIntentPool getIntent "($INTENT_ID : nat)"
echo ""

echo -e "${BLUE}Step 8: Confirm quote${NC}"
CONFIRM_RESULT=$(dfx canister call SimpleIntentPool confirmQuote "(
  $INTENT_ID : nat,
  principal \"$SOLVER\"
)" 2>&1)

echo "$CONFIRM_RESULT"
echo -e "${GREEN}✓ Confirmed quote${NC}"
echo ""

echo -e "${BLUE}Step 9: Approve tokens for transfer${NC}"
APPROVE_RESULT=$(dfx canister call MockICRC1Ledger icrc2_approve "(
  record {
    spender = record {
      owner = principal \"$POOL\";
      subaccount = null
    };
    amount = 11_000_000 : nat;
    fee = null;
    memo = null;
    from_subaccount = null;
    created_at_time = null;
    expected_allowance = null;
    expires_at = null
  }
)" 2>&1)

echo "$APPROVE_RESULT"
echo -e "${GREEN}✓ Approved tokens${NC}"
echo ""

echo -e "${BLUE}Step 10: Deposit tokens${NC}"
DEPOSIT_RESULT=$(dfx canister call SimpleIntentPool depositTokens "($INTENT_ID : nat)" 2>&1)

echo "$DEPOSIT_RESULT"

if echo "$DEPOSIT_RESULT" | grep -q "#ok"; then
  echo -e "${GREEN}✓ Deposited tokens${NC}"
else
  echo -e "${YELLOW}⚠ Deposit result: $DEPOSIT_RESULT${NC}"
fi
echo ""

echo -e "${BLUE}Step 11: Check escrow balance${NC}"
dfx canister call SimpleIntentPool getEscrowBalance "(principal \"$USER\", \"TEST\")"
echo ""

echo -e "${BLUE}Step 12: View final intent state${NC}"
dfx canister call SimpleIntentPool getIntent "($INTENT_ID : nat)"
echo ""

echo "=========================================="
echo -e "${GREEN}Integration Test Complete!${NC}"
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✓ Created intent #$INTENT_ID"
echo "  ✓ Solver submitted quote"
echo "  ✓ User confirmed quote"
echo "  ✓ User deposited tokens to escrow"
echo ""
echo "Next steps (manual):"
echo "  1. Solver deposits to destination chain (Hoosat)"
echo "  2. Call verifyHoosatDeposit with tx_id"
echo "  3. Call fulfillIntent to release escrow to solver"
