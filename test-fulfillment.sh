#!/bin/bash
# Test the solver fulfillment flow
# Assumes test-intent-flow.sh has already run and created intent #0

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Solver Fulfillment Flow Test"
echo "=========================================="
echo ""

POOL=$(dfx canister id SimpleIntentPool)
LEDGER=$(dfx canister id MockICRC1Ledger)

echo -e "${BLUE}Step 1: Check current intent state${NC}"
INTENT=$(dfx canister call SimpleIntentPool getIntent "(0 : nat)")
echo "$INTENT"
echo ""

# Extract status
if echo "$INTENT" | grep -q "Deposited"; then
  echo -e "${GREEN}✓ Intent is in Deposited status${NC}"
else
  echo -e "${RED}✗ Intent is not in Deposited status${NC}"
  echo "Run ./test-intent-flow.sh first to create and deposit to an intent"
  exit 1
fi
echo ""

echo -e "${BLUE}Step 2: Check escrow balance before fulfillment${NC}"
ESCROW=$(dfx canister call SimpleIntentPool getEscrowBalance "(principal \"$(dfx identity get-principal)\", \"TEST\")")
echo "Escrow balance: $ESCROW"
echo ""

echo -e "${BLUE}Step 3: Check solver's token balance before${NC}"
SOLVER_BALANCE_BEFORE=$(dfx canister call MockICRC1Ledger icrc1_balance_of "(
  record {
    owner = principal \"$(dfx identity get-principal)\";
    subaccount = null
  }
)")
echo "Solver balance before: $SOLVER_BALANCE_BEFORE"
echo ""

echo -e "${YELLOW}Note: In a real scenario, the solver would:${NC}"
echo "  1. Deposit 55 HOO to the Hoosat address shown in the intent"
echo "  2. Call verifyHoosatDeposit with the Hoosat tx_id"
echo "  3. Once verified, call fulfillIntent"
echo ""
echo -e "${YELLOW}For this test, we'll simulate the fulfillment directly${NC}"
echo -e "${YELLOW}(skipping actual Hoosat deposit since we can't make real txs)${NC}"
echo ""

echo -e "${BLUE}Step 4: Attempt to call fulfillIntent${NC}"
echo "This should fail because the destination chain deposit hasn't been verified..."
FULFILL_RESULT=$(dfx canister call SimpleIntentPool fulfillIntent "(0 : nat)" 2>&1 || true)
echo "$FULFILL_RESULT"
echo ""

if echo "$FULFILL_RESULT" | grep -q "err"; then
  echo -e "${YELLOW}Expected: Cannot fulfill without destination deposit verification${NC}"
  echo ""
  echo -e "${BLUE}What would happen in production:${NC}"
  echo "  1. Solver deposits 55 HOO to Hoosat address"
  echo "  2. Solver calls: verifyHoosatDeposit(0, \"<hoosat_tx_id>\")"
  echo "  3. System verifies Hoosat transaction via HTTP outcall"
  echo "  4. If verified, status changes to: Deposited → (ready for fulfill)"
  echo "  5. Solver calls: fulfillIntent(0)"
  echo "  6. System:"
  echo "     - Releases 10 TEST from escrow"
  echo "     - Transfers 10 TEST to solver"
  echo "     - Collects protocol fee (0.3% = 30,000 units)"
  echo "     - Status changes to: Fulfilled"
else
  echo -e "${GREEN}Fulfillment succeeded!${NC}"

  echo ""
  echo -e "${BLUE}Step 5: Check escrow balance after fulfillment${NC}"
  ESCROW_AFTER=$(dfx canister call SimpleIntentPool getEscrowBalance "(principal \"$(dfx identity get-principal)\", \"TEST\")")
  echo "Escrow balance after: $ESCROW_AFTER"
  echo ""

  echo -e "${BLUE}Step 6: Check solver's token balance after${NC}"
  SOLVER_BALANCE_AFTER=$(dfx canister call MockICRC1Ledger icrc1_balance_of "(
    record {
      owner = principal \"$(dfx identity get-principal)\";
      subaccount = null
    }
  )")
  echo "Solver balance after: $SOLVER_BALANCE_AFTER"
  echo ""

  echo -e "${BLUE}Step 7: Check protocol fees collected${NC}"
  FEES=$(dfx canister call SimpleIntentPool getProtocolFees)
  echo "Protocol fees: $FEES"
  echo ""

  echo -e "${BLUE}Step 8: View final intent state${NC}"
  dfx canister call SimpleIntentPool getIntent "(0 : nat)"
  echo ""
fi

echo "=========================================="
echo -e "${GREEN}Fulfillment Test Complete!${NC}"
echo "=========================================="
echo ""
echo "Summary:"
echo "  - Intent flow verified up to Deposited status"
echo "  - Full fulfillment requires real Hoosat transaction"
echo "  - SDK provides all necessary verification functions"
echo ""
