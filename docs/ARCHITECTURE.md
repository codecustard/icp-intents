# ICP Intents Library - Architecture

## Overview

The ICP Intents library is a production-grade SDK for building cross-chain intent systems on the Internet Computer. It provides a complete framework for creating, matching, verifying, and settling cross-chain token swaps using an intent-based architecture.

## Design Principles

1. **Modularity**: Clear separation of concerns with isolated modules
2. **Type Safety**: Comprehensive type system with explicit error handling
3. **Extensibility**: Pluggable chain support via registry pattern
4. **Upgrade Safety**: Stable storage with invariant verification
5. **Cycle Efficiency**: Optimized for minimal cycle consumption
6. **State Machine**: Explicit status transitions with validation

## Architecture Layers

```
┌─────────────────────────────────────────────────────────┐
│                    IntentLib.mo                         │
│              (Public SDK Entry Point)                   │
└─────────────────────────────────────────────────────────┘
                           │
           ┌───────────────┼───────────────┐
           │               │               │
┌──────────▼────────┐ ┌───▼────────┐ ┌───▼──────────┐
│    Managers/      │ │  Chains/   │ │   Core/      │
│  IntentManager    │ │  Registry  │ │   Types      │
│  Escrow          │ │  EVM       │ │   State      │
│  FeeManager      │ │  Hoosat    │ │   Events     │
└──────────┬────────┘ └───┬────────┘ └───┬──────────┘
           │               │               │
           └───────────────┼───────────────┘
                           │
                  ┌────────▼────────┐
                  │    Utils/       │
                  │  Math           │
                  │  Validation     │
                  │  Cycles         │
                  └─────────────────┘
```

## Module Structure

### Core (`src/icp-intents-lib/core/`)

**Types.mo**
- Central type definitions for the entire system
- Intent, Quote, IntentStatus, ChainSpec
- Result types: `IntentResult<T> = { #ok : T; #err : IntentError }`
- System configuration

**State.mo**
- State machine implementation for intent lifecycle
- Valid transitions: PendingQuote → Quoted → Confirmed → Deposited → Fulfilled
- Alternative paths: Any state → Cancelled/Expired
- Transition validation with business rules

**Errors.mo**
- Comprehensive error taxonomy
- Categorization: retryable vs terminal errors
- Helper functions: `errorToText()`, `isRetryable()`, `isTerminal()`

**Events.mo**
- Structured event logging for off-chain indexing
- Event types: IntentCreated, QuoteSubmitted, DepositVerified, IntentFulfilled, etc.
- EventLogger class for emit/format operations

### Chains (`src/icp-intents-lib/chains/`)

**ChainTypes.mo**
- Chain abstraction with variants:
  ```motoko
  type Chain = {
    #EVM : EVMChain;
    #Bitcoin : BitcoinChain;
    #Hoosat : HoosatChain;
    #Custom : CustomChain;
  };
  ```
- Verification proof types (EVMProof, UTXOProof, CustomProof)
- Common interfaces: VerificationRequest, VerificationResult

**ChainRegistry.mo**
- Registry for supported chains
- Maps chain names to Chain configurations
- Manages external verifier canisters
- Validation: `validateSpec()`, `getChainBySpec()`

**EVM.mo**
- EVM chain verification implementation
- Uses official EVM RPC canister
- Validates transaction receipts and amounts
- Supports: Ethereum, Base, Arbitrum, Optimism, Sepolia

**Hoosat.mo**
- UTXO-based chain verification
- HTTP outcalls to Hoosat REST API
- Transaction building with hoosat-mo library
- ECDSA signature generation

### Crypto (`src/icp-intents-lib/crypto/`)

**TECDSA.mo**
- Threshold ECDSA operations via IC management canister
- Address generation for multiple chains
- Transaction signing with cycle management
- Derivation paths: intent_id + user_principal

### Managers (`src/icp-intents-lib/managers/`)

**IntentManager.mo**
- Orchestrates the complete intent lifecycle
- Functions:
  - `createIntent()` - Create new intent with validation
  - `submitQuote()` - Solvers submit quotes
  - `confirmQuote()` - User confirms selected quote
  - `markDeposited()` - Mark deposit verified
  - `fulfillIntent()` - Complete intent and release escrow
  - `cancelIntent()` - Cancel with escrow refund
- Integrates with Escrow, FeeManager, ChainRegistry

**Escrow.mo**
- Multi-token escrow with composite keys: "user:token"
- Operations: `lock()`, `release()`, `getBalance()`
- Invariant verification: total_locked = sum(individual_balances)
- Upgrade-safe with `verifyInvariants()`

**FeeManager.mo**
- Fee calculation: protocol + solver + tip
- Fee breakdown with net output
- Collection tracking per token
- Validation: fees shouldn't exceed output

### Utils (`src/icp-intents-lib/utils/`)

**Math.mo**
- Safe arithmetic operations
- Basis points calculations (10,000 BPS = 100%)
- Slippage application
- Overflow/underflow protection

**Validation.mo**
- Input validation for all user data
- Address validation (ETH, Hoosat, Bitcoin)
- Amount, deadline, chain spec validation
- Solver whitelist checking

**Cycles.mo**
- Cycle balance monitoring
- Health checks: #Critical, #Low, #Healthy
- Cost estimation for operations:
  - ECDSA signing: 30B cycles
  - ECDSA pubkey: 10B cycles
  - HTTP outcall: 230B cycles

## State Machine

### Intent Lifecycle

```
┌──────────────┐
│ PendingQuote │ ◄─── createIntent()
└──────┬───────┘
       │ submitQuote()
       ▼
┌──────────────┐
│    Quoted    │
└──────┬───────┘
       │ confirmQuote()
       ▼
┌──────────────┐
│  Confirmed   │
└──────┬───────┘
       │ verifyDeposit()
       ▼
┌──────────────┐
│  Deposited   │ ◄─── Escrow locked
└──────┬───────┘
       │ fulfillIntent()
       ▼
┌──────────────┐
│  Fulfilled   │ ◄─── Escrow released
└──────────────┘

       │ cancelIntent()
       ▼
┌──────────────┐
│  Cancelled   │ ◄─── Escrow refunded
└──────────────┘

       │ deadline passed
       ▼
┌──────────────┐
│   Expired    │ ◄─── Escrow refunded
└──────────────┘
```

### State Transition Rules

| From | To | Condition | Action |
|------|-----|-----------|--------|
| PendingQuote | Quoted | First quote received | Add quote to list |
| Quoted | Confirmed | User selects quote | Set selected_quote |
| Confirmed | Deposited | Deposit verified | Lock escrow |
| Deposited | Fulfilled | Solver delivers | Release escrow, collect fees |
| Any | Cancelled | User cancels | Refund escrow if locked |
| Any | Expired | Deadline passed | Refund escrow if locked |

## Data Flow

### Creating an Intent

```
User → createIntent()
  ↓
Validate inputs (amount, deadline, chains)
  ↓
Check chains are supported (ChainRegistry)
  ↓
Create Intent with status = PendingQuote
  ↓
Emit IntentCreated event
  ↓
Return intent_id
```

### Fulfilling an Intent

```
Solver deposits to generated address
  ↓
Off-chain verification detects deposit
  ↓
verifyDeposit() calls chain verifier
  ↓
Verification successful → markDeposited()
  ↓
Lock funds in Escrow
  ↓
Solver delivers on destination chain
  ↓
fulfillIntent() called
  ↓
Calculate fees (protocol + solver + tip)
  ↓
Release escrow
  ↓
Record protocol fee collection
  ↓
Emit IntentFulfilled event
```

## Chain Integration

### Adding a New Chain

1. **Define Chain Type** (in ChainTypes.mo):
   ```motoko
   type MyChain = {
     network : Text;
     rpc_url : Text;
     min_confirmations : Nat;
   };
   ```

2. **Add to Chain Variant**:
   ```motoko
   type Chain = {
     #EVM : EVMChain;
     #Hoosat : HoosatChain;
     #MyChain : MyChain; // Add here
   };
   ```

3. **Create Verifier Module** (`chains/MyChain.mo`):
   ```motoko
   public func verify(config, request) : async VerificationResult
   public func generateAddress(config, context) : async IntentResult<Text>
   public func buildTransaction(...) : async IntentResult<Blob>
   public func broadcast(...) : async IntentResult<Text>
   ```

4. **Register Chain**:
   ```motoko
   registerChain(state, "mychain", #MyChain({
     network = "mainnet";
     rpc_url = "https://rpc.mychain.com";
     min_confirmations = 6;
   }));
   ```

## Multi-Canister Architecture

The library is designed to work in both single-canister and multi-canister deployments:

### Single-Canister Deployment
```
┌─────────────────────────────┐
│     Intent Pool Canister     │
│  ┌─────────────────────┐    │
│  │  IntentManager      │    │
│  │  ChainRegistry      │    │
│  │  Escrow             │    │
│  │  FeeManager         │    │
│  │  Built-in Verifiers │    │
│  └─────────────────────┘    │
└─────────────────────────────┘
```

### Multi-Canister Deployment
```
┌──────────────────┐      ┌──────────────────┐
│  Intent Pool     │      │  Escrow Manager  │
│  - Intents       │◄────►│  - Locked funds  │
│  - Quotes        │      │  - Invariants    │
└──────────────────┘      └──────────────────┘
         │
         ▼
┌──────────────────┐      ┌──────────────────┐
│  EVM Verifier    │      │  Hoosat Verifier │
│  - EVM RPC       │      │  - UTXO verify   │
│  - Receipt check │      │  - Tx building   │
└──────────────────┘      └──────────────────┘
```

### Benefits of Multi-Canister

- **Scalability**: Distribute load across canisters
- **Isolation**: Failures in one verifier don't affect others
- **Upgradability**: Upgrade verifiers independently
- **Specialization**: Optimize each canister for its task

## Stable Storage

All state is designed for upgrade safety:

```motoko
// Before upgrade
system func preupgrade() {
  stable_data := IntentLib.toStable(state);
}

// After upgrade
system func postupgrade() {
  state := IntentLib.fromStable(stable_data, config);

  // Verify invariants
  if (not IntentLib.verifyEscrowInvariants(state)) {
    Debug.trap("Escrow invariants violated after upgrade!");
  };
}
```

### Stable Data Structure

```motoko
type StableManagerData = {
  intents : [(Nat, Intent)];
  next_id : Nat;
  escrow : StableEscrowData;
  chain_registry : StableRegistryData;
};
```

## Fee Structure

### Fee Components

1. **Protocol Fee**: Platform fee in basis points (configurable)
2. **Solver Fee**: Fee charged by solver (set in quote)
3. **Solver Tip**: Optional tip to prioritize (set in quote)

### Fee Calculation

```motoko
output_amount = 1000 tokens
protocol_fee_bps = 30 (0.3%)
solver_fee = 5 tokens
solver_tip = 2 tokens

protocol_fee = (1000 * 30) / 10000 = 3 tokens
total_fees = 3 + 5 + 2 = 10 tokens
net_output = 1000 - 10 = 990 tokens
```

### Fee Collection

- Protocol fees are collected in destination token
- Tracked per token in FeeManager
- Can be withdrawn by protocol owner
- Solver fees/tips go directly to solver

## Security Considerations

### Access Control

- **Intent Creator**: Only user can confirm quotes and cancel
- **Solver Authorization**: Configurable whitelist/blacklist
- **Protocol Admin**: Fee configuration, chain registration

### Validation

- All user inputs validated before processing
- Address format validation per chain
- Amount bounds checking
- Deadline enforcement
- Chain compatibility verification

### Escrow Safety

- Invariant verification on every operation
- Automatic verification after upgrade
- No partial releases (atomic operations)
- Overflow protection in calculations

### Cycle Management

- Check sufficient cycles before expensive operations
- Cost estimation for ECDSA and HTTP outcalls
- Health monitoring with alerts
- Configurable minimum cycle threshold

## Error Handling

### Error Categories

**Retryable Errors**:
- `#NetworkError` - RPC/HTTP failures
- `#InsufficientCycles` - Need more cycles
- `#HTTPOutcallFailed` - Temporary network issue

**Terminal Errors**:
- `#InvalidAddress` - Bad address format
- `#ChainNotSupported` - Unsupported chain
- `#Expired` - Intent deadline passed
- `#Cancelled` - Intent cancelled by user

### Error Flow

```motoko
switch (await operation()) {
  case (#ok(result)) {
    // Success path
  };
  case (#err(error)) {
    if (Errors.isRetryable(error)) {
      // Retry with backoff
    } else {
      // Log and notify user
    };
  };
};
```

## Performance Optimizations

### Cycle Efficiency

- Batch HTTP outcalls where possible
- Cache public keys for intent lifetime
- Use query calls for read operations
- Minimize cross-canister calls

### Storage Optimization

- HashMap instead of TrieMap for frequent access
- Composite keys to reduce nesting
- Clean up terminal intents via heartbeat
- Archive old data to separate canister

### Computational Efficiency

- Early validation to fail fast
- Lazy evaluation where possible
- Avoid redundant calculations
- Optimize hot paths (quote submission, verification)

## Monitoring & Observability

### Events for Indexing

All major operations emit structured events:
- Intent lifecycle events
- Escrow operations
- Fee collection
- Verification status

### Metrics to Track

- Active intents by status
- Total value locked in escrow
- Fees collected per token
- Verification success rate
- Average fulfillment time
- Cycle burn rate

### Health Checks

- Cycle balance monitoring
- Escrow invariant verification
- Chain verifier availability
- RPC endpoint health

## Future Enhancements

### Planned Features

1. **Bitcoin Support**: Complete BTC address generation and verification
2. **EVM Reverse Flow**: Build/sign transactions for ICP → EVM swaps
3. **Heartbeat Cleanup**: Automatic expiration of old intents
4. **Multi-hop Intents**: Chain multiple swaps (A → B → C)
5. **Partial Fills**: Allow intents to be partially fulfilled
6. **Reputation System**: Track solver performance and reliability

### Scalability Improvements

1. **Sharding**: Distribute intents across multiple pool canisters
2. **Archival**: Move completed intents to archive canister
3. **Batch Processing**: Process multiple verifications in parallel
4. **Optimistic Verification**: Reduce confirmation delays

### Developer Experience

1. **TypeScript SDK**: Client library for web applications
2. **CLI Tool**: Command-line interface for testing
3. **Mock Chains**: Testing framework with mock verifiers
4. **Monitoring Dashboard**: Real-time metrics visualization
