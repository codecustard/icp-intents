import { test; suite } = "mo:test";
import TokenRegistry "../src/icp-intents-lib/tokens/TokenRegistry";
import Principal "mo:base/Principal";

suite("TokenRegistry - Initialization", func() {
  test("init creates empty registry", func() {
    let state = TokenRegistry.init();

    let ledger = TokenRegistry.getLedger(state, "ICP");
    assert(ledger == null);
  });
});

suite("TokenRegistry - Token Registration", func() {
  test("registerToken stores token info", func() {
    let state = TokenRegistry.init();
    let icpLedger = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

    TokenRegistry.registerToken(state, "ICP", icpLedger, 8, 10_000);

    let retrieved = TokenRegistry.getLedger(state, "ICP");
    switch (retrieved) {
      case (?ledger) {
        assert(Principal.equal(ledger, icpLedger));
      };
      case null { assert(false) };
    };
  });

  test("registerToken stores correct decimals", func() {
    let state = TokenRegistry.init();
    let icpLedger = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

    TokenRegistry.registerToken(state, "ICP", icpLedger, 8, 10_000);

    let info = TokenRegistry.getTokenInfo(state, "ICP");
    switch (info) {
      case (?i) {
        assert(i.decimals == 8);
      };
      case null { assert(false) };
    };
  });

  test("registerToken stores correct fee", func() {
    let state = TokenRegistry.init();
    let icpLedger = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

    TokenRegistry.registerToken(state, "ICP", icpLedger, 8, 10_000);

    let info = TokenRegistry.getTokenInfo(state, "ICP");
    switch (info) {
      case (?i) {
        assert(i.fee == 10_000);
      };
      case null { assert(false) };
    };
  });

  test("registerToken overwrites existing token", func() {
    let state = TokenRegistry.init();
    let oldLedger = Principal.fromText("aaaaa-aa");
    let newLedger = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

    TokenRegistry.registerToken(state, "ICP", oldLedger, 8, 10_000);
    TokenRegistry.registerToken(state, "ICP", newLedger, 8, 5_000);

    let retrieved = TokenRegistry.getLedger(state, "ICP");
    switch (retrieved) {
      case (?ledger) {
        assert(Principal.equal(ledger, newLedger));
      };
      case null { assert(false) };
    };

    let info = TokenRegistry.getTokenInfo(state, "ICP");
    switch (info) {
      case (?i) {
        assert(i.fee == 5_000);
      };
      case null { assert(false) };
    };
  });

  test("can register multiple tokens", func() {
    let state = TokenRegistry.init();
    let icpLedger = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
    let ckbtcLedger = Principal.fromText("mxzaz-hqaaa-aaaar-qaada-cai");
    let ckethLedger = Principal.fromText("ss2fx-dyaaa-aaaar-qacoq-cai");

    TokenRegistry.registerToken(state, "ICP", icpLedger, 8, 10_000);
    TokenRegistry.registerToken(state, "ckBTC", ckbtcLedger, 8, 10);
    TokenRegistry.registerToken(state, "ckETH", ckethLedger, 18, 2_000);

    assert(TokenRegistry.getLedger(state, "ICP") != null);
    assert(TokenRegistry.getLedger(state, "ckBTC") != null);
    assert(TokenRegistry.getLedger(state, "ckETH") != null);
  });
});

suite("TokenRegistry - Token Lookup", func() {
  test("getLedger returns None for unregistered token", func() {
    let state = TokenRegistry.init();

    let ledger = TokenRegistry.getLedger(state, "UNKNOWN");
    assert(ledger == null);
  });

  test("getTokenInfo returns complete info", func() {
    let state = TokenRegistry.init();
    let icpLedger = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

    TokenRegistry.registerToken(state, "ICP", icpLedger, 8, 10_000);

    let info = TokenRegistry.getTokenInfo(state, "ICP");
    switch (info) {
      case (?i) {
        assert(i.symbol == "ICP");
        assert(Principal.equal(i.ledger_principal, icpLedger));
        assert(i.decimals == 8);
        assert(i.fee == 10_000);
      };
      case null { assert(false) };
    };
  });

  test("getTokenInfo returns None for unregistered token", func() {
    let state = TokenRegistry.init();

    let info = TokenRegistry.getTokenInfo(state, "UNKNOWN");
    assert(info == null);
  });

  test("isRegistered returns true for registered token", func() {
    let state = TokenRegistry.init();
    let icpLedger = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

    TokenRegistry.registerToken(state, "ICP", icpLedger, 8, 10_000);

    assert(TokenRegistry.isRegistered(state, "ICP"));
  });

  test("isRegistered returns false for unregistered token", func() {
    let state = TokenRegistry.init();

    assert(not TokenRegistry.isRegistered(state, "UNKNOWN"));
  });
});

suite("TokenRegistry - List Tokens", func() {
  test("listTokens returns empty array for empty registry", func() {
    let state = TokenRegistry.init();

    let tokens = TokenRegistry.listTokens(state);
    assert(tokens.size() == 0);
  });

  test("listTokens returns all registered tokens", func() {
    let state = TokenRegistry.init();
    let icpLedger = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
    let ckbtcLedger = Principal.fromText("mxzaz-hqaaa-aaaar-qaada-cai");
    let ckethLedger = Principal.fromText("ss2fx-dyaaa-aaaar-qacoq-cai");

    TokenRegistry.registerToken(state, "ICP", icpLedger, 8, 10_000);
    TokenRegistry.registerToken(state, "ckBTC", ckbtcLedger, 8, 10);
    TokenRegistry.registerToken(state, "ckETH", ckethLedger, 18, 2_000);

    let tokens = TokenRegistry.listTokens(state);
    assert(tokens.size() == 3);

    // Check that all tokens are in the list
    var foundICP = false;
    var foundCkBTC = false;
    var foundCkETH = false;

    for (token in tokens.vals()) {
      if (token == "ICP") { foundICP := true };
      if (token == "ckBTC") { foundCkBTC := true };
      if (token == "ckETH") { foundCkETH := true };
    };

    assert(foundICP);
    assert(foundCkBTC);
    assert(foundCkETH);
  });

  test("listTokens reflects overwrites", func() {
    let state = TokenRegistry.init();
    let ledger1 = Principal.fromText("aaaaa-aa");
    let ledger2 = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

    TokenRegistry.registerToken(state, "ICP", ledger1, 8, 10_000);
    TokenRegistry.registerToken(state, "ICP", ledger2, 8, 5_000); // Overwrite

    let tokens = TokenRegistry.listTokens(state);
    assert(tokens.size() == 1); // Still only one token
  });
});

suite("TokenRegistry - Edge Cases", func() {
  test("handles zero decimals", func() {
    let state = TokenRegistry.init();
    let ledger = Principal.fromText("aaaaa-aa");

    TokenRegistry.registerToken(state, "TEST", ledger, 0, 0);

    let info = TokenRegistry.getTokenInfo(state, "TEST");
    switch (info) {
      case (?i) {
        assert(i.decimals == 0);
        assert(i.fee == 0);
      };
      case null { assert(false) };
    };
  });

  test("handles high decimals (18)", func() {
    let state = TokenRegistry.init();
    let ledger = Principal.fromText("aaaaa-aa");

    TokenRegistry.registerToken(state, "ETH", ledger, 18, 1_000);

    let info = TokenRegistry.getTokenInfo(state, "ETH");
    switch (info) {
      case (?i) {
        assert(i.decimals == 18);
      };
      case null { assert(false) };
    };
  });

  test("handles large fee values", func() {
    let state = TokenRegistry.init();
    let ledger = Principal.fromText("aaaaa-aa");
    let largeFee = 1_000_000_000;

    TokenRegistry.registerToken(state, "EXPENSIVE", ledger, 8, largeFee);

    let info = TokenRegistry.getTokenInfo(state, "EXPENSIVE");
    switch (info) {
      case (?i) {
        assert(i.fee == largeFee);
      };
      case null { assert(false) };
    };
  });
});
