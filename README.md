# ICP Intents SDK - Cross-Chain Intent-Based Exchange

A Motoko SDK for building cross-chain intent-based exchange systems on the Internet Computer Protocol (ICP). Features modular architecture, multi-chain support (EVM, Hoosat, Bitcoin), and comprehensive security through threshold ECDSA and Chain Fusion.

## 🚀 Features

- **Multi-Chain Support**: EVM (Ethereum, Base, Sepolia), Hoosat, Bitcoin, extensible for others
- **Secure Escrow**: Multi-token escrow with invariant enforcement
- **Threshold ECDSA**: Generate unique deposit addresses per intent using ICP's tECDSA
- **Chain Verification**: HTTP outcalls for trustless cross-chain verification
- **Comprehensive Types**: Full type safety with detailed error handling
- **Modular Design**: Use individual components or the complete SDK
- **Upgrade Safe**: Stable storage patterns for canister upgrades

## 📋 Table of Contents

- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [SDK Modules](#sdk-modules)
- [Usage Examples](#usage-examples)
- [Testing](#testing)
- [Security Considerations](#security-considerations)
- [Migration Guide](#migration-guide)

## 🏗 Architecture

### Modular SDK Structure

The SDK is organized into focused, composable modules:

```
icp-intents-lib/
├── IntentLib.mo           # Main SDK entry point
├── core/                  # Core types and state
│   ├── Types.mo           # All type definitions
│   ├── State.mo           # State management
│   ├── Errors.mo          # Error types
│   └── Events.mo          # Event logging
├── managers/              # Business logic
│   ├── IntentManager.mo   # Intent lifecycle orchestration
│   ├── Escrow.mo          # Multi-token escrow
│   └── FeeManager.mo      # Fee calculations
├── chains/                # Chain integrations
│   ├── ChainTypes.mo      # Chain type definitions
│   ├── ChainRegistry.mo   # Supported chains registry
│   ├── EVM.mo             # EVM verification
│   ├── Hoosat.mo          # Hoosat UTXO verification
│   └── Bitcoin.mo         # Bitcoin (coming soon)
├── crypto/                # Cryptography
│   └── TECDSA.mo          # Threshold ECDSA
└── utils/                 # Utilities
    ├── Math.mo            # Safe math & basis points
    ├── Validation.mo      # Input validation
    └── Cycles.mo          # Cycle management
```

### Intent Lifecycle Flow

```
┌─────────┐              ┌─────────┐              ┌─────────┐
│  User   │              │   SDK   │              │ Solver  │
└────┬────┘              └────┬────┘              └────┬────┘
     │                        │                        │
     │ 1. Create Intent       │                        │
     │───────────────────────>│                        │
     │                        │                        │
     │                        │   2. Submit Quote      │
     │                        │<───────────────────────│
     │                        │                        │
     │ 3. Confirm Quote       │                        │
     │───────────────────────>│                        │
     │                        │                        │
     │ <─── Address (tECDSA) ─│                        │
     │                        │                        │
     │     Share Address      │                        │
     │───────────────────────────────────────────────>│
     │                        │                        │
     │                        │ 4. Solver Deposits     │
     │                        │    (dest chain)        │
     │                        │<───────────────────────│
     │                        │                        │
     │                        │ 5. Mark Deposited      │
     │                        │<───────────────────────│
     │                        │                        │
     │                        │  Verify via HTTP       │
     │                        │  Outcall ✓             │
     │                        │                        │
     │                        │ 6. Fulfill Intent      │
     │                        │<───────────────────────│
     │                        │                        │
     │                        │  Release Escrow ───────>│
```

### State Machine

```
PendingQuote → Quoted → Confirmed → Deposited → Fulfilled
     │            │         │            │
     └────────────┴─────────┴────────────┴──→ Cancelled
```

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
import IntentLib "../src/icp-intents-lib/IntentLib";
import Principal "mo:base/Principal";
import Time "mo:base/Time";

actor MyIntentPool {
  // Initialize SDK
  let config : IntentLib.SystemConfig = {
    protocol_fee_bps = 30;  // 0.3%
    fee_collector = Principal.fromText("...");
    supported_chains = [
      #EVM({ chain_id = 1; name = "ethereum"; network = "mainnet"; rpc_urls = null }),
      #EVM({ chain_id = 8453; name = "base"; network = "mainnet"; rpc_urls = null }),
    ];
    min_intent_amount = 100_000;
    max_intent_amount = 1_000_000_000_000;
    default_deadline_duration = 7 * 24 * 60 * 60 * 1_000_000_000; // 7 days
    solver_allowlist = null; // Permissionless
  };

  stable var state = IntentLib.init(config);

  // Create intent
  public shared(msg) func createIntent(
    source : IntentLib.ChainSpec,
    destination : IntentLib.ChainSpec,
    source_amount : Nat,
    min_output : Nat,
    dest_recipient : Text,
    deadline : Time.Time,
  ) : async IntentLib.IntentResult<Nat> {
    IntentLib.createIntent(
      state,
      msg.caller,
      source,
      destination,
      source_amount,
      min_output,
      dest_recipient,
      deadline,
      Time.now()
    )
  };

  // Submit quote
  public shared(msg) func submitQuote(
    intent_id : Nat,
    output_amount : Nat,
    fee : Nat,
    solver_tip : Nat,
  ) : async IntentLib.IntentResult<()> {
    IntentLib.submitQuote(
      state,
      intent_id,
      msg.caller,
      output_amount,
      fee,
      solver_tip,
      null, // solver_dest_address
      Time.now()
    )
  };

  // More methods...
}
```

## 📚 SDK Modules

### IntentLib - Main Entry Point

The primary interface to the SDK. Import with:

```motoko
import IntentLib "../src/icp-intents-lib/IntentLib";
```

**Key Functions:**
- `init(config)` - Initialize SDK state
- `createIntent(...)` - Create new intent
- `submitQuote(...)` - Submit solver quote
- `confirmQuote(...)` - Confirm quote and generate address
- `markDeposited(...)` - Mark destination deposit complete
- `fulfillIntent(...)` - Release escrow to solver
- `cancelIntent(...)` - Cancel intent

**Re-exported Types:**
- `Intent`, `Quote`, `IntentStatus`
- `IntentResult<T>`, `IntentError`
- `SystemConfig`, `ChainSpec`
- `Chain`, `EVMChain`, `HoosatChain`

### Core Modules

#### Types (`core/Types.mo`)

All type definitions for the SDK:

```motoko
import Types "../src/icp-intents-lib/core/Types";

type Intent = Types.Intent;
type Quote = Types.Quote;
type IntentStatus = Types.IntentStatus;
```

**Key Types:**
- `Intent` - Main intent structure with full state
- `Quote` - Solver quote with pricing
- `IntentStatus` - State machine states
- `ChainSpec` - Chain specification (chain, token, network)
- `IntentError` - Comprehensive error types
- `SystemConfig` - SDK configuration

#### Errors (`core/Errors.mo`)

Comprehensive error handling:

```motoko
type IntentError = {
  #NotFound;
  #Unauthorized;
  #InvalidAmount : Text;
  #InvalidDeadline : Text;
  #InvalidChain : Text;
  #InvalidToken : Text;
  #InvalidAddress : Text;
  #InsufficientBalance;
  #QuoteExpired;
  #InvalidState : Text;
  #VerificationFailed : Text;
  // ... and more
};
```

### Manager Modules

#### IntentManager (`managers/IntentManager.mo`)

Orchestrates the full intent lifecycle:

```motoko
import IntentManager "../src/icp-intents-lib/managers/IntentManager";

// Create intent
let result = IntentManager.createIntent(
  state,
  user,
  source,
  destination,
  source_amount,
  min_output,
  dest_recipient,
  deadline,
  current_time
);

// Get intent
let intent = IntentManager.getIntent(state, intent_id);
```

#### Escrow (`managers/Escrow.mo`)

Multi-token escrow with invariant enforcement:

```motoko
import Escrow "../src/icp-intents-lib/managers/Escrow";

let escrow = Escrow.init();

// Lock funds
let result = Escrow.lock(escrow, user, "ICP", 1_000_000);

// Release funds
ignore Escrow.release(escrow, user, "ICP", 500_000);

// Get balance
let balance = Escrow.getBalance(escrow, user, "ICP");
```

**Features:**
- Per-user, per-token balance tracking
- Lock/release operations
- Invariant verification
- Stable storage support

#### FeeManager (`managers/FeeManager.mo`)

Fee calculations and collection:

```motoko
import FeeManager "../src/icp-intents-lib/managers/FeeManager";

let fees = FeeManager.calculateFees(
  output_amount,
  protocol_fee_bps,
  quote
);
// Returns: { protocol_fee, solver_fee, solver_tip, total_fees, net_output }
```

### Chain Modules

#### EVM (`chains/EVM.mo`)

EVM chain verification via HTTP outcalls:

```motoko
import EVM "../src/icp-intents-lib/chains/EVM";

let config = {
  rpc_urls = ["https://eth.llamarpc.com"];
  min_confirmations = 12;
};

let result = await EVM.verify(config, request);
// Returns: #Success | #Pending | #Failed
```

**Supports:**
- Native ETH transfers
- ERC-20 token transfers
- Transaction receipt verification
- Confirmation counting

#### Hoosat (`chains/Hoosat.mo`)

Hoosat UTXO chain verification:

```motoko
import Hoosat "../src/icp-intents-lib/chains/Hoosat";

let result = await Hoosat.verify(config, request);
```

**Features:**
- UTXO verification via HTTP outcalls
- Confirmation checking
- Address validation

### Crypto Modules

#### TECDSA (`crypto/TECDSA.mo`)

Threshold ECDSA address generation:

```motoko
import TECDSA "../src/icp-intents-lib/crypto/TECDSA";
import ChainTypes "../src/icp-intents-lib/chains/ChainTypes";

let context : ChainTypes.AddressContext = {
  intent_id = 1;
  user = userPrincipal;
};

let address = await TECDSA.generateAddress(
  #EVM({ chain_id = 1; name = "ethereum"; network = "mainnet"; rpc_urls = null }),
  context,
  "key_1"
);
// Returns: #ok("0xabc123...") or #err(error)
```

**Features:**
- Deterministic derivation paths
- Ethereum address generation (Keccak256)
- Bitcoin address generation
- Public key management

### Utility Modules

#### Math (`utils/Math.mo`)

Safe mathematical operations:

```motoko
import Math "../src/icp-intents-lib/utils/Math";

// Basis points
let fee = Math.calculateBps(1_000_000, 30); // 0.3%
assert(fee == 3_000);

// Fee calculation
let (fee, net) = Math.calculateFee(1_000_000, 30);

// Slippage
let min_amount = Math.applySlippage(1_000_000, 50); // 0.5% slippage

// Constants
Math.MAX_BPS // 10_000 (100%)
```

#### Validation (`utils/Validation.mo`)

Input validation:

```motoko
import Validation "../src/icp-intents-lib/utils/Validation";

// Validate amount
let err = Validation.validateAmount(amount, config);

// Validate deadline
let err = Validation.validateDeadline(deadline, now, config);

// Validate address
let err = Validation.validateEthAddress("0x742d35Cc...");
let err = Validation.validateHoosatAddress("Hoosat:qz...");
```

## 💡 Usage Examples

### Example 1: Complete Intent Pool

```motoko
import IntentLib "../src/icp-intents-lib/IntentLib";
import Principal "mo:base/Principal";
import Time "mo:base/Time";

actor IntentPool {
  // Configuration
  let config : IntentLib.SystemConfig = {
    protocol_fee_bps = 30;
    fee_collector = Principal.fromText("...");
    supported_chains = [
      #EVM({ chain_id = 1; name = "ethereum"; network = "mainnet"; rpc_urls = null }),
      #Hoosat({ network = "mainnet"; rpc_url = "https://api.network.hoosat.fi"; min_confirmations = 10 }),
    ];
    min_intent_amount = 1_000;
    max_intent_amount = 1_000_000_000_000;
    default_deadline_duration = 604_800_000_000_000; // 7 days
    solver_allowlist = null;
  };

  stable var state = IntentLib.init(config);

  // User creates intent: ICP → ETH
  public shared(msg) func createIntent(
    source_amount : Nat,
    min_output : Nat,
    dest_recipient : Text,
    deadline : Time.Time,
  ) : async IntentLib.IntentResult<Nat> {
    let source : IntentLib.ChainSpec = {
      chain = "icp";
      chain_id = null;
      token = "ICP";
      network = "mainnet";
    };

    let destination : IntentLib.ChainSpec = {
      chain = "ethereum";
      chain_id = ?1;
      token = "native";
      network = "mainnet";
    };

    IntentLib.createIntent(
      state,
      msg.caller,
      source,
      destination,
      source_amount,
      min_output,
      dest_recipient,
      deadline,
      Time.now()
    )
  };

  // Solver submits quote
  public shared(msg) func submitQuote(
    intent_id : Nat,
    output_amount : Nat,
    fee : Nat,
  ) : async IntentLib.IntentResult<()> {
    IntentLib.submitQuote(
      state,
      intent_id,
      msg.caller,
      output_amount,
      fee,
      0, // solver_tip
      null,
      Time.now()
    )
  };

  // User confirms quote
  public shared(msg) func confirmQuote(
    intent_id : Nat,
    quote_index : Nat,
  ) : async IntentLib.IntentResult<Text> {
    await IntentLib.confirmQuote(
      state,
      msg.caller,
      intent_id,
      quote_index,
      Time.now()
    )
  };

  // Solver marks deposit complete
  public shared(msg) func markDeposited(
    intent_id : Nat,
    tx_hash : Text,
  ) : async IntentLib.IntentResult<()> {
    await IntentLib.markDeposited(
      state,
      msg.caller,
      intent_id,
      tx_hash,
      Time.now()
    )
  };

  // Solver fulfills intent
  public shared(msg) func fulfillIntent(
    intent_id : Nat,
  ) : async IntentLib.IntentResult<()> {
    await IntentLib.fulfillIntent(
      state,
      msg.caller,
      intent_id,
      Time.now()
    )
  };

  // Query methods
  public query func getIntent(id : Nat) : async ?IntentLib.Intent {
    IntentLib.getIntent(state, id)
  };
}
```

### Example 2: Token Integration

For token deposits/withdrawals, see the live example in `src/SimpleIntentPool.mo` which includes:
- ICRC-2 token transfers
- Escrow deposits
- Token registration
- Full integration patterns

### Example 3: Standalone Escrow

Use the escrow module independently:

```motoko
import Escrow "../src/icp-intents-lib/managers/Escrow";
import Principal "mo:base/Principal";

actor DEX {
  stable var escrow = Escrow.init();

  public func lockForSwap(user : Principal, token : Text, amount : Nat) : async () {
    ignore Escrow.lock(escrow, user, token, amount);
  };

  public func releaseAfterSwap(user : Principal, token : Text, amount : Nat) : async () {
    ignore Escrow.release(escrow, user, token, amount);
  };
}
```

## 🧪 Testing

The SDK has comprehensive test coverage with **~284 tests** across **14 test files**.

### Quick Start

```bash
# Run all tests
mops test

# Run specific test file
mops test test/Math.test.mo

# Test with verbose output
mops test --verbose
```

### Test Coverage Summary

| Module Type | Coverage | Tests |
|------------|----------|-------|
| Core Utils | 100% | 118 tests |
| Managers | 100% | 120 tests |
| Crypto | 100% | 20 tests |
| Chains | 100% | 26 tests |
| **Total** | **87%** | **~284 tests** |

**Status**: ✅ All tests passing

### Test Organization

```
test/
├── chains/
│   ├── EVM.test.mo              # EVM verification (12 tests)
│   └── Hoosat.test.mo           # Hoosat verification (13 tests)
├── IntentManager/
│   ├── IntentManager.test.mo    # Sync operations (24 tests)
│   └── IntentManager.replica.test.mo # Async operations (20 tests)
├── ChainRegistry.test.mo        # Chain management (18 tests)
├── Escrow.test.mo               # Escrow operations (8 tests)
├── Events.test.mo               # Event logging (15 tests)
├── FeeManager.test.mo           # Fee calculations (19 tests)
├── Math.test.mo                 # Math utilities (23 tests)
├── State.test.mo                # State machine (58 tests)
├── TECDSA.replica.test.mo       # Crypto operations (20 tests)
├── TokenRegistry.test.mo        # Token management (16 tests)
├── Utils.test.mo                # General utilities
└── Validation.test.mo           # Input validation (37 tests)
```

### Documentation

For detailed testing information, see:

- **[Test Coverage Report](docs/TEST_COVERAGE.md)** - Comprehensive coverage analysis
- **[Testing Guide](docs/TESTING_GUIDE.md)** - How to write and run tests

### What's Tested

✅ **State Machine**: All transitions, edge cases, terminal states
✅ **Intent Lifecycle**: Create, quote, confirm, deposit, fulfill, cancel
✅ **Fee Calculations**: Protocol fees, solver fees, tips, validation
✅ **Chain Management**: Registration, validation, multi-chain support
✅ **Crypto Operations**: Key derivation, address generation, signatures
✅ **Escrow**: Balance tracking, lock/release, multi-user/token
✅ **Validation**: Amounts, addresses, deadlines, chain specs
✅ **Math**: BPS calculations, overflow protection, slippage

### Integration Testing

Some modules require integration test infrastructure:

- **EVM/Hoosat Verification**: Requires RPC canisters and HTTP outcalls
- **TECDSA Operations**: Requires IC management canister access
- **Token Transfers**: Requires deployed ICRC-2 ledger canisters

These are documented in the test files with clear requirements for future integration testing.

### Contributing Tests

When adding features:

1. Write unit tests for business logic
2. Document integration requirements
3. Follow existing test patterns
4. See [Testing Guide](docs/TESTING_GUIDE.md) for details

## 🔒 Security Considerations

### Critical Security Features

1. **Threshold ECDSA**
   - Unique derivation path per intent
   - Never reuse addresses
   - Keccak256 for Ethereum addresses

2. **Escrow Invariants**
   - Balance tracking verified on every operation
   - Safe arithmetic (no overflow/underflow)
   - Multi-token isolation

3. **Chain Verification**
   - HTTP outcalls for trustless verification
   - Confirmation requirements enforced
   - Reorg protection

4. **Input Validation**
   - All inputs validated before state changes
   - Address format verification
   - Amount bounds checking

### Recent Security Improvements

The SDK has undergone comprehensive security hardening with the following improvements:

**Critical Fixes (v0.2.0):**

1. **Authorization Bypass Prevention**
   - Removed `Principal.isController()` check that allowed controllers to bypass solver allowlist
   - All solver authorization now properly validated against allowlist
   - Location: `utils/Validation.mo:83`

2. **Integer Underflow Protection**
   - Added validation before all `Nat.sub()` operations to prevent traps
   - `Math.calculateFee()` now returns `?(Nat, Nat)` with safe arithmetic
   - `FeeManager.calculateFees()` validates fees before subtraction
   - Locations: `utils/Math.mo:73`, `managers/FeeManager.mo:62`

3. **Missing Authorization Check**
   - Added caller validation to `markDeposited()` - only intent creator can mark deposits
   - Prevents malicious actors from marking arbitrary intents as deposited
   - Location: `managers/IntentManager.mo:226`

**High Priority Fixes (v0.2.0):**

4. **Escrow Race Condition**
   - Lock escrow **before** state transition in `markDeposited()`
   - Added rollback on transition failure to maintain consistency
   - Location: `managers/IntentManager.mo:234-244`

5. **Time Boundary Corrections**
   - Consistent `>=` comparison for deadline checks (was inconsistent `>`)
   - Prevents intents from executing exactly at deadline timestamp
   - Location: `core/State.mo`

6. **Quote Expiry Validation**
   - Ensure quotes aren't created with expiry time in the past
   - Added validation: `quote_expiry > current_time`
   - Location: `managers/IntentManager.mo:142`

7. **Information Leakage Prevention**
   - Removed `debug_show()` from error messages to prevent config leakage
   - Prevents allowlist exposure in error responses
   - Location: `utils/Validation.mo:86`

8. **Placeholder Removal**
   - Removed hardcoded placeholder principal from `Hoosat.buildTransaction()`
   - Added `user: Principal` parameter for proper key derivation
   - Location: `chains/Hoosat.mo:116`

9. **State Rollback Patterns**
   - Formalized fail-fast validation across all async state-changing operations
   - Prevents partial state mutations when async operations fail
   - Pattern: Validate state transition → Perform risky async operation → Commit state
   - Locations: `managers/IntentManager.mo:489-590` (fulfillIntent), `606-685` (cancelIntent), `719-793` (depositTokens)
   - Critical error logging for irrecoverable state inconsistencies

10. **HTTP Outcall Resilience**
    - Implemented graceful degradation for transient network failures
    - Returns `#Pending` instead of `#Failed` for transient errors (rate limits, timeouts, server errors)
    - Allows automatic retry on temporary failures
    - EVM: Leverages multi-provider consensus via EVM RPC canister
    - Hoosat: Handles HTTP 429, 5xx errors, timeout exceptions across all 4 outcalls
    - Locations: `chains/EVM.mo:354-520`, `chains/Hoosat.mo:182-541`

**Code Quality Improvements (v0.2.0):**

11. **Centralized Constants**
    - Created `utils/Constants.mo` for magic number elimination
    - Reduces configuration errors and improves maintainability

12. **Event Data Accuracy**
    - Fixed placeholder values in `QuoteConfirmed` events
    - Tracks actual `quote_index` and `deposit_address` for off-chain indexing

13. **Consolidated JSON Parsing**
    - Unified duplicate parsing logic in `Hoosat.mo`
    - Improved type safety with validation in `EVM.mo`

### Pre-Production Checklist

- [x] ~~Security review~~ ✅ Complete - Critical and high priority issues resolved
- [ ] External security audit
- [ ] Load testing (1000+ intents)
- [ ] Upgrade testing
- [ ] Cycle cost analysis
- [ ] Error path testing
- [ ] Chain reorg testing

## 📖 Migration Guide

### v0.2.0 Breaking Changes (Security Hardening)

**IMPORTANT**: Version 0.2.0 introduces breaking API changes for security improvements. Review all changes carefully before upgrading.

#### 1. Math.calculateFee() Now Returns Optional

**Change**: Return type changed from `(Nat, Nat)` to `?(Nat, Nat)` for safe arithmetic.

```motoko
// OLD (v0.1.x)
let (fee, net) = Math.calculateFee(gross, fee_bps);

// NEW (v0.2.0)
let (fee, net) = switch (Math.calculateFee(gross, fee_bps)) {
  case null {
    // Handle case where fees exceed gross amount
    return #err(#InvalidAmount("Fees exceed amount"));
  };
  case (?(f, n)) { (f, n) };
};
```

#### 2. FeeManager.calculateFees() Now Returns Optional

**Change**: Return type changed from `FeeBreakdown` to `?FeeBreakdown` to prevent underflow.

```motoko
// OLD (v0.1.x)
let fees = FeeManager.calculateFees(output_amount, protocol_fee_bps, quote);

// NEW (v0.2.0)
let fees = switch (FeeManager.calculateFees(output_amount, protocol_fee_bps, quote)) {
  case null {
    return #err(#InvalidAmount("Total fees exceed output amount"));
  };
  case (?breakdown) { breakdown };
};
```

#### 3. IntentLib.calculateFees() Now Returns Optional

**Change**: Same as FeeManager, now returns `?FeeBreakdown`.

```motoko
// OLD (v0.1.x)
let fees = IntentLib.calculateFees(state, output_amount, protocol_fee_bps, quote);

// NEW (v0.2.0)
let fees = switch (IntentLib.calculateFees(state, output_amount, protocol_fee_bps, quote)) {
  case null { /* handle error */ };
  case (?breakdown) { breakdown };
};
```

#### 4. IntentManager.markDeposited() Requires Caller Parameter

**Change**: Added `caller: Principal` parameter for authorization check.

```motoko
// OLD (v0.1.x)
let result = IntentManager.markDeposited(
  state,
  intent_id,
  verified_amount,
  current_time
);

// NEW (v0.2.0)
public shared(msg) func markDeposited(intent_id : Nat, verified_amount : Nat) : async IntentResult<()> {
  IntentManager.markDeposited(
    state,
    intent_id,
    msg.caller,  // NEW: caller parameter
    verified_amount,
    Time.now()
  )
}
```

#### 5. IntentLib.verifyAndMarkDeposited() Requires Caller Parameter

**Change**: Added `caller: Principal` parameter (flows to IntentManager).

```motoko
// OLD (v0.1.x)
await IntentLib.verifyAndMarkDeposited(
  state,
  intent_id,
  tx_hash,
  current_time
);

// NEW (v0.2.0)
public shared(msg) func markDeposited(intent_id : Nat, tx_hash : Text) : async IntentResult<()> {
  await IntentLib.verifyAndMarkDeposited(
    state,
    msg.caller,  // NEW: caller parameter
    intent_id,
    tx_hash,
    Time.now()
  )
}
```

#### 6. Hoosat.buildTransaction() Requires User Parameter

**Change**: Added `user: Principal` parameter to replace hardcoded placeholder.

```motoko
// OLD (v0.1.x)
await Hoosat.buildTransaction(
  config,
  utxo,
  recipient,
  amount,
  intent_id,
  key_name
);

// NEW (v0.2.0)
await Hoosat.buildTransaction(
  config,
  utxo,
  recipient,
  amount,
  intent_id,
  user,      // NEW: user principal for key derivation
  key_name
);
```

#### Migration Checklist

- [ ] Update all `Math.calculateFee()` calls to handle optional return
- [ ] Update all `FeeManager.calculateFees()` calls to handle optional return
- [ ] Add `msg.caller` parameter to `IntentManager.markDeposited()` calls
- [ ] Add `msg.caller` parameter to `IntentLib.verifyAndMarkDeposited()` calls
- [ ] Add `user` parameter to `Hoosat.buildTransaction()` calls
- [ ] Run all tests to ensure compatibility
- [ ] Review error handling for new null cases

**Testing**: All 284 tests have been updated and pass with the new API.

### From Old API (Pre-Refactor)

**Module Imports:**

```motoko
// OLD
import IntentManager "mo:icp-intents-lib/IntentManager";
import Types "mo:icp-intents-lib/Types";
import Utils "mo:icp-intents-lib/Utils";
import Escrow "mo:icp-intents-lib/Escrow";
import TECDSA "mo:icp-intents-lib/TECDSA";

// NEW
import IntentLib "../src/icp-intents-lib/IntentLib";
// or specific modules:
import IntentManager "../src/icp-intents-lib/managers/IntentManager";
import Types "../src/icp-intents-lib/core/Types";
import Math "../src/icp-intents-lib/utils/Math";
import Validation "../src/icp-intents-lib/utils/Validation";
import Escrow "../src/icp-intents-lib/managers/Escrow";
import TECDSA "../src/icp-intents-lib/crypto/TECDSA";
```

**API Changes:**

```motoko
// OLD - Request records
await IntentManager.postIntent(state, user, {
  source = sourceAsset;
  destination = destAsset;
  // ... more fields
}, currentTime);

// NEW - Individual parameters
IntentLib.createIntent(
  state,
  user,
  source,
  destination,
  source_amount,
  min_output,
  dest_recipient,
  deadline,
  current_time
);
```

**Escrow Changes:**

```motoko
// OLD - deposit/withdraw/lock/unlock
Escrow.deposit(state, user, token, amount);
Escrow.lock(state, user, token, amount);
Escrow.unlock(state, user, token, amount);
Escrow.withdraw(state, user, token, amount);

// NEW - Only lock/release
Escrow.lock(state, user, token, amount);
Escrow.release(state, user, token, amount);
// Note: Deposit/withdraw now handled by integrator
```

**Utils Refactored:**

```motoko
// OLD
Utils.calculateFee(amount, bps);
Utils.isValidEthAddress(addr);

// NEW
Math.calculateBps(amount, bps);
Validation.validateEthAddress(addr);
```

## 📝 Project Structure

```
icp-intents/
├── src/
│   ├── icp-intents-lib/          # SDK Library
│   │   ├── IntentLib.mo          # Main entry point
│   │   ├── core/                 # Core types & state
│   │   ├── managers/             # Business logic
│   │   ├── chains/               # Chain integrations
│   │   ├── crypto/               # Cryptography
│   │   └── utils/                # Utilities
│   ├── SimpleIntentPool.mo       # Example pool canister
│   └── MockICRC1Ledger.mo        # Test ledger
├── test/
│   ├── Escrow.test.mo            # Escrow tests
│   ├── Utils.test.mo             # Utils tests
│   ├── TECDSA.replica.test.mo    # TECDSA tests
│   └── IntentManager/            # IntentManager tests
├── test-intent-flow.sh           # Integration test
├── test-fulfillment.sh           # Fulfillment test
├── mops.toml                     # Package config
└── dfx.json                      # DFX config
```

## 🤝 Contributing

Contributions welcome! See [Testing Guide](docs/TESTING_GUIDE.md) for test development.

### Priority Areas

**Features:**
- [ ] Bitcoin chain support
- [ ] Solana support
- [ ] Intent batching
- [ ] Advanced fee structures
- [ ] Multi-hop intents

**Testing:**
- [x] ~~Core unit tests~~ ✅ Complete (284 tests)
- [ ] Integration test infrastructure
- [ ] Property-based testing
- [ ] Performance benchmarks
- [ ] Security audits

**Documentation:**
- [x] ~~Test coverage report~~ ✅ Complete
- [x] ~~Testing guide~~ ✅ Complete
- [ ] API reference
- [ ] Integration examples
- [ ] Deployment guide

## 📄 License

MIT License

## 🙏 Acknowledgments

- Inspired by NEAR Intents
- Built on ICP Chain Fusion
- Motoko language and community

---

**Built for the Internet Computer ecosystem** 🚀
