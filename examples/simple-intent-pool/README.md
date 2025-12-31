# Simple Intent Pool Example

This example demonstrates how to use the refactored ICP Intents library in a single-canister deployment.

## Features

- ✅ Intent creation with validation
- ✅ Quote submission from solvers
- ✅ Quote confirmation by users
- ✅ EVM deposit verification (Ethereum, Sepolia)
- ✅ Hoosat deposit verification
- ✅ Multi-token escrow management
- ✅ Protocol fee collection
- ✅ Upgrade-safe state management

## Architecture

```
┌─────────────────────────────────────────┐
│      SimpleIntentPool Canister          │
│  ┌─────────────────────────────────┐   │
│  │  IntentLib (SDK)                │   │
│  │  ├─ IntentManager               │   │
│  │  ├─ Escrow                      │   │
│  │  ├─ FeeManager                  │   │
│  │  └─ ChainRegistry               │   │
│  └─────────────────────────────────┘   │
│  ┌─────────────────────────────────┐   │
│  │  Chain Verifiers                │   │
│  │  ├─ EVM (via EVM RPC canister)  │   │
│  │  └─ Hoosat (via HTTP outcalls)  │   │
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

## Usage

### 1. Deploy the Canister

```bash
# From repository root
dfx start --background
dfx deploy SimpleIntentPool
```

### 2. Create an Intent

Swap 1 ETH for at least 50 HOO:

```bash
dfx canister call SimpleIntentPool createIntent '(
  "ethereum",           // source_chain
  "ETH",                // source_token
  1000000000000000000,  // source_amount (1 ETH in wei)
  "hoosat",             // dest_chain
  "HOO",                // dest_token
  50000000000,          // min_output (50 HOO in hootas)
  "Hoosat:your_address", // dest_recipient
  3600                  // deadline_seconds (1 hour)
)'

# Returns: (variant { ok = 0 : nat })
# Intent ID is 0
```

### 3. Submit a Quote (Solver)

```bash
dfx canister call SimpleIntentPool submitQuote '(
  0,                    // intent_id
  52000000000,          // output_amount (52 HOO - better than minimum)
  1000000000,           // solver_fee (1 HOO)
  500000000,            // solver_tip (0.5 HOO)
)'

# Returns: (variant { ok })
```

### 4. Confirm Quote (User)

```bash
dfx canister call SimpleIntentPool confirmQuote '(
  0,                              // intent_id
  principal "solver-principal-id"  // solver
)'

# Returns: (variant { ok })
```

### 5. Get Deposit Address

```bash
dfx canister call SimpleIntentPool generateDepositAddress '(0)'

# Returns: (variant { ok = "0x1234..." })
# User sends ETH to this address
```

### 6. Verify Deposit

After user sends transaction:

```bash
dfx canister call SimpleIntentPool verifyEVMDeposit '(
  0,                                        // intent_id
  "0xabcdef1234567890..."                  // tx_hash
)'

# Returns: (variant { ok })
# Intent status → Deposited
# Escrow locked
```

### 7. Fulfill Intent

After solver delivers on destination chain:

```bash
dfx canister call SimpleIntentPool fulfillIntent '(0)'

# Returns: (variant { ok = record {
#   protocol_fee = 156000000 : nat;
#   solver_fee = 1000000000 : nat;
#   solver_tip = 500000000 : nat;
#   total_fees = 1656000000 : nat;
#   net_output = 50344000000 : nat;
# }})
```

## Query Functions

### Get Intent

```bash
dfx canister call SimpleIntentPool getIntent '(0)'
```

### Get User Intents

```bash
dfx canister call SimpleIntentPool getUserIntents '(principal "user-id")'
```

### Get Supported Chains

```bash
dfx canister call SimpleIntentPool getSupportedChains '()'

# Returns: (vec { "ethereum"; "sepolia"; "hoosat" })
```

### Get Escrow Balance

```bash
dfx canister call SimpleIntentPool getEscrowBalance '(
  principal "user-id",
  "ETH"
)'

# Returns: (1000000000000000000 : nat)
```

### Get Protocol Fees

```bash
dfx canister call SimpleIntentPool getProtocolFees '()'

# Returns: (vec { record { "HOO"; 156000000 : nat } })
```

## Configuration

Edit `Main.mo` to customize:

### Protocol Fee

```motoko
let config : IntentLib.SystemConfig = {
  protocol_fee_bps = 30; // 0.3% (change this)
  // ...
};
```

### Amount Limits

```motoko
let config : IntentLib.SystemConfig = {
  min_amount = 1_000_000;              // Minimum intent amount
  max_amount = 1_000_000_000_000_000;  // Maximum intent amount
  // ...
};
```

### Deadline Limits

```motoko
let config : IntentLib.SystemConfig = {
  max_deadline = 86_400_000_000_000; // 24 hours in nanoseconds
  // ...
};
```

### EVM RPC Canister

```motoko
let evm_config : EVM.Config = {
  evm_rpc_canister = Principal.fromText("7hfb6-caaaa-aaaar-qadga-cai"); // Mainnet
  // evm_rpc_canister = Principal.fromText("a4gq6-oaaaa-aaaab-qaa4q-cai"); // Testnet
  // ...
};
```

### ECDSA Key

```motoko
let evm_config : EVM.Config = {
  ecdsa_key_name = "key_1"; // Mainnet
  // ecdsa_key_name = "test_key_1"; // Testnet
  // ...
};
```

## Adding Support for New Chains

### 1. Register the Chain

```motoko
// In initializeChains()
IntentLib.registerChain(state, "base", #EVM({
  chain_id = 8453;
  name = "Base Mainnet";
  network = "mainnet";
}));
```

### 2. Update Configuration

If using custom verifier:

```motoko
let base_config : EVM.Config = {
  evm_rpc_canister = Principal.fromText("...");
  min_confirmations = 6;
  ecdsa_key_name = "key_1";
};
```

### 3. Add Verification Function

```motoko
public shared func verifyBaseDeposit(
  intent_id : Nat,
  tx_hash : Text
) : async IntentLib.IntentResult<()> {
  // Similar to verifyEVMDeposit
  // Use base_config instead of evm_config
}
```

## Error Handling

All functions return `IntentResult<T>`:

```motoko
type IntentResult<T> = {
  #ok : T;
  #err : IntentError;
};
```

### Common Errors

- `#NotFound` - Intent doesn't exist
- `#Expired` - Intent deadline passed
- `#InvalidStatus` - Wrong status for operation
- `#ChainNotSupported` - Chain not registered
- `#InsufficientBalance` - Not enough in escrow
- `#InsufficientCycles` - Need more cycles
- `#VerificationFailed` - Deposit verification failed

### Example Error Handling

```motoko
switch (await createIntent(...)) {
  case (#ok(intent_id)) {
    Debug.print("Created intent #" # Nat.toText(intent_id));
  };
  case (#err(#InvalidAmount(msg))) {
    Debug.print("Invalid amount: " # msg);
  };
  case (#err(#ChainNotSupported(chain))) {
    Debug.print("Chain not supported: " # chain);
  };
  case (#err(error)) {
    Debug.print("Error: " # IntentLib.errorToText(error));
  };
}
```

## Testing

### Local Testing

```bash
# Deploy to local replica
dfx start --clean --background
dfx deploy SimpleIntentPool

# Run test script
./test.sh
```

### Testnet Testing

```bash
# Deploy to IC testnet
dfx deploy --network ic --mode reinstall SimpleIntentPool

# Use Sepolia for testing
dfx canister call SimpleIntentPool createIntent '(
  "sepolia",  // Testnet chain
  "ETH",
  1000000000000000000,
  "hoosat",
  "HOO",
  50000000000,
  "Hoosat:your_address",
  3600
)' --network ic
```

## Monitoring

### Check Cycle Balance

```bash
dfx canister status SimpleIntentPool
```

### View Logs

```bash
dfx canister logs SimpleIntentPool
```

### Verify Escrow Invariants

After upgrade or periodically:

```motoko
// In postupgrade()
if (not IntentLib.verifyEscrowInvariants(state)) {
  Debug.print("⚠️ Escrow invariants violated!");
}
```

## Upgrading

### Before Upgrade

```bash
# Check current state
dfx canister call SimpleIntentPool getProtocolFees
dfx canister call SimpleIntentPool getSupportedChains
```

### Perform Upgrade

```bash
dfx deploy SimpleIntentPool --mode upgrade
```

### After Upgrade

```bash
# Check logs for invariant verification
dfx canister logs SimpleIntentPool

# Verify state preserved
dfx canister call SimpleIntentPool getProtocolFees
dfx canister call SimpleIntentPool getSupportedChains
```

## Production Checklist

Before deploying to mainnet:

- [ ] Update EVM RPC canister to mainnet ID
- [ ] Change ECDSA key from `test_key_1` to `key_1`
- [ ] Set appropriate protocol fee (e.g., 0.3%)
- [ ] Set reasonable amount limits
- [ ] Set maximum deadline (e.g., 24 hours)
- [ ] Configure solver whitelist if needed
- [ ] Test on testnet first
- [ ] Monitor cycle balance
- [ ] Set up monitoring/alerting
- [ ] Document emergency procedures
- [ ] Review security considerations

## Troubleshooting

### "ChainNotSupported" Error

**Cause**: Chain not registered

**Fix**: Add chain in `initializeChains()`:

```motoko
IntentLib.registerChain(state, "your_chain", #EVM({...}));
```

### "InsufficientCycles" Error

**Cause**: Canister needs more cycles

**Fix**: Top up cycles:

```bash
dfx canister deposit-cycles 1000000000000 SimpleIntentPool
```

### Verification Always Pending

**Cause**: Not enough confirmations or wrong RPC

**Fix**:
- Check `min_confirmations` setting
- Verify RPC canister is correct
- Wait for more block confirmations

### Escrow Invariant Violation

**Cause**: State corruption during upgrade

**Fix**:
- Review preupgrade/postupgrade logs
- May need manual correction
- Contact support if persistent

## Support

- **Documentation**: See `../../docs/ARCHITECTURE.md`
- **Migration Guide**: See `../../docs/MIGRATION.md`
- **Issues**: https://github.com/your-org/icp-intents/issues
