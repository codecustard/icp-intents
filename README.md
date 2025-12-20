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

### Multi-Pool Deployment Model

**This library is designed for permissionless, decentralized intent markets.**

Unlike traditional DEX designs with a single central pool, this library enables:

- **Multiple Intent Pool Canisters** - Anyone can deploy their own intent pool canister using this library
- **Permissionless Competition** - Pools compete on fees, service quality, and liquidity
- **Decentralized Market** - Solvers can scan all pools to find the best intents
- **Market-Driven Selection** - Users choose pools based on reputation, fees, and performance

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│              Decentralized Intent Market            │
│                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │ Intent Pool │  │ Intent Pool │  │ Intent Pool │ │
│  │  Canister A │  │  Canister B │  │  Canister C │ │
│  │ (0.3% fee)  │  │ (0.25% fee) │  │ (0.5% fee)  │ │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘ │
│         │                │                │         │
│         └────────────────┼────────────────┘         │
│                          │                          │
└──────────────────────────┼──────────────────────────┘
                           │
                    ┌──────▼──────┐
                    │   Solvers   │
                    │ (scan pools) │
                    └─────────────┘
```

**Benefits:**
- ✅ No single point of failure
- ✅ Competition drives down fees
- ✅ Innovation in pool features
- ✅ Censorship resistant

### Transfer-Agnostic Design

**Important**: This library focuses on **intent lifecycle management** and does NOT include token transfer logic.

**What the library provides:**
- Intent creation and management
- Quote submission and selection
- Escrow state tracking (lock/unlock)
- tECDSA address generation
- Cross-chain verification
- Event logging

**What integrators must add:**
- ICP/ICRC-1 token transfers
- Ledger integration
- Custom transfer logic
- Fee collection transfers

This design provides **maximum flexibility** - you can integrate with:
- ICRC-1 tokens
- ICP Ledger
- Custom token systems
- NFTs or other assets
- Any future token standard

See [Integration Patterns](#integration-patterns) for examples.

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

persistent actor MyIntentPool {
  // Initialize state with enhanced orthogonal persistence
  let config : Types.ProtocolConfig = {
    default_protocol_fee_bps = 30;  // 0.3%
    max_protocol_fee_bps = 100;
    min_intent_amount = 100_000;
    max_intent_lifetime = 7 * 24 * 60 * 60 * 1_000_000_000;
    max_active_intents = 1000;
    max_events = 100;
    admin = Principal.fromText("your-admin-principal");
    fee_collector = Principal.fromText("your-fee-collector");
    paused = false;
  };

  transient var state = IntentManager.init(
    config,
    { key_name = "key_1"; derivation_path = [] },  // tECDSA config
    { evm_rpc_canister_id = Principal.fromText("..."); min_confirmations = 12 },
    [1, 8453]  // Ethereum and Base
  );

  // User posts an intent
  public shared(msg) func postIntent(req: Types.CreateIntentRequest) : async Types.IntentResult<Nat> {
    await IntentManager.postIntent(state, msg.caller, req, Time.now())
  };

  // Note: You must add token transfer logic - see Integration Patterns section
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

### Example 1: Complete Intent Pool Canister

See `src/examples/BasicIntentCanister.mo` for a full implementation including:
- User intent posting
- Solver quoting
- Escrow management
- Background refund checks
- Admin functions

**Note**: This example is a starting point - you need to add actual token transfer logic.

### Example 2: Standalone Escrow (for DEX or other apps)

```motoko
import Escrow "mo:icp-intents-lib/Escrow";

persistent actor DEX {
  var escrow = Escrow.init();

  public shared(msg) func deposit(token: Text, amount: Nat) : async Types.IntentResult<()> {
    // Add your token transfer logic here (ICRC-1, ICP Ledger, etc.)
    // ...
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

## 🔌 Integration Patterns

Since this library is **transfer-agnostic**, you need to add token transfer logic. Here are common patterns:

### Pattern 1: ICRC-1 Token Integration

```motoko
import ICRC1 "mo:icrc1-mo/ICRC1";
import IntentManager "mo:icp-intents-lib/IntentManager";

persistent actor MyIntentPool {
  let icrc1Ledger = actor ("ryjl3-tyaaa-aaaaa-aaaba-cai") : ICRC1.Self;

  public shared(msg) func depositEscrow(token: Text, amount: Nat) : async Types.IntentResult<()> {
    // 1. Transfer tokens from user to canister
    let transferArgs = {
      from_subaccount = null;
      to = { owner = Principal.fromActor(this); subaccount = null };
      amount = amount;
      fee = null;
      memo = null;
      created_at_time = null;
    };

    let result = await icrc1Ledger.icrc1_transfer(transferArgs);

    switch (result) {
      case (#Ok(_)) {
        // 2. Credit user's escrow balance
        Escrow.deposit(state.escrow, msg.caller, token, amount)
      };
      case (#Err(e)) { #err(#TransferFailed) };
    };
  };

  // When releasing escrow to solver after fulfillment
  public func releaseFunds(solver: Principal, token: Text, amount: Nat) : async () {
    let transferArgs = {
      from_subaccount = null;
      to = { owner = solver; subaccount = null };
      amount = amount;
      fee = null;
      memo = null;
      created_at_time = null;
    };
    ignore await icrc1Ledger.icrc1_transfer(transferArgs);
  };
}
```

### Pattern 2: ICP Ledger Integration

```motoko
import Ledger "mo:icp-ledger-mo/Ledger";
import Types "mo:icp-ledger-mo/Types";

persistent actor MyIntentPool {
  let ledger = actor ("ryjl3-tyaaa-aaaaa-aaaba-cai") : Ledger.Self;

  public shared(msg) func depositICP(amount: Nat64) : async Types.IntentResult<()> {
    // 1. Transfer ICP from user to canister
    let transferArgs : Types.TransferArgs = {
      memo = 0;
      amount = { e8s = amount };
      fee = { e8s = 10_000 };
      from_subaccount = null;
      to = AccountIdentifier.fromPrincipal(Principal.fromActor(this), null);
      created_at_time = null;
    };

    let result = await ledger.transfer(transferArgs);

    switch (result) {
      case (#Ok(_)) {
        Escrow.deposit(state.escrow, msg.caller, "ICP", Nat64.toNat(amount))
      };
      case (#Err(_)) { #err(#TransferFailed) };
    };
  };
}
```

### Pattern 3: Custom Solver Payment

```motoko
// In your claimFulfillment implementation
public func claimFulfillment(intentId: Nat, txHash: ?Text) : async Types.IntentResult<()> {
  // 1. Verify the intent is fulfilled (library handles this)
  let verifyResult = await Verification.verifyDeposit(...);

  switch (verifyResult) {
    case (#ok(_)) {
      // 2. Get intent details
      let intent = IntentManager.getIntent(state, intentId);

      switch (intent) {
        case (?i) {
          // 3. Calculate amounts
          let solverAmount = i.source_amount;
          let protocolFee = Utils.calculateFee(i.source_amount, config.default_protocol_fee_bps);

          // 4. Release escrow (library tracks state)
          ignore Escrow.unlock(state.escrow, i.creator, "ICP", solverAmount + protocolFee);
          ignore Escrow.release(state.escrow, i.creator, "ICP", solverAmount + protocolFee);

          // 5. Transfer tokens (YOU implement this)
          await transferToSolver(i.selected_quote.solver, "ICP", solverAmount);
          await transferToFeeCollector(config.fee_collector, "ICP", protocolFee);

          #ok(())
        };
        case null { #err(#NotFound) };
      };
    };
    case (#err(e)) { #err(e) };
  };
}
```

### Pattern 4: Multi-Token Pool

```motoko
persistent actor MultiTokenPool {
  // Map token identifiers to their ledger canisters
  let tokenLedgers = HashMap.HashMap<Text, Principal>(10, Text.equal, Text.hash);

  public func registerToken(tokenId: Text, ledgerCanister: Principal) : async () {
    // Admin-only function
    tokenLedgers.put(tokenId, ledgerCanister);
  };

  public func depositToken(tokenId: Text, amount: Nat) : async Types.IntentResult<()> {
    switch (tokenLedgers.get(tokenId)) {
      case (?ledgerPrincipal) {
        let ledger = actor (Principal.toText(ledgerPrincipal)) : ICRC1.Self;
        // Transfer and credit escrow...
      };
      case null { #err(#InvalidToken) };
    };
  };
}
```

**Key Points:**
- The library tracks escrow state (lock/unlock/release)
- You implement actual token transfers
- This gives you full control over which tokens to support
- You can integrate with any ledger standard (ICRC-1, ICP Ledger, custom, etc.)

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

### Unit and Replica Tests

The library includes comprehensive test coverage (37 tests) across unit and replica tests:

**Unit Tests (29 tests)**
- `test/Utils.test.mo` - Validation and utilities (8 tests)
- `test/Escrow.test.mo` - Escrow accounting (6 tests)
- `test/IntentManager/IntentManager.test.mo` - Intent lifecycle (15 tests)

**Replica Tests (8 tests)** - Require local replica for IC API calls
- `test/TECDSA.replica.test.mo` - Address generation (4 tests)
- `test/IntentManager/IntentManager.replica.test.mo` - confirmQuote flow (4 tests)

**Run all tests:**
```bash
# Unit tests
mops test

# Replica tests (requires dfx start)
dfx start --clean --background
mops test
```

**Test organization:**
```
test/
├── Utils.test.mo              # Unit tests
├── Escrow.test.mo             # Unit tests
├── TECDSA.replica.test.mo     # Replica tests
└── IntentManager/
    ├── IntentManager.test.mo          # Unit tests
    └── IntentManager.replica.test.mo  # Replica tests
```

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
│   │   ├── BasicIntentCanister.mo  # Example pool canister
│   │   └── BasicIntentCanister.did # Candid interface
│   └── icp-intents-backend/
│       └── main.mo               # Default entry point
├── test/
│   ├── Utils.test.mo             # Utils unit tests (8 tests)
│   ├── Escrow.test.mo            # Escrow unit tests (6 tests)
│   ├── TECDSA.replica.test.mo    # tECDSA replica tests (4 tests)
│   └── IntentManager/
│       ├── IntentManager.test.mo         # Intent unit tests (15 tests)
│       └── IntentManager.replica.test.mo # Intent replica tests (4 tests)
├── mops.toml                     # Package configuration
├── dfx.json                      # DFX configuration
├── README.md                     # This file
├── ARCHITECTURE.md               # Detailed architecture docs
├── TESTING.md                    # Testing guide
└── DEPLOYMENT.md                 # Deployment guide
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
