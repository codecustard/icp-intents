# ICP Intents - Deployment Guide

Complete guide for deploying the ICP Intents library and example canisters.

## Prerequisites

1. **Install dfx**
   ```bash
   sh -ci "$(curl -fsSL https://internetcomputer.org/install.sh)"
   ```

2. **Install mops**
   ```bash
   npm install -g ic-mops
   ```

3. **Install dependencies**
   ```bash
   mops install
   ```

## Local Development

### 1. Start Local Replica

```bash
dfx start --clean --background
```

### 2. Deploy Library (for testing)

The library modules are imported directly, so no separate deployment needed.

### 3. Deploy Example Canister

```bash
dfx deploy BasicIntentCanister
```

### 4. Test Basic Functionality

```bash
# Get canister ID
export CANISTER_ID=$(dfx canister id BasicIntentCanister)

# Post a test intent
dfx canister call BasicIntentCanister postIntent '(
  record {
    source_amount = 1_000_000;
    source_token = "ICP";
    dest_chain = "ethereum";
    dest_chain_id = 1;
    dest_token_address = "native";
    dest_recipient = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0";
    min_output = 900_000;
    deadline = 9999999999000000000;
    custom_rpc_urls = null;
    verification_hints = null;
    metadata = null;
  }
)'

# Get intents
dfx canister call BasicIntentCanister getIntents '(0, 10)'

# Check stats
dfx canister call BasicIntentCanister getStats
```

## IC Mainnet Deployment

### 1. Create Canister

```bash
dfx canister create BasicIntentCanister --network ic --with-cycles 10000000000000
```

### 2. Update Configuration

Edit `src/examples/BasicIntentCanister.mo`:

```motoko
// Change to mainnet tECDSA key
transient let tecdsaConfig : Types.ECDSAConfig = {
  key_name = "key_1";  // Mainnet key
  derivation_path = [];
};

// Update EVM RPC canister ID (mainnet)
transient let verificationConfig = {
  evm_rpc_canister_id = Principal.fromText("7hfb6-caaaa-aaaar-qadga-cai");
  min_confirmations = 12;
};
```

### 3. Deploy

```bash
dfx deploy BasicIntentCanister --network ic
```

### 4. Monitor Cycles

```bash
dfx canister status BasicIntentCanister --network ic
```

### 5. Top Up Cycles

```bash
dfx ledger top-up BasicIntentCanister --amount 5.0 --network ic
```

## Building Your Own Canister

### Option 1: Use Full System

```motoko
import IntentManager "mo:icp-intents-lib/IntentManager";
import Types "mo:icp-intents-lib/Types";

shared(init_msg) persistent actor class MyIntentSystem() = self {
  transient var state = IntentManager.init(/* config */);

  public shared(msg) func postIntent(req: Types.CreateIntentRequest) : async Types.IntentResult<Nat> {
    await IntentManager.postIntent(state, msg.caller, req, Time.now())
  };
}
```

### Option 2: Use Escrow Only (for DEX)

```motoko
import Escrow "mo:icp-intents-lib/Escrow";

actor MyDEX {
  var escrow = Escrow.init();

  public shared(msg) func deposit(token: Text, amount: Nat) : async Types.IntentResult<()> {
    Escrow.deposit(escrow, msg.caller, token, amount)
  };
}
```

## Production Checklist

### Security

- [ ] Replace mock keccak256 in `TECDSA.mo`
- [ ] Use mainnet tECDSA key (`key_1`)
- [ ] Configure correct EVM RPC canister ID
- [ ] Set appropriate protocol fees
- [ ] Configure admin principal
- [ ] Test all error paths
- [ ] Audit escrow accounting

### Performance

- [ ] Load test with 1000+ intents
- [ ] Monitor cycle consumption
- [ ] Optimize query functions
- [ ] Implement pagination limits
- [ ] Set up cycle monitoring

### Upgradeability

- [ ] Test upgrade on testnet
- [ ] Implement pre/post upgrade hooks
- [ ] Backup state before upgrade
- [ ] Plan rollback strategy

### Monitoring

- [ ] Set up cycle alerts
- [ ] Monitor intent fulfillment rates
- [ ] Track failed verifications
- [ ] Log important events

## Troubleshooting

### Issue: tECDSA fails

**Solution**: Ensure you're using correct key name:
- Local: `test_key_1`
- Mainnet: `key_1`

### Issue: EVM RPC verification fails

**Solution**:
- Check EVM RPC canister is funded
- Verify chain ID is correct
- Ensure sufficient confirmations

### Issue: Escrow imbalance

**Solution**: Check test suite in `test/Escrow.test.mo` for invariants.

### Issue: Out of cycles

**Solution**:
```bash
dfx ledger top-up CANISTER_ID --amount 5.0 --network ic
```

## Cycle Cost Estimates

Approximate cycle costs (subject to change):

- Post intent: ~500M cycles
- Submit quote: ~50M cycles
- Confirm quote (with tECDSA): ~5B cycles
- Verify deposit (EVM RPC): ~1B cycles
- Claim fulfillment: ~2B cycles

**Recommended**: Start with 10T cycles, monitor, and adjust.

## Support

- GitHub Issues: Report bugs
- Documentation: See README.md
- Examples: See `src/examples/`

## Next Steps

1. Review security considerations in README.md
2. Run comprehensive tests
3. Deploy to testnet first
4. Get external audit if handling significant value
5. Monitor and optimize

---

**Good luck with your deployment!** 🚀
