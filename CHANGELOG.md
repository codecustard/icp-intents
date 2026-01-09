# Changelog

All notable changes to the ICP Intents SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-01-02

### 🔒 Security - Critical Fixes

#### Fixed Authorization Bypass (CRITICAL)
- **Issue**: `Principal.isController()` allowed canister controllers to bypass solver allowlist
- **Impact**: Controllers could submit quotes without being in allowlist
- **Fix**: Removed controller check, all solvers must be in allowlist
- **Location**: `utils/Validation.mo:83`

#### Fixed Integer Underflow Vulnerabilities (CRITICAL)
- **Issue**: Unsafe `Nat.sub()` operations could trap if fees exceeded amounts
- **Impact**: Canister trap, DoS, potential fund locks
- **Fix**: Added validation before all subtractions, return optional types
- **Locations**:
  - `utils/Math.mo:73` - `calculateFee()` now returns `?(Nat, Nat)`
  - `managers/FeeManager.mo:62` - `calculateFees()` now returns `?FeeBreakdown`
- **Breaking**: Callers must handle optional returns

#### Fixed Missing Authorization Check (CRITICAL)
- **Issue**: `markDeposited()` didn't verify caller was intent creator
- **Impact**: Anyone could mark arbitrary intents as deposited
- **Fix**: Added caller validation, only intent creator can mark deposits
- **Location**: `managers/IntentManager.mo:226`
- **Breaking**: `markDeposited()` now requires `caller: Principal` parameter

### 🔒 Security - High Priority Fixes

#### Fixed Escrow Race Condition (HIGH)
- **Issue**: State transition happened before escrow lock, allowing race conditions
- **Impact**: Double-spend potential if transition succeeded but escrow lock failed
- **Fix**: Lock escrow **before** state transition, rollback on failure
- **Location**: `managers/IntentManager.mo:234-244`

#### Fixed Time Boundary Off-By-One (HIGH)
- **Issue**: Inconsistent deadline validation (`>` vs `>=`)
- **Impact**: Intents could execute exactly at deadline timestamp
- **Fix**: Consistent `>=` comparison across all deadline checks
- **Location**: `core/State.mo` (multiple functions)

#### Added Quote Expiry Validation (HIGH)
- **Issue**: Quotes could be created with expiry time in the past
- **Impact**: Logic errors, instant quote expiration
- **Fix**: Validate `quote_expiry > current_time` on quote submission
- **Location**: `managers/IntentManager.mo:142`

#### Fixed Information Leakage (HIGH)
- **Issue**: `debug_show()` exposed allowlist configuration in error messages
- **Impact**: Solver allowlist disclosure to unauthorized parties
- **Fix**: Removed `debug_show()` from error messages, use static strings
- **Location**: `utils/Validation.mo:86`

#### Removed Placeholder Principal (HIGH)
- **Issue**: `Hoosat.buildTransaction()` used hardcoded placeholder principal
- **Impact**: Incorrect key derivation, potential key reuse
- **Fix**: Added `user: Principal` parameter for proper derivation
- **Location**: `chains/Hoosat.mo:116`
- **Breaking**: `buildTransaction()` now requires `user: Principal` parameter

#### Formalized State Rollback Patterns (HIGH)
- **Issue**: Async state-changing operations could leave partial state mutations on failure
- **Impact**: State inconsistencies, potential fund loss, escrow accounting errors
- **Fix**: Implemented fail-fast validation pattern across all async operations
- **Pattern**: Validate state transition → Perform risky async operation → Commit state
- **Changes**:
  - `fulfillIntent()`: Validates state BEFORE token transfer, clean rollback on failure
  - `cancelIntent()`: Validates state BEFORE token refund, clean rollback on failure
  - `depositTokens()`: Acknowledges ICRC-2 non-reversibility, logs CRITICAL failures
- **Locations**:
  - `managers/IntentManager.mo:489-590` (fulfillIntent)
  - `managers/IntentManager.mo:606-685` (cancelIntent)
  - `managers/IntentManager.mo:719-793` (depositTokens)
- **Benefits**: Eliminates partial state mutations, prevents fund loss, maintains consistency

#### Improved HTTP Outcall Resilience (HIGH)
- **Issue**: Transient network failures caused permanent verification failures
- **Impact**: Valid transactions rejected due to temporary RPC issues, poor UX
- **Fix**: Graceful degradation - return `#Pending` for transient errors instead of `#Failed`
- **Transient Errors Handled**:
  - HTTP 429 (rate limit)
  - HTTP 5xx (server errors)
  - Timeout/unavailable/overloaded exceptions
  - Missing data in valid responses
- **EVM Changes** (`chains/EVM.mo:354-520`):
  - Leverages EVM RPC canister's multi-provider consensus
  - Returns `#Pending` for: receipt not found, tx data unavailable, block number parsing failures
  - Distinguishes transient errors from validation failures
- **Hoosat Changes** (`chains/Hoosat.mo:182-541`):
  - Handles transient errors across all 4 HTTP outcalls (UTXO list, tx details, block details, chain info)
  - Returns `#Pending` for HTTP 429, 5xx, and exception keywords
- **Benefits**: Automatic retry on temporary failures, improved reliability, better UX

### 🔒 Security - Low Priority Fixes

#### Added Rate Limiting and DoS Prevention (LOW)
- **Issue**: No per-user intent limits, no cycle tracking, unbounded HashMap growth
- **Impact**: Potential memory/cycle exhaustion, resource abuse
- **Fix**: Multi-layer defense-in-depth approach
- **Rate Limits Implemented**:
  - Per-user total intent limit: 100
  - Per-user active intent limit: 20
  - Global total intent limit: 10,000
  - Global active intent limit: 5,000
- **Tracking Added**:
  - User intent counts (total and active per user)
  - Cycle consumption tracking
  - Cleanup mechanism for terminal intents (7-day retention)
- **Monitoring Functions**:
  - `cleanupTerminalIntents()` - Remove old terminal intents
  - `getIntentStats()` - Get intent statistics
  - `getUserCycleBudget()` - Get user's capacity info
  - `getCycleStats()` - Get system capacity status
- **Locations**:
  - `utils/RateLimits.mo` (NEW) - Rate limit constants
  - `managers/IntentManager.mo` - Rate checking, counter tracking, cleanup
  - `core/Errors.mo` - Added `#RateLimitExceeded` error variant
  - `IntentLib.mo` - Exported monitoring functions

#### Enhanced JSON Parsing Security (LOW)
- **Issue**: No field length validation, no numeric bounds checking
- **Impact**: Potential memory exhaustion from malicious RPC responses
- **Fix**: Added comprehensive validation at extraction and parsing layers
- **Field Length Limits**:
  - TX hash: 100 characters max
  - Block hash: 100 characters max
  - Address: 120 characters max
  - Generic JSON field: 256 characters max
- **Numeric Bounds**:
  - Block height/number: 2^53 - 1 (JavaScript safe integer limit)
  - Token amounts: 2^80 (supports very large amounts)
  - Confirmations: 100,000 max
- **Validation Functions**:
  - `validateFieldLength()` - Check string length limits
  - `validateNumericBounds()` - Check numeric value bounds
  - `parseNatSafe()` / `hexToNatSafe()` - Safe parsing with overflow detection
- **Locations**:
  - `utils/Constants.mo` - JSON parsing security limits
  - `chains/Hoosat.mo` - Field validation, safe parsing
  - `chains/EVM.mo` - Field validation, safe parsing

### ✨ Code Quality Improvements

#### Centralized Magic Numbers
- **Created**: `utils/Constants.mo` module
- **Impact**: Eliminated magic numbers, improved maintainability
- **Constants**:
  - `ONE_HOUR_NANOS = 3_600_000_000_000`
  - `MAX_REASONABLE_PROTOCOL_FEE_BPS = 1000`
  - `MAX_REASONABLE_TOTAL_FEE_BPS = 1000`
  - `HOOSAT_DEFAULT_FEE = 2000`
  - `ETH_ADDRESS_LENGTH = 42`
  - Address length constants for validation

#### Fixed Event Data Accuracy
- **Issue**: `QuoteConfirmed` events used placeholder values
- **Impact**: Off-chain indexing had incorrect data
- **Fix**: Track actual `quote_index` and extract real `deposit_address`
- **Location**: `managers/IntentManager.mo:176-189`

#### Consolidated JSON Parsing
- **Issue**: Duplicate JSON parsing logic in `Hoosat.mo`
- **Fix**: Unified 4 parsing functions into 1 with type parameter
- **Impact**: Better maintainability, reduced code duplication
- **Location**: `chains/Hoosat.mo:30-60`

#### Improved Type Safety
- **Enhancement**: Added hex string validation in `EVM.mo`
- **Impact**: Prevents memory exhaustion from malformed data
- **Location**: `chains/EVM.mo:97-122`

### 📚 Documentation

#### Added
- Comprehensive security improvements section in README
- Breaking changes migration guide for v0.2.0
- SECURITY.md with responsible disclosure policy
- This CHANGELOG.md
- **Solver Bot Example** (`examples/solver-bot/`) - Complete TypeScript solver implementation

#### Updated
- README migration checklist for v0.2.0
- Pre-production security checklist
- Test coverage documentation
- README with Example Projects section showcasing both Motoko and TypeScript examples

#### Solver Bot Example Details

**Location**: `examples/solver-bot/`

**Purpose**: Educational TypeScript/Node.js solver bot demonstrating the complete solver workflow

**Features**:
- **Intent Monitoring**: Polls intent pool for new intents in PendingQuote/Quoted status
- **Smart Filtering**: Checks solver capabilities (supported chains/tokens, deadline validation)
- **Mock Pricing**: Configurable fixed exchange rates via `.env` (e.g., `RATE_ETH_HOO=50000`)
- **Quote Calculation**: Calculates competitive quotes with profitability checks
- **Automatic Fulfillment**: Tracks confirmed quotes and fulfills deposited intents
- **Auto-Generated Identity**: Creates and saves Ed25519 identity on first run
- **Retry Logic**: Exponential backoff for transient IC call failures
- **Structured Logging**: Colored console output with debug/info/warn/error levels
- **Mock Fulfillment**: Simulates token delivery without real blockchain transactions

**Project Structure** (17 TypeScript files):
```
examples/solver-bot/
├── src/
│   ├── index.ts                  # Main monitoring loop
│   ├── config.ts                 # Environment configuration
│   ├── agent.ts                  # IC Agent with identity management
│   ├── types/intent-pool.ts      # Candid TypeScript types
│   ├── idl/intent-pool.idl.ts   # IDL factory
│   ├── monitor/
│   │   ├── IntentMonitor.ts     # Polling logic
│   │   └── IntentFilter.ts      # Capability filtering
│   ├── pricing/MockPricing.ts    # Fixed-rate pricing
│   ├── fulfillment/MockFulfillment.ts  # Simulated delivery
│   └── utils/
│       ├── logger.ts             # Structured logging
│       └── retry.ts              # Exponential backoff
├── candid/SimpleIntentPool.did   # Candid interface
├── package.json                  # NPM dependencies (52 packages)
├── tsconfig.json                 # TypeScript config
├── .env.example                  # Configuration template
└── README.md                     # Comprehensive documentation
```

**Quick Start**:
```bash
cd examples/solver-bot
npm install                    # Install dependencies
cp .env.example .env          # Configure environment
# Edit .env with canister ID
npm run dev                   # Start bot
```

**Architecture**:
```
Main Loop → IntentMonitor → IntentFilter → MockPricing
    ↓            ↓               ↓              ↓
Poll IDs    Get Intent     Check Support   Calculate Quote
    ↓            ↓               ↓              ↓
Track IDs   Track Seen    Validate Time   Check Profit
    ↓            ↓               ↓              ↓
          Submit Quote → Track Active → MockFulfillment
```

**Configuration** (via `.env`):
- IC network selection (local/ic)
- Solver identity path (auto-generated)
- Polling interval (default 5s)
- Minimum profit threshold (basis points)
- Exchange rates for token pairs
- Supported chains and tokens
- Solver fee/tip configuration

**Production Extension Guide**:
- Replace `MockPricing` with DEX APIs, oracles
- Replace `MockFulfillment` with real blockchain wallet integrations
- Add database for intent history and analytics
- Implement event-driven architecture instead of polling
- Add health checks, metrics, and alerting

**Dependencies**:
- `@dfinity/agent` ^1.0.0
- `@dfinity/candid` ^1.0.0
- `@dfinity/identity` ^1.0.0
- `@dfinity/principal` ^1.0.0
- `dotenv` ^16.0.0
- TypeScript ^5.0.0

**Build Output**: 44 files (11 JS, 11 .d.ts, 11 .js.map, 11 .d.ts.map)

**Test Status**: ✅ TypeScript compilation successful, 0 vulnerabilities

### 🧪 Testing

#### Added
- ChainRegistry tests (18 tests)
- TokenRegistry tests (16 tests)
- FeeManager tests (19 tests)
- Events tests (15 tests)
- Escrow tests (8 tests)
- State machine tests (58 tests)
- EVM verification tests (12 tests)
- Hoosat verification tests (13 tests)

#### Updated
- Math tests for optional return types
- FeeManager tests for optional return types
- IntentManager tests for caller parameter

**Total Test Count**: ~284 tests across 14 test files
**Test Status**: ✅ All passing

### 🔄 Breaking Changes

1. **Math.calculateFee()**: Returns `?(Nat, Nat)` instead of `(Nat, Nat)`
2. **FeeManager.calculateFees()**: Returns `?FeeBreakdown` instead of `FeeBreakdown`
3. **IntentLib.calculateFees()**: Returns `?FeeBreakdown` instead of `FeeBreakdown`
4. **IntentManager.markDeposited()**: Requires `caller: Principal` parameter
5. **IntentLib.verifyAndMarkDeposited()**: Requires `caller: Principal` parameter
6. **Hoosat.buildTransaction()**: Requires `user: Principal` parameter

See [Migration Guide](README.md#v020-breaking-changes-security-hardening) for upgrade instructions.

### 📦 Dependencies

No dependency changes.

---

## [0.1.0] - 2025

### Initial Release

- Multi-chain intent-based exchange SDK
- EVM, Hoosat, Bitcoin chain support
- Threshold ECDSA address generation
- Multi-token escrow
- Fee management
- Event logging
- Comprehensive type system

---

## Version Support

- **0.2.x**: Actively supported, security hardened
- **0.1.x**: Deprecated, upgrade to 0.2.0

## Security Advisories

For security-related changes, see [SECURITY.md](SECURITY.md).
