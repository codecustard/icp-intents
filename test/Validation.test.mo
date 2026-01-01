/// Unit tests for Validation module
/// Tests input validation for amounts, addresses, deadlines, etc.

import {test; suite} "mo:test";
import Validation "../src/icp-intents-lib/utils/Validation";
import Types "../src/icp-intents-lib/core/Types";
import Principal "mo:base/Principal";
import Time "mo:base/Time";

suite("Validation", func() {

  // Helper to create test config
  func createTestConfig() : Types.SystemConfig {
    {
      protocol_fee_bps = 30;
      fee_collector = Principal.fromText("aaaaa-aa");
      supported_chains = [];
      min_intent_amount = 1_000;
      max_intent_amount = 1_000_000_000;
      default_deadline_duration = 3600_000_000_000; // 1 hour
      solver_allowlist = null;
    }
  };

  // Amount validation

  test("validateAmount accepts valid amounts", func() {
    let config = createTestConfig();

    assert(Validation.validateAmount(1_000, config) == null); // Min
    assert(Validation.validateAmount(500_000, config) == null); // Middle
    assert(Validation.validateAmount(1_000_000_000, config) == null); // Max
  });

  test("validateAmount rejects zero amount", func() {
    let config = createTestConfig();

    switch (Validation.validateAmount(0, config)) {
      case (?#InvalidAmount(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("validateAmount rejects amount below minimum", func() {
    let config = createTestConfig();

    switch (Validation.validateAmount(999, config)) {
      case (?#InvalidAmount(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("validateAmount rejects amount above maximum", func() {
    let config = createTestConfig();

    switch (Validation.validateAmount(1_000_000_001, config)) {
      case (?#InvalidAmount(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  // Minimum output validation

  test("validateMinOutput accepts valid min output", func() {
    assert(Validation.validateMinOutput(100, 1000) == null);
    assert(Validation.validateMinOutput(1_000_000, 1_000_000) == null);
  });

  test("validateMinOutput rejects zero", func() {
    switch (Validation.validateMinOutput(0, 1000)) {
      case (?#InvalidAmount(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  // Deadline validation

  test("validateDeadline accepts valid future deadline", func() {
    let config = createTestConfig();
    let now : Time.Time = 1_000_000_000;
    let futureDeadline = now + 1_800_000_000_000; // 30 minutes

    assert(Validation.validateDeadline(futureDeadline, now, config) == null);
  });

  test("validateDeadline rejects past deadline", func() {
    let config = createTestConfig();
    let now : Time.Time = 1_000_000_000;
    let pastDeadline = now - 1000;

    switch (Validation.validateDeadline(pastDeadline, now, config)) {
      case (?#InvalidDeadline(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("validateDeadline rejects deadline equal to current time", func() {
    let config = createTestConfig();
    let now : Time.Time = 1_000_000_000;

    switch (Validation.validateDeadline(now, now, config)) {
      case (?#InvalidDeadline(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("validateDeadline rejects deadline too far in future", func() {
    let config = createTestConfig();
    let now : Time.Time = 1_000_000_000;
    // Max allowed is 30x default duration = 30 hours
    let tooFarDeadline = now + (31 * 3600_000_000_000);

    switch (Validation.validateDeadline(tooFarDeadline, now, config)) {
      case (?#InvalidDeadline(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  // Quote amount validation

  test("validateQuoteAmount accepts valid quote", func() {
    assert(Validation.validateQuoteAmount(1000, 900, 1100) == null);
    assert(Validation.validateQuoteAmount(1000, 1000, 1100) == null); // Exact min
  });

  test("validateQuoteAmount rejects zero output", func() {
    switch (Validation.validateQuoteAmount(0, 100, 1000)) {
      case (?#InvalidQuote(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("validateQuoteAmount rejects output below minimum", func() {
    switch (Validation.validateQuoteAmount(899, 900, 1000)) {
      case (?#InvalidQuote(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  // Fee validation

  test("validateFee accepts reasonable fees", func() {
    assert(Validation.validateFee(100, 1000) == null); // 10%
    assert(Validation.validateFee(499, 1000) == null); // 49.9% (just under limit)
  });

  test("validateFee rejects fee >= 50% of output", func() {
    switch (Validation.validateFee(500, 1000)) {
      case (?#InvalidFee(_)) {}; // Expected (50%)
      case _ { assert(false) };
    };

    switch (Validation.validateFee(600, 1000)) {
      case (?#InvalidFee(_)) {}; // Expected (60%)
      case _ { assert(false) };
    };
  });

  // Quote expiry validation

  test("validateQuoteExpiry accepts valid expiry", func() {
    let now : Time.Time = 1_000_000_000;
    let intentDeadline = now + 7200_000_000_000; // 2 hours
    let quoteExpiry = now + 3600_000_000_000; // 1 hour

    assert(Validation.validateQuoteExpiry(quoteExpiry, now, intentDeadline) == null);
  });

  test("validateQuoteExpiry rejects past expiry", func() {
    let now : Time.Time = 1_000_000_000;
    let intentDeadline = now + 7200_000_000_000;
    let pastExpiry = now - 1000;

    switch (Validation.validateQuoteExpiry(pastExpiry, now, intentDeadline)) {
      case (?#InvalidQuote(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("validateQuoteExpiry rejects expiry beyond intent deadline", func() {
    let now : Time.Time = 1_000_000_000;
    let intentDeadline = now + 3600_000_000_000; // 1 hour
    let lateExpiry = now + 7200_000_000_000; // 2 hours

    switch (Validation.validateQuoteExpiry(lateExpiry, now, intentDeadline)) {
      case (?#InvalidQuote(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  // Ethereum address validation

  test("validateEthAddress accepts valid addresses", func() {
    assert(Validation.validateEthAddress("0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0") == null);
    assert(Validation.validateEthAddress("0x0000000000000000000000000000000000000000") == null);
    assert(Validation.validateEthAddress("0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF") == null);
  });

  test("validateEthAddress rejects address without 0x prefix", func() {
    switch (Validation.validateEthAddress("742d35Cc6634C0532925a3b844Bc9e7595f0bEb0")) {
      case (?#InvalidAddress(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("validateEthAddress rejects address with wrong length", func() {
    switch (Validation.validateEthAddress("0x742d35Cc")) {
      case (?#InvalidAddress(_)) {}; // Expected (too short)
      case _ { assert(false) };
    };

    switch (Validation.validateEthAddress("0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0000")) {
      case (?#InvalidAddress(_)) {}; // Expected (too long)
      case _ { assert(false) };
    };
  });

  test("validateEthAddress rejects address with invalid hex chars", func() {
    switch (Validation.validateEthAddress("0xZZZZ000000000000000000000000000000000000")) {
      case (?#InvalidAddress(_)) {}; // Expected
      case _ { assert(false) };
    };

    switch (Validation.validateEthAddress("0x742d35Cc6634C0532925a3b844Bc9e7595f0bEbG")) {
      case (?#InvalidAddress(_)) {}; // Expected (G is not hex)
      case _ { assert(false) };
    };
  });

  // Hoosat address validation

  test("validateHoosatAddress accepts valid addresses", func() {
    assert(Validation.validateHoosatAddress("hoosat:qz1234567890abcdef1234567890abcdef1234567890abcdef123") == null);
    assert(Validation.validateHoosatAddress("Hoosat:qz1234567890abcdef1234567890abcdef1234567890abcdef123") == null);
  });

  test("validateHoosatAddress rejects address without correct prefix", func() {
    switch (Validation.validateHoosatAddress("bitcoin:qz1234567890abcdef1234567890abcdef1234567890abcdef123")) {
      case (?#InvalidAddress(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("validateHoosatAddress rejects address too short", func() {
    switch (Validation.validateHoosatAddress("hoosat:short")) {
      case (?#InvalidAddress(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  // Bitcoin address validation

  test("validateBitcoinAddress accepts valid length addresses", func() {
    // P2PKH (26-34 chars)
    assert(Validation.validateBitcoinAddress("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa") == null);

    // Bech32 (42-62 chars)
    assert(Validation.validateBitcoinAddress("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq") == null);
  });

  test("validateBitcoinAddress rejects address too short", func() {
    switch (Validation.validateBitcoinAddress("1A1zP1")) {
      case (?#InvalidAddress(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("validateBitcoinAddress rejects address too long", func() {
    let tooLong = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdqextralongsuffixextralongsuffix";
    switch (Validation.validateBitcoinAddress(tooLong)) {
      case (?#InvalidAddress(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  // Chain spec validation

  test("validateChainSpec accepts valid spec", func() {
    let config = createTestConfig();
    let spec : Types.ChainSpec = {
      chain = "ethereum";
      chain_id = ?1;
      token = "ETH";
      network = "mainnet";
    };

    assert(Validation.validateChainSpec(spec, config) == null);
  });

  test("validateChainSpec rejects empty chain name", func() {
    let config = createTestConfig();
    let spec : Types.ChainSpec = {
      chain = "";
      chain_id = ?1;
      token = "ETH";
      network = "mainnet";
    };

    switch (Validation.validateChainSpec(spec, config)) {
      case (?#InvalidChain(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("validateChainSpec rejects empty token", func() {
    let config = createTestConfig();
    let spec : Types.ChainSpec = {
      chain = "ethereum";
      chain_id = ?1;
      token = "";
      network = "mainnet";
    };

    switch (Validation.validateChainSpec(spec, config)) {
      case (?#InvalidToken(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

  // Solver authorization validation

  test("validateSolver accepts any solver when permissionless", func() {
    let config = createTestConfig(); // solver_allowlist = null
    let solver = Principal.fromText("2vxsx-fae");

    assert(Validation.validateSolver(solver, config) == null);
  });

  test("validateSolver accepts allowlisted solver", func() {
    let allowedSolver = Principal.fromText("2vxsx-fae");
    let config : Types.SystemConfig = {
      protocol_fee_bps = 30;
      fee_collector = Principal.fromText("aaaaa-aa");
      supported_chains = [];
      min_intent_amount = 1_000;
      max_intent_amount = 1_000_000_000;
      default_deadline_duration = 3600_000_000_000;
      solver_allowlist = ?[allowedSolver];
    };

    assert(Validation.validateSolver(allowedSolver, config) == null);
  });

  test("validateSolver rejects non-allowlisted solver", func() {
    let allowedSolver = Principal.fromText("2vxsx-fae");
    let otherSolver = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
    let config : Types.SystemConfig = {
      protocol_fee_bps = 30;
      fee_collector = Principal.fromText("aaaaa-aa");
      supported_chains = [];
      min_intent_amount = 1_000;
      max_intent_amount = 1_000_000_000;
      default_deadline_duration = 3600_000_000_000;
      solver_allowlist = ?[allowedSolver];
    };

    switch (Validation.validateSolver(otherSolver, config)) {
      case (?#SolverNotAllowed) {}; // Expected
      case _ { assert(false) };
    };
  });

  // Protocol fee validation

  test("validateProtocolFeeBps accepts valid fees", func() {
    assert(Validation.validateProtocolFeeBps(0) == null); // 0%
    assert(Validation.validateProtocolFeeBps(30) == null); // 0.3%
    assert(Validation.validateProtocolFeeBps(100) == null); // 1%
    assert(Validation.validateProtocolFeeBps(1000) == null); // 10% (max)
  });

  test("validateProtocolFeeBps rejects fee > 10%", func() {
    switch (Validation.validateProtocolFeeBps(1001)) {
      case (?#InvalidFee(_)) {}; // Expected
      case _ { assert(false) };
    };

    switch (Validation.validateProtocolFeeBps(5000)) {
      case (?#InvalidFee(_)) {}; // Expected (50%)
      case _ { assert(false) };
    };
  });

  test("validateProtocolFeeBps rejects fee > 100%", func() {
    switch (Validation.validateProtocolFeeBps(10_001)) {
      case (?#InvalidFee(_)) {}; // Expected
      case _ { assert(false) };
    };
  });

});
