# ICP Intents - Testing Guide

Guide for testing the intent system on different networks without spending real money.

## Supported Networks

The `BasicIntentCanister` supports these networks:

| Network | Chain ID | Type | Fees | Best For |
|---------|----------|------|------|----------|
| Ethereum Mainnet | 1 | Mainnet | $$$ Expensive | Production only |
| Base | 8453 | Mainnet | $ Cheap | Production testing |
| Sepolia | 11155111 | Testnet | FREE | Development |
| Base Sepolia | 84532 | Testnet | FREE | Development |

## Recommended Testing Flow

### 1. Development Testing (FREE) - Use Sepolia

Get free testnet ETH:
- Sepolia Faucet: https://sepoliafaucet.com/
- Base Sepolia Faucet: https://www.alchemy.com/faucets/base-sepolia

**Post test intent on Sepolia:**

```bash
dfx canister call BasicIntentCanister postIntent '(
  record {
    source_amount = 1_000_000;
    source_token = "ICP";
    dest_chain = "sepolia";
    dest_chain_id = 11155111;
    dest_token_address = "native";
    dest_recipient = "0xYourSepoliaAddress";
    min_output = 900_000;
    deadline = 9999999999000000000;
    custom_rpc_urls = null;
    verification_hints = null;
    metadata = null;
  }
)'
```

### 2. Pre-Production Testing - Use Base

Base has very low fees (~$0.01 per transaction) while being a real mainnet.

**Post intent on Base:**

```bash
dfx canister call BasicIntentCanister postIntent '(
  record {
    source_amount = 1_000_000;
    source_token = "ICP";
    dest_chain = "base";
    dest_chain_id = 8453;
    dest_token_address = "native";
    dest_recipient = "0xYourBaseAddress";
    min_output = 900_000;
    deadline = 9999999999000000000;
    custom_rpc_urls = null;
    verification_hints = null;
    metadata = null;
  }
)'
```

### 3. Production - Use Ethereum Mainnet

Only after thorough testing on testnets and Base.

```bash
dfx canister call BasicIntentCanister postIntent '(
  record {
    source_amount = 1_000_000;
    source_token = "ICP";
    dest_chain = "ethereum";
    dest_chain_id = 1;
    dest_token_address = "native";
    dest_recipient = "0xYourEthAddress";
    min_output = 900_000;
    deadline = 9999999999000000000;
    custom_rpc_urls = null;
    verification_hints = null;
    metadata = null;
  }
)'
```

## Testing ERC20 Tokens

### Sepolia USDC (Test Token)

```bash
dfx canister call BasicIntentCanister postIntent '(
  record {
    source_amount = 1_000_000;
    source_token = "ICP";
    dest_chain = "sepolia";
    dest_chain_id = 11155111;
    dest_token_address = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238";  # Sepolia USDC
    dest_recipient = "0xYourAddress";
    min_output = 900_000;
    deadline = 9999999999000000000;
    custom_rpc_urls = null;
    verification_hints = null;
    metadata = null;
  }
)'
```

### Base USDC (Real Token)

```bash
# USDC on Base: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
```

## Complete Test Flow

### Step 1: Deploy Canister

```bash
dfx start --clean --background
dfx deploy BasicIntentCanister
```

### Step 2: Post Intent (Sepolia)

```bash
dfx canister call BasicIntentCanister postIntent '(
  record {
    source_amount = 1_000_000;
    source_token = "ICP";
    dest_chain = "sepolia";
    dest_chain_id = 11155111;
    dest_token_address = "native";
    dest_recipient = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0";
    min_output = 900_000;
    deadline = 9999999999000000000;
    custom_rpc_urls = null;
    verification_hints = null;
    metadata = null;
  }
)'
```

### Step 3: Submit Quote (as solver)

```bash
dfx canister call BasicIntentCanister submitQuote '(
  record {
    intent_id = 1;
    output_amount = 950_000;
    fee = 50_000;
    expiry = 9999999999000000000;
  }
)'
```

### Step 4: Get Intents

```bash
dfx canister call BasicIntentCanister getIntents '(0, 10)'
```

### Step 5: Confirm Quote (deposit escrow first!)

```bash
# First deposit escrow
dfx canister call BasicIntentCanister depositEscrow '("ICP", 1_050_000)'

# Then confirm quote
dfx canister call BasicIntentCanister confirmQuote '(1, 0)'
# Returns tECDSA-generated address like "0xabc123..."
```

### Step 6: Solver Deposits (off-chain)

Send ETH to the generated address on Sepolia using MetaMask.

### Step 7: Claim Fulfillment

```bash
dfx canister call BasicIntentCanister claimFulfillment '(1, null)'
```

## Network Comparison

### Cost Comparison (Approximate)

| Action | Ethereum | Base | Sepolia |
|--------|----------|------|---------|
| Native transfer | ~$5-20 | ~$0.01 | FREE |
| ERC20 transfer | ~$10-30 | ~$0.02 | FREE |
| Contract call | ~$15-50 | ~$0.05 | FREE |

### Confirmation Times

| Network | Avg Block Time | Recommended Confirmations |
|---------|----------------|---------------------------|
| Ethereum | ~12 seconds | 12 blocks (~2.5 min) |
| Base | ~2 seconds | 12 blocks (~24 sec) |
| Sepolia | ~12 seconds | 6 blocks (~1.5 min) |

## Troubleshooting

### Issue: "Invalid Chain" error

**Solution**: Make sure the chain ID matches a supported chain:
```motoko
supportedChains = [1, 8453, 11155111, 84532]
```

### Issue: Verification fails

**Causes**:
1. Not enough confirmations yet (wait longer)
2. Wrong deposit address
3. Amount too low
4. RPC provider issues

**Solution**: Check the transaction on block explorer:
- Sepolia: https://sepolia.etherscan.io/
- Base: https://basescan.org/
- Ethereum: https://etherscan.io/

### Issue: Out of cycles

**Solution**:
```bash
dfx ledger top-up CANISTER_ID --amount 5.0
```

## Getting Testnet Funds

### Sepolia ETH Faucets
- https://sepoliafaucet.com/
- https://www.alchemy.com/faucets/ethereum-sepolia
- https://faucet.quicknode.com/ethereum/sepolia

### Base Sepolia Faucets
- https://www.alchemy.com/faucets/base-sepolia
- Bridge from Sepolia: https://bridge.base.org/

## Best Practices

1. **Start with Sepolia** - Free testing, perfect for development
2. **Move to Base** - Low-cost real mainnet testing
3. **Final test on Ethereum** - Only after everything works
4. **Use small amounts** - Test with minimal funds first
5. **Monitor cycles** - Check canister status regularly

## Adding More Networks

Want to add Arbitrum, Polygon, or others? Just add the chain ID:

```motoko
transient let supportedChains : [Nat] = [
  1,        // Ethereum
  8453,     // Base
  42161,    // Arbitrum
  137,      // Polygon
  11155111, // Sepolia
  // ... add more
];
```

Chain IDs: https://chainlist.org/

---

**Remember**: Always test on testnets first! 🧪
