# ICP Intents Solver Bot Example

Educational TypeScript/Node.js solver bot demonstrating the complete solver workflow for the [ICP Intents SDK](https://github.com/codecustard/icp-intents).

**Educational Demo - NOT for Production Use**

## Overview

This solver bot demonstrates the complete solver workflow:

1. **Monitor** - Poll intent pool for new intents
2. **Quote** - Calculate competitive quotes based on pricing logic
3. **Fulfill** - Deliver tokens on destination chain after deposit

### Features

- Polling-based intent monitoring
- Mock pricing with configurable exchange rates
- Simulated fulfillment (no real blockchain transactions)
- Retry logic with exponential backoff
- Structured logging with colors
- Clean shutdown handling

### Architecture

```
┌─────────────────────┐
│   Intent Pool       │  ← Canister on IC
│   (Motoko)          │
└──────────┬──────────┘
           │
           │ Query/Update calls
           │
┌──────────▼──────────┐
│  Solver Bot (TS)    │
│                     │
│  ┌───────────────┐  │
│  │ IntentMonitor │  │  Poll for new intents
│  └───────┬───────┘  │
│          │          │
│  ┌───────▼───────┐  │
│  │ IntentFilter  │  │  Check capabilities
│  └───────┬───────┘  │
│          │          │
│  ┌───────▼───────┐  │
│  │ MockPricing   │  │  Calculate quotes
│  └───────┬───────┘  │
│          │          │
│  ┌───────▼───────┐  │
│  │ MockFulfill   │  │  Simulate delivery
│  └───────────────┘  │
└─────────────────────┘
```

## Quick Start

### Prerequisites

- Node.js 18+ and npm
- dfx (DFINITY SDK) installed
- Running local IC replica or access to IC testnet

### 1. Install Dependencies

```bash
cd examples/solver-bot
npm install
```

### 2. Deploy Intent Pool Canister

```bash
# Terminal 1: Start local replica
dfx start --clean

# Terminal 2: Deploy
cd ../..  # Back to root
dfx deploy SimpleIntentPool
```

Note the canister ID from the deployment output.

### 3. Configure Environment

```bash
cd examples/solver-bot
cp .env.example .env
```

Edit `.env` and set:
- `INTENT_POOL_CANISTER_ID` - Your deployed canister ID
- Other settings as needed (see Configuration section)

**Note:** A solver identity will be automatically generated on first run and saved to `identity.json`. The solver's principal will be displayed in the logs.

### 4. Run the Bot

```bash
# Development mode with auto-reload
npm run dev

# Or build and run
npm run build
npm start
```

On first run, you'll see:
```
[INFO] No identity file found, generating new identity
[INFO] New identity generated and saved
[INFO] Solver bot initialized principal: xxxxx-xxxxx-xxxxx-xxxxx
```

## Configuration

All configuration is via environment variables in `.env`:

### IC Network

```bash
IC_NETWORK=local                                    # Options: local, ic
INTENT_POOL_CANISTER_ID=rrkah-fqaaa-aaaaa-aaaaq-cai # Your canister ID
SOLVER_IDENTITY_PATH=./identity.json                # Path to identity file (auto-generated)
```

### Monitoring

```bash
POLLING_INTERVAL_MS=5000                            # Poll every 5 seconds
```

### Profitability

```bash
MIN_PROFIT_BPS=50                                   # Minimum 0.5% profit
```

### Exchange Rates (Demo)

Fixed exchange rates for demo purposes:

```bash
RATE_ETH_HOO=50000                                  # 1 ETH = 50000 HOO
RATE_ICP_ETH=0.002                                  # 1 ICP = 0.002 ETH
RATE_ICP_HOO=100                                    # 1 ICP = 100 HOO
RATE_HOO_ETH=0.00002                                # 1 HOO = 0.00002 ETH
```

Add any `RATE_<SOURCE>_<DEST>` pairs you need.

### Supported Assets

```bash
SUPPORTED_CHAINS=ethereum,sepolia,hoosat,icp
SUPPORTED_TOKENS=ETH,ICP,HOO,USDC
```

### Fees

```bash
DEFAULT_SOLVER_FEE_BPS=30                           # 0.3% solver fee
DEFAULT_SOLVER_TIP_BPS=10                           # 0.1% solver tip
```

## Testing

### Manual Testing

#### 1. Start Components

```bash
# Terminal 1: dfx
dfx start --clean
dfx deploy SimpleIntentPool

# Terminal 2: Solver bot
cd examples/solver-bot
npm run dev
```

#### 2. Create Test Intent

```bash
# Terminal 3: Create intent
dfx canister call SimpleIntentPool createIntent '(
  "ethereum",        // source chain
  "ETH",            // source token
  1000000000000000000,  // 1 ETH (18 decimals)
  "hoosat",         // dest chain
  "HOO",            // dest token
  50000000000000000000000,  // min 50000 HOO
  "hoosat:qz1234...",      // dest address
  3600              // deadline: 1 hour
)'
```

You should see the bot:
1. Detect the new intent
2. Calculate a quote
3. Submit the quote

#### 3. Confirm Quote

```bash
# Get intent ID from bot logs (e.g., 0)
dfx canister call SimpleIntentPool confirmQuote '(
  0,                                    // intent ID
  principal "xxxxx-xxxxx-xxxxx-xxxxx"  // solver principal
)'
```

#### 4. Verify Deposit

For EVM chains:

```bash
dfx canister call SimpleIntentPool verifyEVMDeposit '(
  0,                                    // intent ID
  "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"  // tx hash
)'
```

The bot should:
1. Detect the deposited intent
2. Simulate fulfillment
3. Call fulfillIntent

## Code Structure

```
src/
├── index.ts                  # Main entry point with monitoring loop
├── config.ts                 # Configuration loader (.env)
├── agent.ts                  # IC Agent setup
├── types/
│   └── intent-pool.ts       # TypeScript types from Candid
├── idl/
│   └── intent-pool.idl.ts   # IDL factory for Candid interface
├── monitor/
│   ├── IntentMonitor.ts     # Poll intent pool
│   └── IntentFilter.ts      # Filter by capabilities
├── pricing/
│   └── MockPricing.ts       # Fixed-rate pricing
├── fulfillment/
│   └── MockFulfillment.ts   # Simulated token delivery
└── utils/
    ├── logger.ts             # Structured logging
    └── retry.ts              # Exponential backoff
```

## Extending for Production

This is an educational demo with **mock components**. For production:

### 1. Real Pricing

Replace `MockPricing` with real price feeds:

```typescript
class RealPricing {
  async getSpotPrice(source: string, dest: string): Promise<number> {
    // Call DEX APIs, oracles, etc.
  }

  calculateSlippage(amount: bigint): bigint {
    // Factor in liquidity, market depth
  }
}
```

**Integrations:**
- DEX APIs (Uniswap, PancakeSwap, etc.)
- Price oracles (Chainlink, Pyth, etc.)
- CEX APIs for market data

### 2. Real Fulfillment

Replace `MockFulfillment` with actual blockchain transactions:

```typescript
class RealFulfillment {
  async sendEVM(intent: Intent, quote: Quote): Promise<string> {
    // Connect to Ethereum wallet
    // Send transaction
    // Return tx hash
  }

  async sendHoosat(intent: Intent, quote: Quote): Promise<string> {
    // Connect to Hoosat wallet
    // Build and sign transaction
    // Broadcast and return tx hash
  }
}
```

**Integrations:**
- ethers.js / viem for EVM chains
- Hoosat SDK for Hoosat
- ICRC ledger canisters for ICP

### 3. Event-Driven Architecture

Instead of polling, listen for events:

```typescript
class EventMonitor {
  async subscribeToIntents(): Promise<void> {
    // Subscribe to on-chain events
    // React to IntentCreated, QuoteConfirmed, etc.
  }
}
```

**Options:**
- IC event subscription (when available)
- Webhook endpoints
- WebSocket connections

### 4. Database & Analytics

Add persistent storage:

```typescript
class IntentDatabase {
  async storeIntent(intent: Intent): Promise<void>;
  async getActiveIntents(): Promise<Intent[]>;
  async calculateProfit(timeRange: string): Promise<Metrics>;
}
```

**Tech Stack:**
- PostgreSQL / MongoDB for intent history
- Redis for caching
- Grafana for metrics

### 5. Advanced Features

- **Batching**: Fulfill multiple intents in one transaction
- **Hedging**: Pre-position assets to reduce risk
- **Portfolio Management**: Balance across multiple chains
- **Health Checks**: Monitor system status
- **Alerting**: Notify on errors or low balances

## Troubleshooting

### Identity Issues

The bot automatically generates an identity file (`identity.json`) on first run. If you want to use a specific identity:

1. Delete the auto-generated `identity.json`
2. The bot will generate a new one on next run

**Note:** The identity format is JSON, not PEM. If you have an existing dfx identity, you'll need to add it to the allowlist using its principal.

### Bot can't connect to canister

```
Error: Call failed: Reject code: 5
```

**Solutions:**
1. Verify canister ID in `.env`
2. Check dfx is running: `dfx ping`
3. Verify identity has access: `dfx identity whoami`

### No intents detected

**Reasons:**
- No intents exist in pool
- Intent filters too restrictive
- Intent already has quotes

**Debug:**
```bash
# Check if intents exist
dfx canister call SimpleIntentPool getIntent '(0)'

# Try creating a test intent (see Testing section)
```

### Quote submission fails

```
Error: InvalidQuote
```

**Reasons:**
- Quote output < min_output
- Quote expiry invalid
- Solver not in allowlist

**Debug:**
- Check pricing calculation logs
- Verify solver principal matches config
- Check canister's solver allowlist

## Security Considerations

This is a **demo** with several security issues:

1. Private keys stored in plaintext (`identity.json` file)
2. No rate limiting
3. No transaction confirmations
4. No slippage protection
5. Mock fulfillment (no real delivery)

**For production:**
- Use secure key management (HSM, KMS, etc.)
- Implement rate limiting and circuit breakers
- Wait for transaction confirmations
- Add slippage checks and timeout protection
- Real blockchain integrations with proper error handling

## Resources

- [ICP Intents SDK Documentation](../../README.md)
- [SimpleIntentPool Example](../simple-intent-pool/)
- [DFINITY Developer Docs](https://internetcomputer.org/docs/)
- [@dfinity/agent Documentation](https://agent-js.icp.xyz/)

## License

MIT License - See [LICENSE](../../LICENSE) for details
