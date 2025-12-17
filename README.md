# ICP Intents - Cross-Chain Intent-Based Swap Library

A Motoko library/SDK for building permissionless cross-chain intent-based swap systems on the Internet Computer Protocol (ICP). Inspired by NEAR Intents but optimized for ICP's unique capabilities including Chain Fusion and threshold ECDSA (tECDSA).

## 🚀 Features

- **Permissionless**: Anyone can post intents or act as a solver
- **Cross-Chain**: Support for EVM chains (Ethereum, Base) with extensibility for others
- **Secure Escrow**: Built-in escrow system for ICP and ICRC-1 tokens
- **tECDSA Integration**: Generates unique deposit addresses per intent using ICP's threshold ECDSA
- **EVM Verification**: Uses official EVM RPC canister for multi-provider consensus
- **Anti-Griefing**: 2-step flow (quote → confirm) prevents solver spam
- **Modular Design**: Use individual components or the full system
- **Extensible**: Built with hooks for custom chains and verification methods

## 📋 Table of Contents

- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Library Modules](#library-modules)
- [Usage Examples](#usage-examples)
- [Testing](#testing)
- [Deployment](#deployment)
- [Security Considerations](#security-considerations)
- [Extending the Library](#extending-the-library)

## 🏗 Architecture

### Flow Diagram

```
┌─────────┐              ┌─────────┐              ┌─────────┐
│  User   │              │ Canister│              │ Solver  │
└────┬────┘              └────┬────┘              └────┬────┘
     │                        │                        │
     │ 1. Post Intent         │                        │
     │───────────────────────>│                        │
     │                        │                        │
     │                        │   2. Submit Quote      │
     │                        │<───────────────────────│
     │                        │                        │
     │ 3. Confirm Quote       │                        │
     │───────────────────────>│                        │
     │                        │                        │
     │ <─── tECDSA Address ───│                        │
     │                        │                        │
     │     Share Address      │                        │
     │───────────────────────────────────────────────>│
     │                        │                        │
     │                        │   4. Deposit Funds     │
     │                        │    (on dest chain)     │
     │                        │<───────────────────────│
     │                        │                        │
     │                        │   5. Claim Fulfillment │
     │                        │<───────────────────────│
     │                        │                        │
     │                        │  Verify via EVM RPC    │
     │                        │         ✓              │
     │                        │                        │
     │                        │  Release Escrow        │
     │                        │─────────────────────> │
```

### Core Modules

1. **Types**: All type definitions
2. **Utils**: Validation and helper functions
3. **Escrow**: Token escrow management (standalone or integrated)
4. **TECDSA**: Threshold ECDSA address generation
5. **Verification**: Cross-chain deposit verification via EVM RPC
6. **IntentManager**: Orchestrates the full intent lifecycle

## 🚀 Quick Start

### Installation

Add to your `mops.toml`:

```toml
[dependencies]
base = "0.11.1"
map = "9.0.1"
sha3 = "0.1.1"
```

Then run:

```bash
mops install
```

### Basic Usage

```motoko
import IntentManager "mo:icp-intents-lib/IntentManager";
import Types "mo:icp-intents-lib/Types";
import Principal "mo:base/Principal";
import Time "mo:base/Time";

actor MyIntentDEX {
  // Initialize
  let config : Types.ProtocolConfig = {
    default_protocol_fee_bps = 30;  // 0.3%
    max_protocol_fee_bps = 100;
    min_intent_amount = 100_000;
    max_intent_lifetime = 7 * 24 * 60 * 60 * 1_000_000_000;
    admin = Principal.fromText("your-admin-principal");
    fee_collector = Principal.fromText("your-fee-collector");
    paused = false;
  };

  transient var state = IntentManager.init(
    config,
    /* tECDSA config */,
    /* verification config */,
    [1, 8453]  // Ethereum and Base
  );

  // User posts an intent
  public shared(msg) func postIntent(req: Types.CreateIntentRequest) : async Types.IntentResult<Nat> {
    await IntentManager.postIntent(state, msg.caller, req, Time.now())
  };
}
```

## 📚 Library Modules

### Types Module (`src/icp-intents-lib/Types.mo`)

All core type definitions. Import with:

```motoko
import Types "mo:icp-intents-lib/Types";
```

Key types:
- `Intent`: Main intent structure
- `Quote`: Solver quote
- `IntentStatus`: Lifecycle states
- `IntentError`: Comprehensive error types
- `IntentResult<T>`: Result type alias

### Utils Module (`src/icp-intents-lib/Utils.mo`)

Validation and utility functions:

```motoko
import Utils "mo:icp-intents-lib/Utils";

// Validate Ethereum address
let isValid = Utils.isValidEthAddress("0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0");

// Calculate protocol fee
let fee = Utils.calculateFee(1_000_000, 30);  // 0.3% fee

// Parse amounts with decimals
let amount = Utils.parseAmount("1.5", 8);  // ICP with e8s
```

### Escrow Module (`src/icp-intents-lib/Escrow.mo`)

Standalone escrow system (use in DEX or other apps):

```motoko
import Escrow "mo:icp-intents-lib/Escrow";

var escrowState = Escrow.init();

// Deposit
let result = Escrow.deposit(escrowState, user, "ICP", 1_000_000);

// Lock funds
ignore Escrow.lock(escrowState, user, "ICP", 500_000);

// Release (e.g., to solver)
ignore Escrow.release(escrowState, user, "ICP", 500_000);
```

### TECDSA Module (`src/icp-intents-lib/TECDSA.mo`)

Generate unique addresses for intents:

```motoko
import TECDSA "mo:icp-intents-lib/TECDSA";

let config = { key_name = "test_key_1" };
let address = await TECDSA.deriveAddress(config, intentId, userPrincipal);
// Returns: "0xabc123..."
```

**Note**: Uses Keccak256 from the [mops sha3 package](https://mops.one/sha3) for secure Ethereum address generation.

### Verification Module (`src/icp-intents-lib/Verification.mo`)

Verify deposits on EVM chains:

```motoko
import Verification "mo:icp-intents-lib/Verification";

// Verify native ETH
let result = await Verification.verifyNativeDeposit(
  config,
  "0xabc...",
  expectedAmount,
  1  // Ethereum mainnet
);
```

## 💡 Usage Examples

### Example 1: Complete Intent System

See `src/examples/BasicIntentCanister.mo` for a full implementation including:
- User intent posting
- Solver quoting
- Escrow management
- Background refund checks
- Admin functions

### Example 2: DEX Integration (Escrow Only)

```motoko
import Escrow "mo:icp-intents-lib/Escrow";

actor DEX {
  var escrow = Escrow.init();

  public shared(msg) func deposit(token: Text, amount: Nat) : async Types.IntentResult<()> {
    Escrow.deposit(escrow, msg.caller, token, amount)
  };

  public shared(msg) func swap(/* params */) : async Types.IntentResult<()> {
    // Lock tokens, execute swap, release
    ignore Escrow.lock(escrow, msg.caller, fromToken, amount);
    // ... swap logic ...
    ignore Escrow.release(escrow, msg.caller, fromToken, amount);
    #ok(())
  };
}
```

## 🧪 Testing

**💡 TIP**: Test on cheap networks first! See [TESTING.md](TESTING.md) for complete guide.

### Supported Networks (Built-in)

| Network | Chain ID | Cost | Use For |
|---------|----------|------|---------|
| Ethereum | 1 | Expensive | Production only |
| Base | 8453 | ~$0.01/tx | Low-cost testing |
| Sepolia | 11155111 | FREE | Development |
| Base Sepolia | 84532 | FREE | Development |

### Quick Test (Sepolia - FREE)

```bash
dfx start --clean --background
dfx deploy BasicIntentCanister

# Post intent on Sepolia testnet (FREE!)
dfx canister call BasicIntentCanister postIntent '(
  record {
    source_amount = 1_000_000;
    source_token = "ICP";
    dest_chain = "sepolia";        # Testnet
    dest_chain_id = 11155111;      # Sepolia
    dest_token_address = "native";
    dest_recipient = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0";
    min_output = 900_000;
    deadline = 9999999999000000000;
    custom_rpc_urls = null;
    verification_hints = null;
    metadata = null;
  }
)'

# Get free testnet ETH: https://sepoliafaucet.com/
```

### Unit Tests

See comprehensive test files:
- `test/Utils.test.mo` - Validation and utilities
- `test/Escrow.test.mo` - Escrow accounting
- `test/Integration.test.mo` - Full intent flow

For complete testing guide including Base, ERC20 tokens, and troubleshooting, see **[TESTING.md](TESTING.md)**.

## 🚀 Deployment

### 1. Local Deployment

```bash
dfx start --clean --background
mops install
dfx deploy
```

### 2. IC Mainnet

```bash
# Update tECDSA config to use "key_1"
# Update EVM RPC canister ID

dfx deploy --network ic --with-cycles 10000000000000
```

### 3. Configuration

Update in your canister:
- `key_name`: "test_key_1" (local/testnet) or "key_1" (mainnet)
- `evm_rpc_canister_id`: Official EVM RPC canister on mainnet
- `supportedChains`: Add your desired chain IDs

## 🔒 Security Considerations

### ⚠️ CRITICAL: Before Production

1. **Keccak256 Implementation**
   - ✅ Uses Keccak256 from [mops sha3 package](https://mops.one/sha3)
   - Generates secure Ethereum addresses from tECDSA public keys

2. **Unique Derivation Paths**
   - Never reuse tECDSA paths
   - Current: `[intentId, userPrincipal]`
   - Each intent gets unique address

3. **Verification Safety**
   - Wait for sufficient confirmations (12+ for Ethereum)
   - Use EVM RPC canister for multi-provider consensus
   - Handle chain reorgs gracefully

4. **Escrow Invariants**
   - Always: `balance = locked + available`
   - Comprehensive tests in `test/Escrow.test.mo`
   - Protected against underflow/overflow

5. **Upgrade Safety**
   - Use stable variables for persistent state
   - Test upgrades on testnet first
   - Implement pre/post upgrade hooks

### Security Audit Checklist

- [x] Keccak256 implementation
- [ ] Audit tECDSA derivation uniqueness
- [ ] Verify escrow accounting
- [ ] Test all error paths
- [ ] Load test (1000+ intents)
- [ ] Cycle cost analysis
- [ ] Upgrade testing
- [ ] External security audit

## 🔧 Extending the Library

### Adding EVM Chains

```motoko
let supportedChains = [
  1,      // Ethereum
  8453,   // Base
  42161,  // Arbitrum
  137,    // Polygon
];
```

### Adding Non-EVM Chains

Extend `Verification.mo`:

```motoko
public func verifyCustomChain(
  address: Text,
  amount: Nat,
  chainHints: Text
) : async VerificationResult {
  // Custom verification logic
}
```

### Custom Escrow

Extend `Escrow.mo` for NFTs or other assets.

## 📖 Project Structure

```
icp-intents/
├── src/
│   ├── icp-intents-lib/          # Reusable library modules
│   │   ├── Types.mo              # Core type definitions
│   │   ├── Utils.mo              # Utility functions
│   │   ├── Escrow.mo             # Escrow management
│   │   ├── TECDSA.mo             # Address generation
│   │   ├── Verification.mo       # Chain verification
│   │   └── IntentManager.mo      # Intent orchestration
│   ├── examples/
│   │   ├── BasicIntentCanister.mo  # Full example
│   │   └── BasicIntentCanister.did # Candid interface
│   └── icp-intents-backend/
│       └── main.mo               # Default entry point
├── test/
│   ├── Utils.test.mo             # Utils unit tests
│   ├── Escrow.test.mo            # Escrow unit tests
│   └── Integration.test.mo       # Integration tests
├── mops.toml                     # Package configuration
├── dfx.json                      # DFX configuration
└── README.md                     # This file
```

## 📝 API Reference

See `src/examples/BasicIntentCanister.did` for complete Candid interface.

## 🤝 Contributing

Contributions welcome! Priority areas:

- [ ] Real keccak256 implementation
- [ ] Bitcoin support
- [ ] Solana support
- [ ] Solver reputation system
- [ ] Gas estimation
- [ ] Intent batching

## 📄 License

MIT License

## 🙏 Acknowledgments

- Inspired by NEAR Intents
- Built on ICP Chain Fusion
- Uses official EVM RPC canister
- Motoko language and community

---

**Built for the Internet Computer ecosystem** 🚀
