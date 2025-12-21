# Local Testing Guide

Guide for testing the ICP Intents library locally with mock tokens.

## Quick Start

```bash
# Run the automated setup script
./scripts/test-local.sh
```

This will:
1. Start local dfx replica
2. Deploy MockICRC1Ledger (test token)
3. Deploy BasicIntentCanister
4. Register the test token
5. Mint 1B test tokens to your account

## Manual Testing

### 1. Deploy Canisters

```bash
dfx start --clean --background
dfx deploy MockICRC1Ledger
dfx deploy BasicIntentCanister
```

### 2. Register Token

```bash
# Get ledger canister ID
LEDGER_ID=$(dfx canister id MockICRC1Ledger)

# Register token with intent canister
dfx canister call BasicIntentCanister registerToken "(\"TST\", principal \"$LEDGER_ID\")"
```

### 3. Mint Test Tokens

```bash
# Mint tokens to yourself
PRINCIPAL=$(dfx identity get-principal)
dfx canister call MockICRC1Ledger mint "(principal \"$PRINCIPAL\", 1_000_000_000)"
```

### 4. Test Token Transfers

#### Check Balance
```bash
dfx canister call MockICRC1Ledger icrc1_balance_of "(record {
  owner = principal \"$(dfx identity get-principal)\";
  subaccount = null
})"
```

#### Deposit to Escrow
```bash
# Deposit 1M TST tokens
dfx canister call BasicIntentCanister depositEscrow "(\"TST\", 1_000_000)"

# Check escrow balance
dfx canister call BasicIntentCanister getEscrowBalance "(\"TST\")"
```

#### Withdraw from Escrow
```bash
dfx canister call BasicIntentCanister withdrawEscrow "(\"TST\", 500_000)"
```

### 5. Test Full Intent Flow

#### Post an Intent
```bash
dfx canister call BasicIntentCanister postIntent '(record {
  source = record {
    chain = "icp";
    chain_id = null;
    token = "TST";
    network = "mainnet"
  };
  destination = record {
    chain = "ethereum";
    chain_id = opt 11155111;
    token = "native";
    network = "sepolia"
  };
  dest_recipient = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0";
  source_amount = 1_000_000;
  min_output = 900_000;
  deadline = 9999999999000000000;
  custom_rpc_urls = null;
  verification_hints = null;
  metadata = null;
})'
```

#### Submit a Quote (as solver)
```bash
dfx canister call BasicIntentCanister submitQuote '(record {
  intent_id = 1;
  output_amount = 950_000;
  fee = 50_000;
  expiry = 9999999999000000000;
})'
```

#### Confirm Quote
```bash
# This locks escrow and returns a tECDSA deposit address
dfx canister call BasicIntentCanister confirmQuote '(1, 0)'
```

#### View Intents
```bash
# Get all intents
dfx canister call BasicIntentCanister getIntents '(0, 10)'

# Get your intents
dfx canister call BasicIntentCanister getMyIntents '()'
```

## MockICRC1Ledger Features

The mock ledger implements minimal ICRC-1 functionality:

### Transfer Tokens
```bash
dfx canister call MockICRC1Ledger icrc1_transfer '(record {
  from_subaccount = null;
  to = record {
    owner = principal "RECIPIENT_PRINCIPAL";
    subaccount = null
  };
  amount = 100_000;
  fee = null;
  memo = null;
  created_at_time = null;
})'
```

### Mint Tokens (Testing Only)
```bash
dfx canister call MockICRC1Ledger mint "(principal \"RECIPIENT\", 1_000_000)"
```

### Burn Tokens
```bash
dfx canister call MockICRC1Ledger burn "(100_000)"
```

### Get All Balances (Debug)
```bash
dfx canister call MockICRC1Ledger getAllBalances '()'
```

### Token Metadata
```bash
# Name
dfx canister call MockICRC1Ledger icrc1_name '()'

# Symbol
dfx canister call MockICRC1Ledger icrc1_symbol '()'

# Decimals
dfx canister call MockICRC1Ledger icrc1_decimals '()'

# Fee
dfx canister call MockICRC1Ledger icrc1_fee '()'

# Total Supply
dfx canister call MockICRC1Ledger icrc1_total_supply '()'
```

## Multi-User Testing

To test with multiple users (solver, user, etc.):

```bash
# Create new identity
dfx identity new solver
dfx identity use solver

# Get solver principal
SOLVER=$(dfx identity get-principal)

# Mint tokens to solver
dfx canister call MockICRC1Ledger mint "(principal \"$SOLVER\", 1_000_000_000)"

# Switch back to default
dfx identity use default
```

## Debugging

### View Canister Logs
```bash
# Intent canister logs
dfx canister logs BasicIntentCanister

# Ledger logs
dfx canister logs MockICRC1Ledger
```

### Check Canister Status
```bash
dfx canister status BasicIntentCanister
dfx canister status MockICRC1Ledger
```

### Reset Everything
```bash
dfx stop
dfx start --clean --background
./scripts/test-local.sh
```

## Differences from Production

The MockICRC1Ledger is simplified for testing:

**Missing features:**
- No archive nodes
- No transaction history
- No subaccount support (owner-only balances)
- No transaction deduplication
- No created_at_time validation
- Unrestricted minting (anyone can mint)

**For production testing**, use:
- Real ICRC-1 ledger: https://github.com/dfinity/ICRC-1
- ICP Ledger: https://internetcomputer.org/docs/current/developer-docs/integrations/ledger/

## Next Steps

Once local testing is complete:
1. Test on IC testnet with real ICRC-1 tokens
2. Deploy to IC mainnet
3. Register production token ledgers
4. Test with real cross-chain swaps on testnets (Sepolia, Base Sepolia)

---

**Note**: The mock ledger is for LOCAL TESTING ONLY. Never deploy to mainnet.
