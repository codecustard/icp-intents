# Testing Guide for ICP Intents SDK

This guide explains how to write, run, and maintain tests for the ICP Intents SDK.

## Table of Contents

- [Getting Started](#getting-started)
- [Testing Philosophy](#testing-philosophy)
- [Test Types](#test-types)
- [Writing Tests](#writing-tests)
- [Best Practices](#best-practices)
- [Common Patterns](#common-patterns)
- [Troubleshooting](#troubleshooting)

## Getting Started

### Prerequisites

```bash
# Install mops (Motoko package manager)
npm install -g ic-mops

# Install dependencies
mops install
```

### Running Tests

```bash
# Run all tests
mops test

# Run specific test file
mops test test/Math.test.mo

# Run with verbose output
mops test --verbose
```

## Testing Philosophy

### Core Principles

1. **Test Business Logic, Not Integrations**
   - Focus on pure functions and business rules
   - Document integration requirements separately
   - Mock external dependencies when possible

2. **Comprehensive Coverage**
   - Test happy paths and error cases
   - Test edge cases (zero, max values, boundaries)
   - Test idempotent operations

3. **Clear Test Names**
   - Use descriptive names that explain what's being tested
   - Follow pattern: `"{function} {scenario} {expected result}"`
   - Example: `"calculateFees computes correct protocol fee"`

4. **Fast and Isolated**
   - Tests should run quickly (< 1 minute total)
   - Each test should be independent
   - No shared mutable state between tests

## Test Types

### 1. Sync Unit Tests

For pure functions without async operations.

**Use when:**
- Function doesn't use `await`
- No external canister calls
- Deterministic output

**Example:**
```motoko
import { test; suite } = "mo:test";
import Math "../src/icp-intents-lib/utils/Math";

suite("Math - BPS Calculations", func() {
  test("calculateBps returns correct value", func() {
    let result = Math.calculateBps(1000, 30);
    assert(result == 3); // 0.3% of 1000
  });
});
```

### 2. Async Unit Tests

For functions requiring async context but testable in isolation.

**Use when:**
- Function uses `await`
- Can be tested without real external services
- Async operations are mockable

**Example:**
```motoko
import { test; suite } = "mo:test/async";
import IntentManager "../src/icp-intents-lib/managers/IntentManager";

await suite("IntentManager - Async", func() : async () {
  await test("cancelIntent succeeds", func() : async () {
    let state = createTestState();
    let result = await IntentManager.cancelIntent(state, 0, alice, currentTime);

    switch (result) {
      case (#ok(_)) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });
});
```

### 3. Integration Test Documentation

For functions requiring external services or complex setup.

**Use when:**
- Function requires HTTP outcalls
- Function requires external canisters (EVM RPC, ICRC-2 ledgers)
- Function requires IC management canister

**Example:**
```motoko
suite("EVM - Integration Notes", func() {
  test("verify() requires EVM RPC canister for full testing", func() {
    // NOTE: The verify() function requires:
    // 1. A deployed EVM RPC canister
    // 2. Real transaction data
    // 3. HTTP outcalls to Ethereum nodes
    //
    // Integration tests would need to:
    // - Mock the EVM RPC canister responses
    // - Test receipt extraction logic
    // - Test transaction validation
    // - Test confirmation checking

    assert(true); // Placeholder for integration test documentation
  });
});
```

## Writing Tests

### Test Structure

```motoko
import { test; suite } = "mo:test";
import ModuleUnderTest "../src/path/to/module";
// Import other dependencies as needed

// Helper functions (if needed)
func createTestData() : Type {
  // Setup test data
};

suite("Module - Feature Category", func() {
  test("specific behavior being tested", func() {
    // Arrange: Set up test data
    let input = createTestData();

    // Act: Execute the function
    let result = ModuleUnderTest.functionUnderTest(input);

    // Assert: Verify the result
    switch (result) {
      case (#ok(value)) {
        assert(value == expectedValue);
      };
      case (#err(_)) { assert(false) };
    };
  });
});
```

### Naming Conventions

#### Test Files
- Place in `test/` directory
- Mirror source file structure when logical
- Use `.test.mo` suffix for sync tests
- Use `.replica.test.mo` suffix for async tests

Examples:
- `src/utils/Math.mo` → `test/Math.test.mo`
- `src/managers/IntentManager.mo` → `test/IntentManager/IntentManager.test.mo` (sync)
- `src/managers/IntentManager.mo` → `test/IntentManager/IntentManager.replica.test.mo` (async)

#### Suite Names
Format: `"Module - Feature Category"`

Examples:
- `"Math - BPS Calculations"`
- `"IntentManager - createIntent"`
- `"State - Transition to Quoted"`

#### Test Names
Format: `"function/behavior description with expected outcome"`

Good examples:
- `"calculateBps returns correct value for 0.3%"`
- `"transitionToQuoted succeeds from PendingQuote"`
- `"validateChainSpec rejects invalid chain_id"`

Bad examples:
- `"test1"` ❌ (not descriptive)
- `"calculateBps"` ❌ (missing scenario)
- `"it works"` ❌ (too vague)

## Best Practices

### 1. Test One Thing at a Time

```motoko
// Good: Focused test
test("calculateFees computes correct protocol fee", func() {
  let result = FeeManager.calculateFees(1000_000, 30, quote);
  assert(result.protocol_fee == 3_000);
});

// Bad: Testing multiple things
test("calculateFees works", func() {
  let result = FeeManager.calculateFees(1000_000, 30, quote);
  assert(result.protocol_fee == 3_000);
  assert(result.solver_fee == 5_000);
  assert(result.total_fees == 9_000);
  assert(result.net_output == 991_000);
  // Too many assertions - split into separate tests
});
```

### 2. Use Descriptive Variable Names

```motoko
// Good: Clear intent
test("transitionToQuoted fails from Fulfilled status", func() {
  let fulfilledIntent = createTestIntent(#Fulfilled);
  let result = State.transitionToQuoted(fulfilledIntent);

  switch (result) {
    case (#err(#InvalidStatus(_))) { assert(true) };
    case (_) { assert(false) };
  };
});

// Bad: Unclear variables
test("transition fails", func() {
  let i = createTestIntent(#Fulfilled);
  let r = State.transitionToQuoted(i);
  assert(r == #err(#InvalidStatus("...")));
});
```

### 3. Test Error Cases

```motoko
// Test both success and failure paths
suite("Validation", func() {
  test("validateAmount accepts valid amounts", func() {
    let result = Validation.validateAmount(1000);
    assert(result == #ok(()));
  });

  test("validateAmount rejects zero", func() {
    let result = Validation.validateAmount(0);
    switch (result) {
      case (#err(#InvalidAmount(_))) { assert(true) };
      case (_) { assert(false) };
    };
  });
});
```

### 4. Test Edge Cases

```motoko
suite("Math - Edge Cases", func() {
  test("calculateBps handles zero amount", func() {
    let result = Math.calculateBps(0, 30);
    assert(result == 0);
  });

  test("calculateBps handles max BPS (100%)", func() {
    let result = Math.calculateBps(1000, 10_000);
    assert(result == 1000);
  });

  test("calculateBps handles large amounts", func() {
    let result = Math.calculateBps(1_000_000_000_000, 30);
    assert(result == 3_000_000_000);
  });
});
```

### 5. Use Helper Functions

```motoko
// Create reusable test data
func createTestIntent(status : Types.IntentStatus) : Types.Intent {
  {
    id = 0;
    user = Principal.fromText("aaaaa-aa");
    source = { chain = "ethereum"; chain_id = ?1; token = "ETH"; network = "mainnet" };
    destination = { chain = "icp"; chain_id = null; token = "ICP"; network = "mainnet" };
    // ... other fields
    status = status;
  }
};

// Use in multiple tests
test("test A", func() {
  let intent = createTestIntent(#PendingQuote);
  // ...
});

test("test B", func() {
  let intent = createTestIntent(#Quoted);
  // ...
});
```

## Common Patterns

### Pattern 1: Result Type Assertions

```motoko
// Asserting success
test("function succeeds", func() {
  let result = someFunction(input);

  switch (result) {
    case (#ok(value)) {
      assert(value == expectedValue);
    };
    case (#err(_)) { assert(false) };
  };
});

// Asserting specific error
test("function fails with expected error", func() {
  let result = someFunction(invalidInput);

  switch (result) {
    case (#ok(_)) { assert(false) };
    case (#err(#InvalidAmount(_))) { assert(true) };
    case (#err(_)) { assert(false) }; // Unexpected error type
  };
});
```

### Pattern 2: Testing State Transitions

```motoko
test("state transition updates status", func() {
  let initialIntent = createTestIntent(#PendingQuote);

  let result = State.transitionToQuoted(initialIntent);

  switch (result) {
    case (#ok(newIntent)) {
      assert(newIntent.status == #Quoted);
      // Optionally verify other fields unchanged
      assert(newIntent.id == initialIntent.id);
    };
    case (#err(_)) { assert(false) };
  };
});
```

### Pattern 3: Testing Collections

```motoko
test("function returns all expected items", func() {
  let state = setup();
  // Add test data
  TokenRegistry.registerToken(state, "ICP", ledger1, 8, 10_000);
  TokenRegistry.registerToken(state, "ckBTC", ledger2, 8, 10);

  let tokens = TokenRegistry.listTokens(state);

  assert(tokens.size() == 2);

  // Verify contents
  var foundICP = false;
  var foundCkBTC = false;
  for (token in tokens.vals()) {
    if (token == "ICP") { foundICP := true };
    if (token == "ckBTC") { foundCkBTC := true };
  };

  assert(foundICP and foundCkBTC);
});
```

### Pattern 4: Testing Idempotency

```motoko
test("operation is idempotent", func() {
  let intent = createTestIntent(#Quoted);

  // Apply operation twice
  let result1 = State.transitionToQuoted(intent);
  let result2 = switch (result1) {
    case (#ok(i)) { State.transitionToQuoted(i) };
    case (#err(_)) { assert(false); result1 };
  };

  // Both should succeed with same result
  switch (result2) {
    case (#ok(i)) { assert(i.status == #Quoted) };
    case (#err(_)) { assert(false) };
  };
});
```

## Troubleshooting

### Common Issues

#### Issue: Tests fail with "unbound variable"
**Solution**: Check imports and make sure all modules are properly imported.

```motoko
// Missing import
test("test", func() {
  let x = Principal.fromText("aaaaa-aa"); // ❌ Error
});

// Fixed
import Principal "mo:base/Principal";

test("test", func() {
  let x = Principal.fromText("aaaaa-aa"); // ✅ Works
});
```

#### Issue: "expected async type" error
**Solution**: Use `mo:test/async` for async tests and add `await` keywords.

```motoko
// Wrong: Using sync test framework for async function
import { test; suite } = "mo:test";

test("async test", func() {
  let result = await asyncFunction(); // ❌ Error
});

// Fixed: Use async test framework
import { test; suite } = "mo:test/async";

await test("async test", func() : async () {
  let result = await asyncFunction(); // ✅ Works
});
```

#### Issue: "type error" in test data
**Solution**: Match the exact type signature, including all required fields.

```motoko
// Check the actual type definition
// public type Intent = {
//   id : Nat;
//   user : Principal;
//   status : IntentStatus;
//   escrow_balance : Nat; // ← Don't forget this field!
//   // ...
// }

func createTestIntent(status : IntentStatus) : Intent {
  {
    id = 0;
    user = Principal.fromText("aaaaa-aa");
    status = status;
    escrow_balance = 0; // ← Include all required fields
    // ... all other fields
  }
};
```

#### Issue: Tests pass locally but fail in CI
**Solution**: Ensure tests don't depend on:
- System time (use fixed timestamps)
- File system state
- External network calls
- Shared mutable state

### Getting Help

If you encounter issues:

1. Check existing test files for similar patterns
2. Review this guide for best practices
3. Check the [mo:test documentation](https://github.com/kritzcreek/mo-test)
4. Ask in the project's discussion forum

## Contributing Tests

### Before Submitting

1. ✅ All tests pass: `mops test`
2. ✅ Test names are descriptive
3. ✅ Edge cases are covered
4. ✅ Error cases are tested
5. ✅ Helper functions are documented
6. ✅ Integration requirements documented (if applicable)

### Pull Request Checklist

- [ ] Tests added for new functionality
- [ ] Existing tests updated for API changes
- [ ] Test coverage report updated (if adding new modules)
- [ ] Tests follow naming conventions
- [ ] Tests are isolated and don't share state

## Appendix

### Test File Template

```motoko
import { test; suite } = "mo:test";
import ModuleName "../src/path/to/module";
import Principal "mo:base/Principal";
// Other imports...

// Helper functions
func createTestData() : Type {
  // ...
};

suite("ModuleName - Feature Category", func() {
  test("specific behavior with expected outcome", func() {
    // Arrange
    let input = createTestData();

    // Act
    let result = ModuleName.function(input);

    // Assert
    switch (result) {
      case (#ok(value)) {
        assert(value == expectedValue);
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("error case behavior", func() {
    let invalidInput = createInvalidTestData();

    let result = ModuleName.function(invalidInput);

    switch (result) {
      case (#ok(_)) { assert(false) };
      case (#err(#ExpectedError(_))) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });
});
```

### Useful Assertions

```motoko
// Basic assertions
assert(true);
assert(not false);
assert(value == expected);
assert(value != unexpected);

// Comparison
assert(a > b);
assert(a >= b);
assert(a < b);
assert(a <= b);

// Option handling
switch (optValue) {
  case (?v) { assert(v == expected) };
  case null { assert(false) };
};

// Result handling
switch (result) {
  case (#ok(v)) { assert(v == expected) };
  case (#err(_)) { assert(false) };
};

// Array/Buffer size
assert(array.size() == expectedSize);

// Text operations
assert(Text.startsWith(text, #text "prefix"));
assert(Text.contains(text, #text "substring"));
```

---

**Happy Testing! 🧪**
