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

#### Updated
- README migration checklist for v0.2.0
- Pre-production security checklist
- Test coverage documentation

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
