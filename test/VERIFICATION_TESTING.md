# Verification Testing Guide

This guide explains how to test the chain verification logic with real blockchain transactions.

## Overview

The `Verification.replica.test.mo` file contains integration tests that verify:
- Hoosat transaction verification with real RPC calls
- EVM transaction verification via the EVM RPC canister
- Confirmation counting logic
- Pending vs Success status transitions

## Prerequisites

1. **DFX running**: Start local replica with `dfx start --background`
2. **Real transaction data**: You need actual confirmed transactions to test against
3. **RPC access**:
   - Hoosat: Public RPC endpoint (e.g., `https://api.hoosat.fi/testnet`)
   - EVM: Access to EVM RPC canister (`7hfb6-caaaa-aaaar-qadga-cai`)

## How to Test

### Step 1: Get Real Transaction Data

**For Hoosat:**
1. Go to Hoosat block explorer (testnet or mainnet)
2. Find a confirmed transaction
3. Note down:
   - Transaction ID
   - Recipient address
   - Amount (in sompi)

**For EVM (Sepolia recommended):**
1. Go to https://sepolia.etherscan.io
2. Find a confirmed transaction
3. Note down:
   - Transaction hash (0x...)
   - To address (0x...)
   - Value (in wei)
   - Chain ID (11155111 for Sepolia)

### Step 2: Update Test File

Edit `test/Verification.replica.test.mo` and update the constants:

```motoko
// Hoosat section (mainnet)
let HOOSAT_RPC = "https://api.network.hoosat.fi";
let HOOSAT_TX_ID = "abc123..."; // Your tx ID from explorer
let HOOSAT_ADDRESS = "hoosat:qq..."; // Recipient address
let HOOSAT_AMOUNT = 100000000; // Amount in sompi

// EVM section (Sepolia testnet recommended)
let EVM_RPC_CANISTER = "7hfb6-caaaa-aaaar-qadga-cai"; // Official EVM RPC canister
let EVM_CHAIN_ID = 11155111; // 11155111 = Sepolia, 1 = Ethereum mainnet
let EVM_TX_HASH = "0xabc123..."; // Full tx hash from explorer
let EVM_TO_ADDRESS = "0x123..."; // Recipient address (lowercase)
let EVM_VALUE = 1000000000000000; // Amount in wei
```

### Step 3: Run Tests

```bash
# Run all verification tests
mops test Verification.replica

# Or run with dfx
dfx start --background
mops test Verification.replica
```

## What Gets Tested

### Hoosat Tests

1. **verify confirmed transaction returns Success**
   - Calls Hoosat RPC to fetch UTXO data
   - Fetches transaction details
   - Fetches block height
   - Calculates confirmations
   - Should return `#Success` with confirmation count

2. **verify with high min_confirmations returns Pending**
   - Uses impossibly high confirmation requirement (999999)
   - Should return `#Pending` status
   - Validates that pending logic works

### EVM Tests

1. **verify confirmed EVM transaction returns Success**
   - Calls EVM RPC canister
   - Fetches transaction receipt
   - Fetches transaction details for value
   - Fetches current block number
   - Calculates confirmations
   - Should return `#Success`

2. **verify with high min_confirmations returns Pending**
   - Tests pending state logic
   - Should return `#Pending`

## Expected Output

```
Test files:
• test/Verification.replica.test.mo

 ✓ verify confirmed Hoosat transaction
   Hoosat verification: #Success({ confirmations = 26_428; ... })
   ✓ Verified with 26_428 confirmations

 ✓ verify with high confirmation requirement returns Pending
   ✓ Correctly returned Pending

 ✓ verify confirmed EVM transaction
   EVM verification: #Success({ confirmations = 15; ... })
   ✓ Verified with 15 confirmations

 ✓ verify EVM with high confirmation requirement returns Pending
   ✓ Correctly returned Pending

PASS
Tests passed
Done in 30.00s, passed 4
```

## Manual Testing

You can also test individual transactions by updating the "Manual Verification Helpers" section and running just that test.

## Troubleshooting

**Test fails with "Insufficient cycles":**
- Increase cycles in the test setup
- Check HTTP outcall costs are properly budgeted

**Test fails with "HTTP request failed":**
- Verify RPC URL is accessible
- Check network connectivity
- Ensure dfx is running for local tests

**Test fails with "Transaction not found":**
- Verify transaction ID/hash is correct
- Ensure transaction is confirmed on-chain
- Check you're using the right network (testnet vs mainnet)

**Test returns #Failed("Address mismatch"):**
- Verify the recipient address matches exactly
- Check address format (hoosat: vs Hoosat:, lowercase 0x)

**Test returns #Failed("Insufficient amount"):**
- Verify the amount is in the correct unit (sompi for Hoosat, wei for EVM)
- Check the transaction value matches what you specified

## Example: Testing a Real Sepolia Transaction

```motoko
// Real example from Sepolia
let CHAIN_ID = 11155111;
let TX_HASH = "0x1234567890abcdef..."; // Get from Sepolia Etherscan
let TO_ADDRESS = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb"; // Lowercase
let VALUE = 1000000000000000; // 0.001 ETH

// Run test
mops test Verification.replica
```

The test will:
1. Call EVM RPC canister
2. Fetch receipt (confirms tx succeeded, status=1)
3. Fetch tx details (confirms value)
4. Fetch current block (calculates confirmations)
5. Return #Success with actual confirmation count
