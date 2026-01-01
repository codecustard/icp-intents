import { test; suite } = "mo:test";
import FeeManager "../src/icp-intents-lib/managers/FeeManager";
import Types "../src/icp-intents-lib/core/Types";
import HashMap "mo:base/HashMap";
import Text "mo:base/Text";
import Principal "mo:base/Principal";

// Helper function to create test quote
func createTestQuote() : Types.Quote {
  {
    solver = Principal.fromText("aaaaa-aa");
    output_amount = 1000_000;
    fee = 5_000;
    solver_tip = 1_000;
    expiry = 1000000000000;
    submitted_at = 1000000000000;
    solver_dest_address = ?"0x1234567890abcdef";
  }
};

suite("FeeManager - Initialization", func() {
  test("init creates empty fee state", func() {
    let state = FeeManager.init();

    let collected = FeeManager.getCollectedFees(state, "ICP");
    assert(collected == 0);
    assert(state.total_fees_usd == 0);
  });
});

suite("FeeManager - Fee Calculation", func() {
  test("calculateFees computes correct protocol fee", func() {
    let quote = createTestQuote();
    let outputAmount = 1000_000;
    let protocolFeeBps = 30; // 0.3%

    let breakdown = FeeManager.calculateFees(outputAmount, protocolFeeBps, quote);

    // Protocol fee = 1000_000 * 30 / 10000 = 3000
    assert(breakdown.protocol_fee == 3_000);
  });

  test("calculateFees includes solver fee from quote", func() {
    let quote = createTestQuote();
    let outputAmount = 1000_000;
    let protocolFeeBps = 30;

    let breakdown = FeeManager.calculateFees(outputAmount, protocolFeeBps, quote);

    assert(breakdown.solver_fee == 5_000); // From quote
  });

  test("calculateFees includes solver tip from quote", func() {
    let quote = createTestQuote();
    let outputAmount = 1000_000;
    let protocolFeeBps = 30;

    let breakdown = FeeManager.calculateFees(outputAmount, protocolFeeBps, quote);

    assert(breakdown.solver_tip == 1_000); // From quote
  });

  test("calculateFees computes correct total fees", func() {
    let quote = createTestQuote();
    let outputAmount = 1000_000;
    let protocolFeeBps = 30;

    let breakdown = FeeManager.calculateFees(outputAmount, protocolFeeBps, quote);

    // Total = protocol_fee + solver_fee + solver_tip = 3000 + 5000 + 1000 = 9000
    assert(breakdown.total_fees == 9_000);
  });

  test("calculateFees computes correct net output", func() {
    let quote = createTestQuote();
    let outputAmount = 1000_000;
    let protocolFeeBps = 30;

    let breakdown = FeeManager.calculateFees(outputAmount, protocolFeeBps, quote);

    // Net = output_amount - total_fees = 1000_000 - 9000 = 991_000
    assert(breakdown.net_output == 991_000);
  });

  test("calculateFees handles zero protocol fee", func() {
    let quote = createTestQuote();
    let outputAmount = 1000_000;
    let protocolFeeBps = 0;

    let breakdown = FeeManager.calculateFees(outputAmount, protocolFeeBps, quote);

    assert(breakdown.protocol_fee == 0);
    // Total = 0 + 5000 + 1000 = 6000
    assert(breakdown.total_fees == 6_000);
    assert(breakdown.net_output == 994_000);
  });

  test("calculateFees handles high protocol fee", func() {
    let quote = createTestQuote();
    let outputAmount = 1000_000;
    let protocolFeeBps = 500; // 5%

    let breakdown = FeeManager.calculateFees(outputAmount, protocolFeeBps, quote);

    // Protocol fee = 1000_000 * 500 / 10000 = 50_000
    assert(breakdown.protocol_fee == 50_000);
  });
});

suite("FeeManager - Fee Recording", func() {
  test("recordProtocolFee stores fee amount", func() {
    let state = FeeManager.init();

    FeeManager.recordProtocolFee(state, "ICP", 10_000);

    let collected = FeeManager.getCollectedFees(state, "ICP");
    assert(collected == 10_000);
  });

  test("recordProtocolFee accumulates fees for same token", func() {
    let state = FeeManager.init();

    FeeManager.recordProtocolFee(state, "ICP", 10_000);
    FeeManager.recordProtocolFee(state, "ICP", 5_000);
    FeeManager.recordProtocolFee(state, "ICP", 3_000);

    let collected = FeeManager.getCollectedFees(state, "ICP");
    assert(collected == 18_000);
  });

  test("recordProtocolFee tracks multiple tokens separately", func() {
    let state = FeeManager.init();

    FeeManager.recordProtocolFee(state, "ICP", 10_000);
    FeeManager.recordProtocolFee(state, "ckBTC", 5_000);
    FeeManager.recordProtocolFee(state, "ckETH", 3_000);

    assert(FeeManager.getCollectedFees(state, "ICP") == 10_000);
    assert(FeeManager.getCollectedFees(state, "ckBTC") == 5_000);
    assert(FeeManager.getCollectedFees(state, "ckETH") == 3_000);
  });

  test("getCollectedFees returns zero for untracked token", func() {
    let state = FeeManager.init();

    let collected = FeeManager.getCollectedFees(state, "UNKNOWN");
    assert(collected == 0);
  });
});

suite("FeeManager - Fee Retrieval", func() {
  test("getAllCollectedFees returns all tokens", func() {
    let state = FeeManager.init();

    FeeManager.recordProtocolFee(state, "ICP", 10_000);
    FeeManager.recordProtocolFee(state, "ckBTC", 5_000);

    let allFees = FeeManager.getAllCollectedFees(state);
    assert(allFees.size() == 2);
  });

  test("getAllCollectedFees returns empty for no fees", func() {
    let state = FeeManager.init();

    let allFees = FeeManager.getAllCollectedFees(state);
    assert(allFees.size() == 0);
  });
});

suite("FeeManager - Fee Reset", func() {
  test("resetFees clears token fees", func() {
    let state = FeeManager.init();

    FeeManager.recordProtocolFee(state, "ICP", 10_000);
    FeeManager.resetFees(state, "ICP");

    let collected = FeeManager.getCollectedFees(state, "ICP");
    assert(collected == 0);
  });

  test("resetFees only affects specified token", func() {
    let state = FeeManager.init();

    FeeManager.recordProtocolFee(state, "ICP", 10_000);
    FeeManager.recordProtocolFee(state, "ckBTC", 5_000);

    FeeManager.resetFees(state, "ICP");

    assert(FeeManager.getCollectedFees(state, "ICP") == 0);
    assert(FeeManager.getCollectedFees(state, "ckBTC") == 5_000);
  });

  test("resetFees handles nonexistent token gracefully", func() {
    let state = FeeManager.init();

    FeeManager.resetFees(state, "UNKNOWN"); // Should not error

    let collected = FeeManager.getCollectedFees(state, "UNKNOWN");
    assert(collected == 0);
  });
});

suite("FeeManager - Fee Validation", func() {
  test("validateFeeParams accepts valid fees", func() {
    let outputAmount = 1000_000;
    let protocolFeeBps = 30;
    let solverFee = 5_000;
    let solverTip = 1_000;

    let valid = FeeManager.validateFeeParams(outputAmount, protocolFeeBps, solverFee, solverTip);
    assert(valid);
  });

  test("validateFeeParams rejects fees exceeding output", func() {
    let outputAmount = 10_000;
    let protocolFeeBps = 30; // 3
    let solverFee = 8_000;
    let solverTip = 5_000; // Total = 3 + 8000 + 5000 = 13003 > 10000

    let valid = FeeManager.validateFeeParams(outputAmount, protocolFeeBps, solverFee, solverTip);
    assert(not valid);
  });

  test("validateFeeParams accepts fees equal to output", func() {
    let outputAmount = 10_000;
    let protocolFeeBps = 0;
    let solverFee = 8_000;
    let solverTip = 2_000; // Total = 10000

    let valid = FeeManager.validateFeeParams(outputAmount, protocolFeeBps, solverFee, solverTip);
    assert(valid);
  });

  test("validateFeeParams accepts zero fees", func() {
    let outputAmount = 1000_000;
    let protocolFeeBps = 0;
    let solverFee = 0;
    let solverTip = 0;

    let valid = FeeManager.validateFeeParams(outputAmount, protocolFeeBps, solverFee, solverTip);
    assert(valid);
  });
});

suite("FeeManager - Fee Rate Calculation", func() {
  test("effectiveFeeRate computes correct rate", func() {
    let quote = createTestQuote();
    let outputAmount = 1000_000;
    let protocolFeeBps = 30;

    let breakdown = FeeManager.calculateFees(outputAmount, protocolFeeBps, quote);
    let rate = FeeManager.effectiveFeeRate(breakdown, outputAmount);

    // Total fees = 9000, output = 1000000
    // Rate in bps = (9000 * 10000) / 1000000 = 90 bps = 0.9%
    assert(rate == 90);
  });

  test("effectiveFeeRate handles zero output", func() {
    let breakdown : Types.FeeBreakdown = {
      protocol_fee = 100;
      solver_fee = 100;
      solver_tip = 100;
      total_fees = 300;
      net_output = 0;
    };

    let rate = FeeManager.effectiveFeeRate(breakdown, 0);
    assert(rate == 0); // Should not error
  });

  test("effectiveFeeRate handles zero fees", func() {
    let breakdown : Types.FeeBreakdown = {
      protocol_fee = 0;
      solver_fee = 0;
      solver_tip = 0;
      total_fees = 0;
      net_output = 1000_000;
    };

    let rate = FeeManager.effectiveFeeRate(breakdown, 1000_000);
    assert(rate == 0);
  });
});

suite("FeeManager - Fee Reasonableness", func() {
  test("areFeesReasonable returns true for low fees", func() {
    let quote = createTestQuote();
    let outputAmount = 1000_000;
    let protocolFeeBps = 30; // 0.3%

    let breakdown = FeeManager.calculateFees(outputAmount, protocolFeeBps, quote);
    let reasonable = FeeManager.areFeesReasonable(breakdown, outputAmount);

    assert(reasonable); // 0.9% total < 10%
  });

  test("areFeesReasonable returns false for high fees", func() {
    let highFeeQuote : Types.Quote = {
      solver = Principal.fromText("aaaaa-aa");
      output_amount = 1000_000;
      fee = 100_000; // 10%
      solver_tip = 10_000; // 1%
      expiry = 1000000000000;
      submitted_at = 1000000000000;
      solver_dest_address = ?"0x1234567890abcdef";
    };

    let outputAmount = 1000_000;
    let protocolFeeBps = 0;

    let breakdown = FeeManager.calculateFees(outputAmount, protocolFeeBps, highFeeQuote);
    let reasonable = FeeManager.areFeesReasonable(breakdown, outputAmount);

    // Total = 110_000 = 11% > 10%
    assert(not reasonable);
  });

  test("areFeesReasonable accepts fees just under 10%", func() {
    let highButOkQuote : Types.Quote = {
      solver = Principal.fromText("aaaaa-aa");
      output_amount = 1000_000;
      fee = 98_000;
      solver_tip = 0;
      expiry = 1000000000000;
      submitted_at = 1000000000000;
      solver_dest_address = ?"0x1234567890abcdef";
    };

    let outputAmount = 1000_000;
    let protocolFeeBps = 10; // 0.1% -> 1000

    let breakdown = FeeManager.calculateFees(outputAmount, protocolFeeBps, highButOkQuote);
    let reasonable = FeeManager.areFeesReasonable(breakdown, outputAmount);

    // Total = 1000 + 98000 = 99_000 = 9.9% which is < 1000 bps threshold (10%)
    assert(reasonable);
  });

  test("areFeesReasonable rejects exactly 10%", func() {
    let exactTenPercent : Types.Quote = {
      solver = Principal.fromText("aaaaa-aa");
      output_amount = 1000_000;
      fee = 99_000;
      solver_tip = 0;
      expiry = 1000000000000;
      submitted_at = 1000000000000;
      solver_dest_address = ?"0x1234567890abcdef";
    };

    let outputAmount = 1000_000;
    let protocolFeeBps = 10; // 0.1% -> 1000

    let breakdown = FeeManager.calculateFees(outputAmount, protocolFeeBps, exactTenPercent);
    let reasonable = FeeManager.areFeesReasonable(breakdown, outputAmount);

    // Total = 1000 + 99000 = 100_000 = exactly 10% (1000 bps)
    // Function checks rate < 1000, so exactly 10% is not reasonable
    assert(not reasonable);
  });
});

suite("FeeManager - Total Value Calculation", func() {
  test("calculateTotalValue computes USD value correctly", func() {
    let state = FeeManager.init();
    // Using smaller amounts for clearer math
    FeeManager.recordProtocolFee(state, "ICP", 10_000_000_000_000_000_000); // 10 tokens (18 decimals)
    FeeManager.recordProtocolFee(state, "ckBTC", 2_000_000_000_000_000_000); // 2 tokens (18 decimals)

    let fees = FeeManager.getAllCollectedFees(state);

    let prices = HashMap.HashMap<Text, Nat>(10, Text.equal, Text.hash);
    prices.put("ICP", 500); // $5.00 per ICP token
    prices.put("ckBTC", 5_000_000); // $50,000.00 per ckBTC token

    let totalValue = FeeManager.calculateTotalValue(fees, prices);

    // ICP: (10_000_000_000_000_000_000 * 500) / 1_000_000_000_000_000_000 = 5_000 cents
    // ckBTC: (2_000_000_000_000_000_000 * 5_000_000) / 1_000_000_000_000_000_000 = 10_000_000 cents
    // Total = 5_000 + 10_000_000 = 10_005_000 cents
    assert(totalValue == 10_005_000);
  });

  test("calculateTotalValue skips tokens without prices", func() {
    let state = FeeManager.init();
    FeeManager.recordProtocolFee(state, "ICP", 100_000_000_000_000_000_000);
    FeeManager.recordProtocolFee(state, "UNKNOWN", 999_000_000_000_000_000_000);

    let fees = FeeManager.getAllCollectedFees(state);

    let prices = HashMap.HashMap<Text, Nat>(10, Text.equal, Text.hash);
    prices.put("ICP", 500);
    // No price for UNKNOWN

    let totalValue = FeeManager.calculateTotalValue(fees, prices);

    // Only ICP counted: 100 * 500 = 50000
    assert(totalValue == 50000);
  });

  test("calculateTotalValue handles empty fees", func() {
    let state = FeeManager.init();
    let fees = FeeManager.getAllCollectedFees(state);

    let prices = HashMap.HashMap<Text, Nat>(10, Text.equal, Text.hash);

    let totalValue = FeeManager.calculateTotalValue(fees, prices);
    assert(totalValue == 0);
  });
});
