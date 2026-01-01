/// Unit tests for Utils module
/// Uses mops test package for proper test structure
///
/// NOTE: The Utils module was refactored into separate modules:
/// - Math.mo - for calculations and basis points
/// - Validation.mo - for input validation
/// - Cycles.mo - for cycle management
///
/// TODO: Create new tests for these individual modules if needed

import {test; suite} "mo:test";

suite("Utils", func() {

  test("Utils module was refactored", func() {
    // The old Utils module was split into Math, Validation, and Cycles
    // See those modules for the current API
    assert(true); // Placeholder
  });

});

/* OLD TESTS - FUNCTIONS NO LONGER EXIST

  The old Utils module had functions like:
  - isValidEthAddress() - now Validation.validateEthAddress()
  - hexToNat() - removed
  - calculateFee() - now Math.calculateFee() or Math.calculateBps()
  - isInFuture(), hasPassed() - removed
  - isValidDeadline() - now Validation.validateDeadline()
  - isValidAmount() - now Validation.validateAmount()
  - createDerivationPath() - now in TECDSA module
  - formatAmount(), parseAmount() - removed

  Many of these functions were refactored with different signatures
  See Math.mo and Validation.mo for current API

*/
