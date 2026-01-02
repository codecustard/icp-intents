/// Unit tests for Math module
/// Tests safe arithmetic operations and basis point calculations

import {test; suite} "mo:test";
import Math "../src/icp-intents-lib/utils/Math";
import Nat64 "mo:base/Nat64";

suite("Math", func() {

  // Safe arithmetic operations

  test("safeAdd performs addition", func() {
    assert(Math.safeAdd(100, 50) == ?150);
    assert(Math.safeAdd(0, 0) == ?0);
    assert(Math.safeAdd(1_000_000, 500_000) == ?1_500_000);
  });

  test("safeSub performs subtraction with underflow check", func() {
    assert(Math.safeSub(100, 50) == ?50);
    assert(Math.safeSub(100, 100) == ?0);

    // Underflow check
    assert(Math.safeSub(50, 100) == null);
    assert(Math.safeSub(0, 1) == null);
  });

  test("safeMul performs multiplication", func() {
    assert(Math.safeMul(10, 5) == ?50);
    assert(Math.safeMul(0, 100) == ?0);
    assert(Math.safeMul(1000, 1000) == ?1_000_000);
  });

  test("safeDiv performs division with zero check", func() {
    assert(Math.safeDiv(100, 2) == ?50);
    assert(Math.safeDiv(100, 3) == ?33); // Floor division
    assert(Math.safeDiv(0, 100) == ?0);

    // Division by zero
    assert(Math.safeDiv(100, 0) == null);
  });

  // Basis points calculations

  test("calculateBps calculates basis points correctly", func() {
    // 0.3% of 1,000,000 = 3,000
    assert(Math.calculateBps(1_000_000, 30) == 3_000);

    // 1% of 1,000,000 = 10,000
    assert(Math.calculateBps(1_000_000, 100) == 10_000);

    // 10% of 1,000,000 = 100,000
    assert(Math.calculateBps(1_000_000, 1_000) == 100_000);

    // 100% of 1,000,000 = 1,000,000
    assert(Math.calculateBps(1_000_000, 10_000) == 1_000_000);

    // 0% fee
    assert(Math.calculateBps(1_000_000, 0) == 0);
  });

  test("calculateBps handles invalid basis points", func() {
    // bps > MAX_BPS should return 0
    assert(Math.calculateBps(1_000_000, 10_001) == 0);
    assert(Math.calculateBps(1_000_000, 20_000) == 0);
  });

  test("calculateFee returns fee and net amount", func() {
    // 0.3% fee on 1,000,000
    let (fee1, net1) = switch (Math.calculateFee(1_000_000, 30)) {
      case null { assert(false); (0, 0) };
      case (?(f, n)) { (f, n) };
    };
    assert(fee1 == 3_000);
    assert(net1 == 997_000);

    // 1% fee on 1,000,000
    let (fee2, net2) = switch (Math.calculateFee(1_000_000, 100)) {
      case null { assert(false); (0, 0) };
      case (?(f, n)) { (f, n) };
    };
    assert(fee2 == 10_000);
    assert(net2 == 990_000);

    // 0% fee
    let (fee3, net3) = switch (Math.calculateFee(1_000_000, 0)) {
      case null { assert(false); (0, 0) };
      case (?(f, n)) { (f, n) };
    };
    assert(fee3 == 0);
    assert(net3 == 1_000_000);
  });

  test("MAX_BPS constant is correct", func() {
    assert(Math.MAX_BPS == 10_000);
  });

  // Min/max functions

  test("min returns smaller value", func() {
    assert(Math.min(100, 50) == 50);
    assert(Math.min(50, 100) == 50);
    assert(Math.min(100, 100) == 100);
    assert(Math.min(0, 1) == 0);
  });

  test("max returns larger value", func() {
    assert(Math.max(100, 50) == 100);
    assert(Math.max(50, 100) == 100);
    assert(Math.max(100, 100) == 100);
    assert(Math.max(0, 1) == 1);
  });

  // Bounds checking

  test("isInBounds checks if amount is within bounds", func() {
    assert(Math.isInBounds(50, 0, 100) == true);
    assert(Math.isInBounds(0, 0, 100) == true);
    assert(Math.isInBounds(100, 0, 100) == true);

    assert(Math.isInBounds(150, 0, 100) == false);
    assert(Math.isInBounds(50, 60, 100) == false);
  });

  // Slippage

  test("applySlippage calculates minimum with slippage", func() {
    // 0.5% slippage on 1,000,000 = 995,000 minimum
    assert(Math.applySlippage(1_000_000, 50) == 995_000);

    // 1% slippage on 1,000,000 = 990,000 minimum
    assert(Math.applySlippage(1_000_000, 100) == 990_000);

    // 0% slippage
    assert(Math.applySlippage(1_000_000, 0) == 1_000_000);

    // Edge case: slippage >= amount
    assert(Math.applySlippage(100, 10_000) == 0); // 100% slippage
  });

  // String formatting

  test("bpsToPercent formats basis points as percentage", func() {
    assert(Math.bpsToPercent(30) == "0.30%");
    assert(Math.bpsToPercent(100) == "1.00%");
    assert(Math.bpsToPercent(1_000) == "10.00%");
    assert(Math.bpsToPercent(10_000) == "100.00%");
    assert(Math.bpsToPercent(0) == "0.00%");
    assert(Math.bpsToPercent(5) == "0.05%");
    assert(Math.bpsToPercent(50) == "0.50%");
    assert(Math.bpsToPercent(500) == "5.00%");
  });

  // Nat64 conversions

  test("natToNat64 converts Nat to Nat64", func() {
    assert(Math.natToNat64(0) == ?Nat64.fromNat(0));
    assert(Math.natToNat64(100) == ?Nat64.fromNat(100));
    assert(Math.natToNat64(1_000_000) == ?Nat64.fromNat(1_000_000));

    // Max Nat64
    let maxNat64 : Nat = 18446744073709551615;
    assert(Math.natToNat64(maxNat64) == ?Nat64.fromNat(maxNat64));
  });

  test("natToNat64 rejects overflow", func() {
    // Above Nat64 max
    let tooLarge : Nat = 18446744073709551616;
    assert(Math.natToNat64(tooLarge) == null);
  });

  test("nat64ToNat converts Nat64 to Nat", func() {
    assert(Math.nat64ToNat(Nat64.fromNat(0)) == 0);
    assert(Math.nat64ToNat(Nat64.fromNat(100)) == 100);
    assert(Math.nat64ToNat(Nat64.fromNat(1_000_000)) == 1_000_000);
  });

  // Proportional calculations

  test("proportional calculates proportional share", func() {
    // 50% of 1000 = 500
    assert(Math.proportional(1000, 1, 2) == ?500);

    // 25% of 1000 = 250
    assert(Math.proportional(1000, 1, 4) == ?250);

    // 33.33% of 1000 = 333 (floor)
    assert(Math.proportional(1000, 1, 3) == ?333);

    // 100% of 1000 = 1000
    assert(Math.proportional(1000, 1, 1) == ?1000);

    // 200% of 1000 = 2000
    assert(Math.proportional(1000, 2, 1) == ?2000);
  });

  test("proportional rejects zero denominator", func() {
    assert(Math.proportional(1000, 1, 0) == null);
  });

  // Array operations

  test("sum calculates array sum", func() {
    assert(Math.sum([]) == ?0);
    assert(Math.sum([100]) == ?100);
    assert(Math.sum([100, 200, 300]) == ?600);
    assert(Math.sum([0, 0, 0]) == ?0);
    assert(Math.sum([1, 2, 3, 4, 5]) == ?15);
  });

  test("average calculates array average", func() {
    assert(Math.average([100]) == ?100);
    assert(Math.average([100, 200, 300]) == ?200);
    assert(Math.average([1, 2, 3, 4, 5]) == ?3); // Floor division
    assert(Math.average([10, 20]) == ?15);
  });

  test("average rejects empty array", func() {
    assert(Math.average([]) == null);
  });

  // Edge cases

  test("handles large numbers correctly", func() {
    let large : Nat = 1_000_000_000_000; // 1 trillion

    // 0.3% of 1 trillion
    assert(Math.calculateBps(large, 30) == 3_000_000_000);

    // 1% of 1 trillion
    assert(Math.calculateBps(large, 100) == 10_000_000_000);
  });

  test("handles zero correctly", func() {
    assert(Math.calculateBps(0, 30) == 0);
    assert(Math.applySlippage(0, 50) == 0);

    let (fee, net) = switch (Math.calculateFee(0, 30)) {
      case null { assert(false); (0, 0) };
      case (?(f, n)) { (f, n) };
    };
    assert(fee == 0);
    assert(net == 0);
  });

});
