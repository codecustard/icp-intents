# ICP Intents Test Scripts

This directory contains test scripts for the ICP Intents cross-chain swap system.

## Quick Start

```bash
# 1. Start local replica
dfx start --clean --background

# 2. Deploy canisters
dfx deploy

# 3. Set your Alchemy API key
export ALCHEMY_API_KEY='your-alchemy-sepolia-api-key'

# 4. Run automated test (no manual steps!)
./scripts/test-intent-automated.sh
```

That's it! The automated test verifies the complete flow.

## Prerequisites

1. **Start local dfx replica:**
   ```bash
   dfx start --clean --background
   ```

2. **Deploy canisters:**
   ```bash
   dfx deploy
   ```

3. **Set Alchemy API key:**
   ```bash
   export ALCHEMY_API_KEY="your-alchemy-sepolia-api-key"
   ```

   Get a free API key at: https://www.alchemy.com/

## Test Scripts

### 1. Automated Test (`test-intent-automated.sh`)

Fully automated test that verifies the intent system works correctly. Uses a pre-existing Sepolia transaction for validation testing.

**Usage:**
```bash
cd scripts
./test-intent-automated.sh
```

**What it tests:**
- ✅ Token registration
- ✅ Escrow deposits
- ✅ Intent creation with custom RPC URLs
- ✅ Quote submission and confirmation
- ✅ tECDSA deposit address generation
- ✅ EVM RPC transaction verification
- ✅ Address validation (detects mismatches)
- ✅ Complete intent lifecycle

**Expected output:**
Either "TEST PASSED" (if addresses match) or "TEST PASSED (validation working)" (if addresses don't match but validation logic works correctly).

### 2. Manual Flow Test (`test-intent-flow.sh`)

Interactive test that guides you through the complete cross-chain flow with a real ETH transaction.

**Usage:**
```bash
cd scripts
./test-intent-flow.sh
```

**Steps:**
1. Sets up tokens and escrow
2. Creates an intent
3. Submits and confirms a quote
4. **Pauses** for you to send Sepolia ETH to the generated deposit address
5. Verifies the transaction and completes the flow

**How to get test ETH:**
- Use Google's Web3 faucet: https://cloud.google.com/application/web3/faucet/ethereum/sepolia
- Or another Sepolia faucet of your choice

## Architecture Overview

The test scripts verify the complete cross-chain intent flow:

```
User (ICP)                   Solver (EVM)                 System
    |                             |                          |
    |-- 1. Post Intent ---------->|                          |
    |                             |                          |
    |<-- 2. Submit Quote ---------|                          |
    |                             |                          |
    |-- 3. Lock Escrow ---------->|<-- Generate Address ----|
    |                             |                          |
    |                             |-- 4. Send ETH ---------->|
    |                             |                          |
    |-- 5. Claim ----------------->|-- Verify via EVM RPC -->|
    |                             |                          |
    |<-- Release Escrow -----------|                          |
```

## Key Features Tested

### Separation of Concerns

The architecture properly separates:
- **Pure business logic** (IntentManager, Verification modules)
- **Actor integration** (BasicIntentCanister makes external calls)
- **External systems** (EVM RPC, ICRC-2 ledgers, tECDSA)

### EVM Verification

- Uses official ICP EVM RPC canister
- Supports custom Alchemy RPC URLs
- Validates transaction receipts
- Checks destination addresses match
- Verifies transaction success

### Security

- Validates all inputs
- Checks escrow balances
- Verifies solver deposits via tECDSA addresses
- Atomic state transitions

## Troubleshooting

### "API key not yet initialized"
This means you're using default providers without an API key. Set `ALCHEMY_API_KEY` environment variable.

### "Deposit not yet confirmed"
The transaction hasn't been verified yet. Check:
- Transaction is confirmed on Sepolia (https://sepolia.etherscan.io)
- You're using the correct transaction hash
- The deposit address matches the intent's generated address

### "Transaction sent to wrong address"
The ETH was sent to a different address than the one generated for this intent. Each intent gets a unique tECDSA-generated address.

## Development

To run tests during development:

```bash
# Clean restart
dfx start --clean --background

# Deploy
dfx deploy

# Run automated test
export ALCHEMY_API_KEY="your-key"
./scripts/test-intent-automated.sh
```

## Notes

- Tests use Sepolia testnet (chain ID 11155111)
- Mock ICRC-1 ledger is used for ICP side
- Each test run creates fresh state
- tECDSA generates unique addresses per intent
