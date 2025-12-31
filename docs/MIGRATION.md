# Migration Guide: Legacy → Refactored ICP Intents Library

This guide helps you migrate from the legacy prototype implementation to the production-grade refactored library.

## Table of Contents

- [Overview](#overview)
- [Breaking Changes](#breaking-changes)
- [Step-by-Step Migration](#step-by-step-migration)
- [Code Examples](#code-examples)
- [Common Patterns](#common-patterns)
- [Troubleshooting](#troubleshooting)

## Overview

### What Changed

The refactored library introduces:

1. **Chain Abstraction**: Explicit `Chain` variant types instead of hardcoded chains
2. **State Machine**: Explicit `IntentStatus` with validated transitions
3. **Module Organization**: Clear separation into core/, chains/, managers/, utils/
4. **Multi-Token Escrow**: HashMap-based with composite keys
5. **Fee System**: Separate protocol, solver, and tip fees
6. **Error Handling**: Comprehensive error taxonomy with `IntentResult<T>`
7. **Type Safety**: More explicit types, fewer `Any` or optional fields

### Backward Compatibility

⚠️ **This is a breaking change release.** The refactored library is NOT backward compatible with the legacy version. You must migrate your code.

### Migration Timeline

Recommended approach:
1. **Week 1**: Review new architecture, update development environment
2. **Week 2**: Migrate core intent logic, test with legacy data
3. **Week 3**: Update chain-specific code, test verification
4. **Week 4**: Deploy to testnet, monitor, fix issues
5. **Week 5+**: Deploy to mainnet with migration plan for existing intents

## Breaking Changes

### 1. Import Paths Changed

**Before:**
```motoko
import Types "../icp-intents-lib/Types";
import Utils "../icp-intents-lib/Utils";
import Verification "../icp-intents-lib/Verification";
import TECDSA "../icp-intents-lib/TECDSA";
```

**After:**
```motoko
import IntentLib "../icp-intents-lib/IntentLib";
// Or import specific modules:
import Types "../icp-intents-lib/core/Types";
import TECDSA "../icp-intents-lib/crypto/TECDSA";
import EVM "../icp-intents-lib/chains/EVM";
```

### 2. Intent Type Structure

**Before:**
```motoko
type Intent = {
  id : Nat;
  user : Principal;
  source_chain : Text; // Just a string
  dest_chain : Text;   // Just a string
  status : Text;       // String status
  // ... other fields
};
```

**After:**
```motoko
type Intent = {
  id : Nat;
  user : Principal;
  source : ChainSpec;      // Structured type
  destination : ChainSpec;  // Structured type
  status : IntentStatus;    // Variant type
  quotes : [Quote];         // Explicit quotes array
  selected_quote : ?Quote;  // Selected quote
  escrow_balance : Nat;     // Tracked balance
  // ... other fields
};

type ChainSpec = {
  chain : Text;
  chain_id : ?Nat;
  token : Text;
  network : Text;
};

type IntentStatus = {
  #PendingQuote;
  #Quoted;
  #Confirmed;
  #Deposited;
  #Fulfilled;
  #Cancelled;
  #Expired;
};
```

### 3. Chain Registration Required

**Before:**
```motoko
// Chains were hardcoded
let intent = {
  source_chain = "ethereum";
  dest_chain = "hoosat";
  // ...
};
```

**After:**
```motoko
// Must register chains first
IntentLib.registerChain(state, "ethereum", #EVM({
  chain_id = 1;
  name = "Ethereum Mainnet";
  network = "mainnet";
}));

IntentLib.registerChain(state, "hoosat", #Hoosat({
  network = "mainnet";
  rpc_url = "https://api.network.hoosat.fi";
  min_confirmations = 10;
}));
```

### 4. Initialization Changed

**Before:**
```motoko
stable var intents = TrieMap.TrieMap<Nat, Intent>();
stable var next_id = 0;
```

**After:**
```motoko
import IntentLib "../icp-intents-lib/IntentLib";

stable var stable_data : ?IntentLib.StableManagerData = null;
var state : IntentLib.ManagerState = IntentLib.init({
  protocol_fee_bps = 30; // 0.3%
  min_amount = 1_000_000; // Minimum intent amount
  max_amount = 1_000_000_000_000; // Maximum intent amount
  max_deadline = 86_400_000_000_000; // 24 hours in nanoseconds
  allowed_solvers = null; // null = all allowed
});

system func preupgrade() {
  stable_data := ?IntentLib.toStable(state);
};

system func postupgrade() {
  state := switch (stable_data) {
    case (?data) {
      IntentLib.fromStable(data, state.config)
    };
    case null { state };
  };
  stable_data := null;
};
```

### 5. Error Handling Pattern

**Before:**
```motoko
public func doSomething() : async ?Result {
  // ... might trap or return null
};
```

**After:**
```motoko
public func doSomething() : async IntentLib.IntentResult<Result> {
  switch (await operation()) {
    case (#ok(value)) { #ok(value) };
    case (#err(error)) { #err(error) };
  }
};

// Usage:
switch (await doSomething()) {
  case (#ok(result)) {
    // Success
  };
  case (#err(#NotFound)) {
    // Handle not found
  };
  case (#err(#InsufficientBalance)) {
    // Handle insufficient balance
  };
  case (#err(error)) {
    // Handle other errors
    Debug.print("Error: " # IntentLib.errorToText(error));
  };
};
```

### 6. Fee Structure

**Before:**
```motoko
// Single protocol fee
let fee = (amount * 30) / 10_000; // 0.3%
```

**After:**
```motoko
// Comprehensive fee breakdown
let fees : FeeBreakdown = IntentLib.calculateFees(
  output_amount,
  protocol_fee_bps,
  quote
);

// fees.protocol_fee - Platform fee
// fees.solver_fee - Solver's fee
// fees.solver_tip - Optional tip
// fees.total_fees - Sum of all fees
// fees.net_output - Amount user receives
```

## Step-by-Step Migration

### Step 1: Update Dependencies

```bash
# Pull latest changes
git pull origin main

# Verify new structure exists
ls src/icp-intents-lib/
# Should see: core/ chains/ managers/ utils/ crypto/ IntentLib.mo
```

### Step 2: Migrate Actor Initialization

**Legacy Code:**
```motoko
actor IntentPool {
  stable var intents : [(Nat, Types.Intent)] = [];
  stable var next_id : Nat = 0;
  var intent_map = TrieMap.TrieMap<Nat, Types.Intent>();

  system func preupgrade() {
    intents := Iter.toArray(intent_map.entries());
  };

  system func postupgrade() {
    for ((id, intent) in intents.vals()) {
      intent_map.put(id, intent);
    };
    intents := [];
  };
}
```

**Migrated Code:**
```motoko
import IntentLib "../icp-intents-lib/IntentLib";
import Time "mo:base/Time";

actor IntentPool {
  // Stable storage
  stable var stable_data : ?IntentLib.StableManagerData = null;

  // Runtime state
  let config : IntentLib.SystemConfig = {
    protocol_fee_bps = 30;
    min_amount = 1_000_000;
    max_amount = 1_000_000_000_000;
    max_deadline = 86_400_000_000_000;
    allowed_solvers = null;
  };

  var state : IntentLib.ManagerState = IntentLib.init(config);

  // Register supported chains
  private func initChains() {
    IntentLib.registerChain(state, "ethereum", #EVM({
      chain_id = 1;
      name = "Ethereum Mainnet";
      network = "mainnet";
    }));

    IntentLib.registerChain(state, "hoosat", #Hoosat({
      network = "mainnet";
      rpc_url = "https://api.network.hoosat.fi";
      min_confirmations = 10;
    }));
  };

  // Initialize chains on deploy
  initChains();

  // Upgrade hooks
  system func preupgrade() {
    stable_data := ?IntentLib.toStable(state);
  };

  system func postupgrade() {
    state := switch (stable_data) {
      case (?data) {
        IntentLib.fromStable(data, config)
      };
      case null { state };
    };
    stable_data := null;

    // Verify invariants
    if (not IntentLib.verifyEscrowInvariants(state)) {
      Debug.trap("Escrow invariants violated!");
    };

    // Re-register chains
    initChains();
  };
}
```

### Step 3: Migrate Intent Creation

**Legacy Code:**
```motoko
public shared({ caller }) func createIntent(
  source_chain : Text,
  dest_chain : Text,
  amount : Nat,
  min_output : Nat,
  recipient : Text,
  deadline : Time.Time
) : async Nat {
  let id = next_id;
  next_id += 1;

  let intent = {
    id = id;
    user = caller;
    source_chain = source_chain;
    dest_chain = dest_chain;
    amount = amount;
    min_output = min_output;
    recipient = recipient;
    deadline = deadline;
    status = "pending";
  };

  intent_map.put(id, intent);
  id
};
```

**Migrated Code:**
```motoko
public shared({ caller }) func createIntent(
  source_chain : Text,
  source_token : Text,
  dest_chain : Text,
  dest_token : Text,
  source_amount : Nat,
  min_output : Nat,
  dest_recipient : Text,
  deadline : Time.Time
) : async IntentLib.IntentResult<Nat> {
  let source : IntentLib.ChainSpec = {
    chain = source_chain;
    chain_id = null; // Or pass from caller
    token = source_token;
    network = "mainnet";
  };

  let destination : IntentLib.ChainSpec = {
    chain = dest_chain;
    chain_id = null;
    token = dest_token;
    network = "mainnet";
  };

  IntentLib.createIntent(
    state,
    caller,
    source,
    destination,
    source_amount,
    min_output,
    dest_recipient,
    deadline,
    Time.now()
  )
};
```

### Step 4: Migrate Quote Submission

**Legacy Code:**
```motoko
public shared({ caller }) func submitQuote(
  intent_id : Nat,
  output_amount : Nat
) : async Bool {
  switch (intent_map.get(intent_id)) {
    case null { false };
    case (?intent) {
      // Add quote logic
      true
    };
  }
};
```

**Migrated Code:**
```motoko
public shared({ caller }) func submitQuote(
  intent_id : Nat,
  output_amount : Nat,
  fee : Nat,
  tip : Nat
) : async IntentLib.IntentResult<()> {
  IntentLib.submitQuote(
    state,
    intent_id,
    caller, // solver
    output_amount,
    fee,
    tip,
    null, // solver_dest_address (optional)
    Time.now()
  )
};
```

### Step 5: Migrate Verification

**Legacy Code:**
```motoko
import Verification "../icp-intents-lib/Verification";

public func verifyDeposit(
  intent_id : Nat,
  tx_hash : Text
) : async Result {
  let config = {
    evm_rpc_canister_id = Principal.fromText("...");
    min_confirmations = 6;
  };

  // Manual verification logic
  let rpc = Verification.getEVMRPC(config.evm_rpc_canister_id);
  // ... complex verification
};
```

**Migrated Code:**
```motoko
import EVM "../icp-intents-lib/chains/EVM";

public func verifyDeposit(
  intent_id : Nat,
  tx_hash : Text,
  expected_address : Text,
  expected_amount : Nat
) : async IntentLib.IntentResult<()> {
  let intent = switch (IntentLib.getIntent(state, intent_id)) {
    case null { return #err(#NotFound) };
    case (?i) { i };
  };

  let config : EVM.Config = {
    evm_rpc_canister = Principal.fromText("7hfb6-caaaa-aaaar-qadga-cai");
    min_confirmations = 6;
    ecdsa_key_name = "key_1";
  };

  let request : IntentLib.VerificationRequest = {
    chain = #EVM({
      chain_id = 1;
      name = "Ethereum";
      network = "mainnet";
    });
    proof = #EVM({
      tx_hash = tx_hash;
      block_number = 0;
      from_address = "";
      to_address = expected_address;
      value = expected_amount;
      confirmations = 0;
    });
    expected_address = expected_address;
    expected_amount = expected_amount;
  };

  switch (await EVM.verify(config, request)) {
    case (#Success(data)) {
      // Mark as deposited
      IntentLib.verifyAndMarkDeposited(
        state,
        intent_id,
        data.verified_amount,
        Time.now()
      )
    };
    case (#Pending(_)) {
      #err(#InvalidStatus("Deposit not yet confirmed"))
    };
    case (#Failed(msg)) {
      #err(#VerificationFailed(msg))
    };
  }
};
```

## Code Examples

### Complete Actor Example

See `examples/single-canister/IntentPool.mo` for a complete working example.

### Multi-Canister Setup

See `examples/multi-canister/` for:
- IntentPool canister
- EscrowManager canister
- EVMVerifier canister
- HoosatVerifier canister

## Common Patterns

### Pattern 1: Checking Intent Status

**Before:**
```motoko
if (intent.status == "confirmed") {
  // ...
}
```

**After:**
```motoko
switch (intent.status) {
  case (#Confirmed) {
    // ...
  };
  case _ {
    // Wrong status
  };
}

// Or use helper:
if (IntentLib.canBeConfirmed(intent)) {
  // ...
}
```

### Pattern 2: Error Propagation

**Before:**
```motoko
public func operation() : async ?Result {
  let step1 = await doStep1();
  if (step1 == null) { return null };
  // ...
};
```

**After:**
```motoko
public func operation() : async IntentLib.IntentResult<Result> {
  let result1 = switch (await doStep1()) {
    case (#ok(value)) { value };
    case (#err(e)) { return #err(e) };
  };

  let result2 = switch (await doStep2(result1)) {
    case (#ok(value)) { value };
    case (#err(e)) { return #err(e) };
  };

  #ok(result2)
};
```

### Pattern 3: Fee Handling

**Before:**
```motoko
let protocol_fee = (amount * 30) / 10_000;
let net = amount - protocol_fee;
```

**After:**
```motoko
let fees = IntentLib.calculateFees(
  quote.output_amount,
  intent.protocol_fee_bps,
  quote
);

// Use fees.net_output for user payout
// fees.protocol_fee goes to protocol
// fees.solver_fee + fees.solver_tip goes to solver
```

## Troubleshooting

### Issue: "ChainNotSupported" Error

**Cause**: Chain not registered before use

**Solution**:
```motoko
// Add this in actor initialization
IntentLib.registerChain(state, "your_chain", #EVM({
  chain_id = 1;
  name = "Chain Name";
  network = "mainnet";
}));

// Verify registration
if (not IntentLib.isChainSupported(state, "your_chain")) {
  Debug.print("Chain not registered!");
};
```

### Issue: Escrow Invariant Violation

**Cause**: Escrow state corrupted during upgrade

**Solution**:
```motoko
system func postupgrade() {
  state := IntentLib.fromStable(stable_data, config);

  // Verify invariants
  if (not IntentLib.verifyEscrowInvariants(state)) {
    Debug.print("⚠️ Escrow invariants violated!");
    // Investigate: check total_locked vs sum of balances
    // May need manual correction
  };
};
```

### Issue: Type Mismatch Errors

**Cause**: Using old Types.mo definitions

**Solution**:
```motoko
// Use IntentLib types
import IntentLib "../icp-intents-lib/IntentLib";

type Intent = IntentLib.Intent;
type Quote = IntentLib.Quote;
type IntentStatus = IntentLib.IntentStatus;
```

### Issue: "Unbound variable" Errors

**Cause**: Import paths changed

**Solution**:
```motoko
// Old imports - DON'T USE
// import Types "../icp-intents-lib/Types";

// New imports
import IntentLib "../icp-intents-lib/IntentLib";
// Or specific modules:
import Types "../icp-intents-lib/core/Types";
```

## Data Migration

### Migrating Existing Intents

If you have existing intents in production:

1. **Export Legacy Data**:
   ```motoko
   public query func exportLegacyIntents() : async [(Nat, LegacyIntent)] {
     Iter.toArray(legacy_intent_map.entries())
   };
   ```

2. **Transform to New Format**:
   ```motoko
   func migrateLegacyIntent(legacy : LegacyIntent) : Intent {
     {
       id = legacy.id;
       user = legacy.user;
       source = {
         chain = legacy.source_chain;
         chain_id = null;
         token = legacy.source_token;
         network = "mainnet";
       };
       destination = {
         chain = legacy.dest_chain;
         chain_id = null;
         token = legacy.dest_token;
         network = "mainnet";
       };
       source_amount = legacy.amount;
       min_output = legacy.min_output;
       dest_recipient = legacy.recipient;
       deadline = legacy.deadline;
       status = migrateStatus(legacy.status);
       quotes = [];
       selected_quote = null;
       escrow_balance = 0;
       protocol_fee_bps = 30;
       created_at = legacy.created_at;
       updated_at = legacy.updated_at;
     }
   };

   func migrateStatus(legacy : Text) : IntentStatus {
     switch (legacy) {
       case ("pending") { #PendingQuote };
       case ("quoted") { #Quoted };
       case ("confirmed") { #Confirmed };
       case ("fulfilled") { #Fulfilled };
       case ("cancelled") { #Cancelled };
       case _ { #Expired };
     }
   };
   ```

3. **Import to New System**:
   ```motoko
   public func importMigratedIntents(intents : [(Nat, Intent)]) : async () {
     for ((id, intent) in intents.vals()) {
       // Add to new state
       // This is internal - not exposed in IntentLib
       // You may need to add a migration helper function
     };
   };
   ```

## Testing Your Migration

### Unit Tests

```motoko
import { test } "mo:test";

test("migrated intent has correct status", func() {
  let legacy = { status = "confirmed"; /* ... */ };
  let migrated = migrateLegacyIntent(legacy);

  switch (migrated.status) {
    case (#Confirmed) { assert true };
    case _ { assert false };
  }
});
```

### Integration Tests

1. Deploy to testnet
2. Create test intent with new API
3. Submit quote
4. Verify deposit
5. Fulfill intent
6. Check escrow invariants
7. Verify fees collected

## Getting Help

- **Documentation**: See `docs/ARCHITECTURE.md` for system design
- **Examples**: Check `examples/` directory
- **Issues**: Report problems at https://github.com/anthropics/icp-intents/issues
- **Discussions**: Ask questions in GitHub Discussions

## Checklist

Before deploying to production:

- [ ] All imports updated to new paths
- [ ] Actor initialization migrated to IntentLib
- [ ] Chains registered properly
- [ ] Error handling uses IntentResult<T>
- [ ] Fee calculations updated
- [ ] Upgrade hooks implemented with invariant checks
- [ ] Legacy data migration plan ready
- [ ] Tested on testnet
- [ ] Monitoring/logging updated for new event format
- [ ] Frontend updated to handle new types
- [ ] Cycle management reviewed

## Timeline Estimate

- **Small project** (< 1000 LOC): 1-2 weeks
- **Medium project** (1000-5000 LOC): 2-4 weeks
- **Large project** (> 5000 LOC): 4-8 weeks

Add 1-2 weeks if you have production data to migrate.
