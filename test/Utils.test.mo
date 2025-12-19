/// Unit tests for Utils module
/// Uses mops test package for proper test structure

import {test; suite} "mo:test";
import Utils "../src/icp-intents-lib/Utils";
import Principal "mo:base/Principal";
import Time "mo:base/Time";

suite("Utils", func() {

  test("validates Ethereum addresses correctly", func() {
    // Valid addresses
    assert(Utils.isValidEthAddress("0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0"));
    assert(Utils.isValidEthAddress("0x0000000000000000000000000000000000000000"));

    // Invalid addresses
    assert(not Utils.isValidEthAddress("0x742d35Cc"));  // Too short
    assert(not Utils.isValidEthAddress("742d35Cc6634C0532925a3b844Bc9e7595f0bEb"));  // No 0x
    assert(not Utils.isValidEthAddress("0xZZZZ000000000000000000000000000000000000"));  // Invalid hex
  });

  test("converts hex to Nat correctly", func() {
    assert(Utils.hexToNat("0x0") == ?0);
    assert(Utils.hexToNat("0x10") == ?16);
    assert(Utils.hexToNat("0xFF") == ?255);
    assert(Utils.hexToNat("0x100") == ?256);
    assert(Utils.hexToNat("0xDEADBEEF") == ?3735928559);

    // Invalid hex
    assert(Utils.hexToNat("0xGG") == null);
  });

  test("calculates fees correctly", func() {
    // 0.3% = 30 bps
    assert(Utils.calculateFee(1000000, 30) == 3000);  // 0.3% of 1M = 3000

    // 1% = 100 bps
    assert(Utils.calculateFee(1000000, 100) == 10000);  // 1% of 1M = 10000

    // 0% fee
    assert(Utils.calculateFee(1000000, 0) == 0);
  });

  test("validates time correctly", func() {
    let now : Time.Time = 1000000000;
    let future : Time.Time = 2000000000;
    let past : Time.Time = 500000000;

    assert(Utils.isInFuture(future, now));
    assert(not Utils.isInFuture(past, now));

    assert(Utils.hasPassed(past, now));
    assert(not Utils.hasPassed(future, now));
  });

  test("validates deadlines correctly", func() {
    let now : Time.Time = 1000000000;
    let maxLifetime : Int = 7 * 24 * 60 * 60 * 1_000_000_000;  // 7 days
    let validDeadline = now + 3600_000_000_000;  // 1 hour from now
    let tooFarDeadline = now + (8 * 24 * 60 * 60 * 1_000_000_000);  // 8 days
    let pastDeadline = now - 1000;

    assert(Utils.isValidDeadline(validDeadline, now, maxLifetime));
    assert(not Utils.isValidDeadline(tooFarDeadline, now, maxLifetime));
    assert(not Utils.isValidDeadline(pastDeadline, now, maxLifetime));
  });

  test("validates amounts correctly", func() {
    assert(Utils.isValidAmount(1000, 100));
    assert(Utils.isValidAmount(100, 100));
    assert(not Utils.isValidAmount(99, 100));
    assert(not Utils.isValidAmount(0, 100));
  });

  test("creates derivation paths correctly", func() {
    let user = Principal.fromText("aaaaa-aa");
    let intentId = 42;

    let path = Utils.createDerivationPath(intentId, user);
    assert(path.size() == 2);

    // Different intents should have different paths
    let path2 = Utils.createDerivationPath(43, user);
    assert(path[0] != path2[0]);
  });

  test("formats and parses amounts correctly", func() {
    // Format with 8 decimals (like ICP e8s)
    let formatted = Utils.formatAmount(123456789, 8);
    assert(formatted == "1.23456789");

    // Parse with 8 decimals
    let parsed = Utils.parseAmount("1.5", 8);
    assert(parsed == ?150000000);

    let parsed2 = Utils.parseAmount("100", 8);
    assert(parsed2 == ?10000000000);

    // Invalid formats
    assert(Utils.parseAmount("1.2.3", 8) == null);
    assert(Utils.parseAmount("abc", 8) == null);
  });

});
