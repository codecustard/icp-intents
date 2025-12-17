# ICP Intents - Architecture & Escrow Design

## Universal Chain Asset Design

The library now uses a **fully extensible** design that works for ANY blockchain combination.

### ChainAsset Type

```motoko
public type ChainAsset = {
  chain: Text;        // "icp", "ethereum", "base", "bitcoin", "solana"
  chain_id: ?Nat;     // For EVM: 1, 8453, 11155111, etc. (null for non-EVM)
  token: Text;        // "native", ERC20 address, or ICRC-1 canister ID
  network: Text;      // "mainnet", "testnet", "sepolia"
};
```

### Example Chain Assets

```motoko
// ICP native token (mainnet)
{
  chain = "icp";
  chain_id = null;
  token = "native";
  network = "mainnet";
}

// ETH on Sepolia testnet
{
  chain = "ethereum";
  chain_id = ?11155111;
  token = "native";
  network = "sepolia";
}

// USDC on Base mainnet
{
  chain = "ethereum";  // Base is EVM-compatible
  chain_id = ?8453;
  token = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";
  network = "mainnet";
}

// ICRC-1 token on ICP
{
  chain = "icp";
  chain_id = null;
  token = "ryjl3-tyaaa-aaaaa-aaaba-cai";  // Token canister ID
  network = "mainnet";
}

// Future: Bitcoin
{
  chain = "bitcoin";
  chain_id = null;
  token = "native";
  network = "mainnet";
}
```

## Supported Intent Directions

The architecture is **infinitely extensible**. Currently implemented:

### 1. ICP → EVM (e.g., ICP → ETH)
```motoko
source = { chain = "icp"; ... };
destination = { chain = "ethereum"; chain_id = ?1; ... };
```

### 2. EVM → ICP (e.g., ETH → ICP)  🆕 Coming soon
```motoko
source = { chain = "ethereum"; chain_id = ?1; ... };
destination = { chain = "icp"; ... };
```

### 3. Future: Any Chain Pair
```motoko
// BTC → ICP
source = { chain = "bitcoin"; ... };
destination = { chain = "icp"; ... };

// ICP → Solana
source = { chain = "icp"; ... };
destination = { chain = "solana"; ... };

// ETH → BTC (external bridge)
source = { chain = "ethereum"; ... };
destination = { chain = "bitcoin"; ... };
```

## Escrow Architecture

Different chains use different escrow strategies for optimal security and gas efficiency.

### ICP Escrow: **Shared Pool Per User**

```
HashMap<(Principal, Token), EscrowAccount>

User Alice:
├─ ICP Account
│  ├─ Total Balance: 10,000,000
│  ├─ Locked (Intent #1): 1,000,000
│  ├─ Locked (Intent #2): 2,000,000
│  └─ Available: 7,000,000
│
└─ ICRC-1 Token (ryjl3-tyaaa...)
   ├─ Total Balance: 5,000,000
   └─ Available: 5,000,000
```

**Why shared pool?**
- ✅ Users deposit once, use for multiple intents
- ✅ Gas efficient (no repeated deposits)
- ✅ Lock/unlock mechanism tracks per-intent allocation
- ✅ Safe: Locked funds can't be withdrawn

### EVM Escrow: **Unique Address Per Intent**

```
Intent #1 (ICP → ETH):
├─ derivationPath = [intentId: 1, user: Alice]
├─ Generated Address: 0xABC...123
└─ Usage: Solver deposits ETH here

Intent #2 (ETH → ICP):
├─ derivationPath = [intentId: 2, user: Bob]
├─ Generated Address: 0xDEF...456
└─ Usage: User deposits ETH here, canister later sends to solver

Intent #3 (ETH → ICP):
├─ derivationPath = [intentId: 3, user: Charlie]
├─ Generated Address: 0x789...ABC
└─ Usage: User deposits, canister sends to solver
```

**Why unique per intent?**
- ✅ Clear attribution (no ambiguity about which deposit is for which intent)
- ✅ Secure isolation (intents can't interfere)
- ✅ No amount collision (multiple intents with same amount OK)
- ✅ tECDSA derivation is free (just a function call)

## Complete Flow Examples

### ICP → ETH on Sepolia (Current)

```motoko
// 1. User posts intent
postIntent({
  source = { chain = "icp"; chain_id = null; token = "native"; network = "mainnet" };
  destination = { chain = "ethereum"; chain_id = ?11155111; token = "native"; network = "sepolia" };
  source_amount = 1_000_000;
  min_output = 900_000;
  dest_recipient = "0x742...";
  // ...
});

// 2. User deposits to ICP escrow (shared pool)
depositEscrow("ICP", 1_050_000);  // Adds to user's ICP balance

// 3. Solver submits quote
submitQuote({ intent_id = 1; output_amount = 950_000; fee = 50_000; ... });

// 4. User confirms → locks 1,050,000 from escrow → generates unique address
confirmQuote(1, 0);
// Returns: "0xABC...123" (unique for this intent)

// 5. Solver deposits 950,000+ ETH to 0xABC...123 on Sepolia

// 6. Canister verifies via EVM RPC, releases ICP to solver
claimFulfillment(1, null);
```

**Escrow state after step 4:**
```
User's ICP Account:
├─ Balance: 1,050,000
├─ Locked (Intent #1): 1,050,000
└─ Available: 0
```

### ETH → ICP (New - Bidirectional) 🆕

```motoko
// 1. User posts intent (offering ETH, wants ICP)
postIntent({
  source = { chain = "ethereum"; chain_id = ?11155111; token = "native"; network = "sepolia" };
  destination = { chain = "icp"; chain_id = null; token = "native"; network = "mainnet" };
  source_amount = 1_000_000;  // 1M wei
  min_output = 900_000;       // 900k ICP e8s
  dest_recipient = "user-principal-or-account-id";
  // ...
});

// 2. Canister generates unique ETH address for this intent
// Returns: "0xDEF...456"

// 3. User sends 1M wei to 0xDEF...456 on Sepolia (off-chain)

// 4. Solver quotes
submitQuote({ intent_id = 2; output_amount = 950_000; fee = 50_000; ... });

// 5. User confirms (or auto-confirmed when ETH detected)
confirmQuote(2, 0);

// 6. Solver deposits 950,000 ICP to canister
// (to a specific subaccount or with memo=intentId)

// 7. Canister verifies:
//    - ETH received at 0xDEF...456 ✅
//    - ICP received from solver ✅
//
// 8. Canister releases:
//    - ICP to user (from solver's deposit)
//    - ETH to solver (signs tx with tECDSA, sends from 0xDEF...456)
claimFulfillmentReverse(2);
```

**Key difference:**
- ICP→EVM: Canister verifies destination, releases source
- EVM→ICP: Canister holds source (ETH), verifies + signs to release

## Security Considerations

### ICP Escrow (Shared Pool)
- ✅ Lock before generating address
- ✅ Can't withdraw locked funds
- ✅ Refund unlocks automatically
- ✅ Invariant: `balance = locked + available`

### EVM Escrow (Unique Addresses)
- ✅ Each intent isolated
- ✅ Canister controls private key (tECDSA)
- ✅ Can verify deposits via EVM RPC
- ✅ Can send funds by signing transactions
- ⚠️ Gas management needed (canister needs ETH for gas)

### tECDSA Derivation Paths
```motoko
// Each intent gets unique path
derivationPath = [intentIdBlob, userPrincipalBlob]

// Intent #1, User Alice → 0xABC...
// Intent #2, User Alice → 0xDEF...  (different!)
// Intent #1, User Bob   → 0x123...  (different!)
```

**Critical:** Never reuse derivation paths!

## Gas Management for EVM→ICP

When sending ETH from canister addresses, the canister needs ETH for gas:

### Option 1: Deduct gas from intent amount
```motoko
// User sends: 1.0 ETH
// Canister sends to solver: 1.0 ETH - gas (e.g., 0.9999 ETH)
let gasEstimate = 21_000 * gasPrice;
let amountToSolver = depositedAmount - gasEstimate;
```

### Option 2: Separate gas pool
```motoko
// Canister maintains small ETH balance for gas
// Replenished from protocol fees
```

### Option 3: Solver pays gas
```motoko
// Solver provides gas in exchange for getting assets
// Canister doesn't need gas pool
```

## Adding New Chains

### Bitcoin Example

1. **Add verification module** (`VerificationBTC.mo`):
   ```motoko
   public func verifyBTCDeposit(
     address: Text,
     amount: Nat,
     txHash: Text
   ) : async VerificationResult {
     // Use BTC RPC or indexer
   }
   ```

2. **Add address generation** (if needed):
   ```motoko
   // For P2PKH: derive from tECDSA public key
   // For P2WPKH: use bech32 encoding
   ```

3. **Update IntentManager** with routing logic:
   ```motoko
   if (intent.source.chain == "bitcoin") {
     // Use BTC verification
   } else if (intent.source.chain == "ethereum") {
     // Use EVM verification
   }
   ```

That's it! The ChainAsset design makes it fully extensible.

## Summary

| Aspect | ICP | EVM | Other Chains |
|--------|-----|-----|--------------|
| Escrow Type | Shared pool per user | Unique address per intent | TBD per chain |
| Lock Mechanism | HashMap + lock/unlock | tECDSA derivation | Chain-specific |
| Verification | Balance check | EVM RPC | Chain-specific RPC |
| Release | Transfer from pool | Sign + broadcast tx | Chain-specific |

**Result:** Universal, extensible intent system that works for ANY blockchain! 🚀
