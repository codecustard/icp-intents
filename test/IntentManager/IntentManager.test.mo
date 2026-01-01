/// Unit tests for IntentManager core business logic
/// Tests intent creation, quote submission, cancellation, and state transitions

import {test; suite} "mo:test";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import IntentManager "../../src/icp-intents-lib/managers/IntentManager";
import Types "../../src/icp-intents-lib/core/Types";
import ChainRegistry "../../src/icp-intents-lib/chains/ChainRegistry";

suite("IntentManager", func() {

  // Test helpers
  func createTestConfig() : Types.SystemConfig {
    {
      protocol_fee_bps = 30;
      fee_collector = Principal.fromText("aaaaa-aa");
      supported_chains = [
        #EVM({ chain_id = 1; name = "ethereum"; network = "mainnet"; rpc_urls = null }),
        #EVM({ chain_id = 11155111; name = "sepolia"; network = "testnet"; rpc_urls = null }),
        #Hoosat({ network = "mainnet"; rpc_url = "https://api.network.hoosat.fi"; min_confirmations = 10 }),
      ];
      min_intent_amount = 1_000;
      max_intent_amount = 1_000_000_000_000;
      default_deadline_duration = 3600_000_000_000; // 1 hour
      solver_allowlist = null;
    }
  };

  func createTestState() : IntentManager.ManagerState {
    let state = IntentManager.init(createTestConfig());

    // Register supported chains
    let config = createTestConfig();
    for (chain in config.supported_chains.vals()) {
      switch (chain) {
        case (#EVM(evm)) {
          ChainRegistry.registerChain(state.chain_registry, evm.name, chain);
        };
        case (#Hoosat(hoosat)) {
          ChainRegistry.registerChain(state.chain_registry, "hoosat", chain);
        };
        case (#Bitcoin(btc)) {
          ChainRegistry.registerChain(state.chain_registry, "bitcoin", chain);
        };
        case (#Custom(custom)) {
          ChainRegistry.registerChain(state.chain_registry, custom.name, chain);
        };
      };
    };

    // Also register ICP as source chain (not in Chain enum, so add manually)
    ChainRegistry.registerChain(state.chain_registry, "icp", #Custom({
      name = "icp";
      network = "mainnet";
      verification_canister = null;
      metadata = null;
    }));

    state
  };

  func createChainSpec(chain: Text, chainId: ?Nat, token: Text) : Types.ChainSpec {
    {
      chain = chain;
      chain_id = chainId;
      token = token;
      network = "mainnet";
    }
  };

  // ========================================
  // createIntent Tests
  // ========================================

  test("createIntent creates intent with valid parameters", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("icp", null, "ICP");
    let destination = createChainSpec("ethereum", ?1, "ETH");

    let result = IntentManager.createIntent(
      state,
      alice,
      source,
      destination,
      10_000, // source_amount
      9_000,  // min_output
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0", // dest_recipient
      currentTime + 1800_000_000_000, // deadline (30 min)
      currentTime
    );

    switch (result) {
      case (#ok(intentId)) {
        assert(intentId == 0); // First intent

        // Verify intent was created
        let intent = IntentManager.getIntent(state, intentId);
        switch (intent) {
          case (?i) {
            assert(i.id == 0);
            assert(i.user == alice);
            assert(i.source_amount == 10_000);
            assert(i.min_output == 9_000);
            assert(i.status == #PendingQuote);
            assert(i.quotes.size() == 0);
            assert(i.selected_quote == null);
          };
          case null { assert(false) };
        };
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("createIntent increments ID for multiple intents", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("icp", null, "ICP");
    let destination = createChainSpec("ethereum", ?1, "ETH");

    // Create first intent
    let result1 = IntentManager.createIntent(
      state, alice, source, destination, 10_000, 9_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 1800_000_000_000, currentTime
    );
    assert(result1 == #ok(0));

    // Create second intent
    let result2 = IntentManager.createIntent(
      state, alice, source, destination, 20_000, 18_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 1800_000_000_000, currentTime
    );
    assert(result2 == #ok(1));

    // Create third intent
    let result3 = IntentManager.createIntent(
      state, alice, source, destination, 30_000, 27_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 1800_000_000_000, currentTime
    );
    assert(result3 == #ok(2));
  });

  test("createIntent rejects zero amount", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("icp", null, "ICP");
    let destination = createChainSpec("ethereum", ?1, "ETH");

    let result = IntentManager.createIntent(
      state, alice, source, destination,
      0, // zero amount
      9_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 1800_000_000_000, currentTime
    );

    switch (result) {
      case (#err(#InvalidAmount(_))) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("createIntent rejects amount below minimum", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("icp", null, "ICP");
    let destination = createChainSpec("ethereum", ?1, "ETH");

    let result = IntentManager.createIntent(
      state, alice, source, destination,
      999, // Below minimum (1000)
      900,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 1800_000_000_000, currentTime
    );

    switch (result) {
      case (#err(#InvalidAmount(_))) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("createIntent rejects amount above maximum", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("icp", null, "ICP");
    let destination = createChainSpec("ethereum", ?1, "ETH");

    let result = IntentManager.createIntent(
      state, alice, source, destination,
      1_000_000_000_001, // Above maximum
      900_000_000_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 1800_000_000_000, currentTime
    );

    switch (result) {
      case (#err(#InvalidAmount(_))) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("createIntent rejects zero min_output", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("icp", null, "ICP");
    let destination = createChainSpec("ethereum", ?1, "ETH");

    let result = IntentManager.createIntent(
      state, alice, source, destination,
      10_000,
      0, // zero min_output
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 1800_000_000_000, currentTime
    );

    switch (result) {
      case (#err(#InvalidAmount(_))) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("createIntent rejects past deadline", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("icp", null, "ICP");
    let destination = createChainSpec("ethereum", ?1, "ETH");

    let result = IntentManager.createIntent(
      state, alice, source, destination,
      10_000, 9_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime - 1000, // Past deadline
      currentTime
    );

    switch (result) {
      case (#err(#InvalidDeadline(_))) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("createIntent rejects deadline too far in future", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("icp", null, "ICP");
    let destination = createChainSpec("ethereum", ?1, "ETH");

    // Max allowed is 30x default duration = 30 hours
    let tooFar = currentTime + (31 * 3600_000_000_000);

    let result = IntentManager.createIntent(
      state, alice, source, destination,
      10_000, 9_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      tooFar,
      currentTime
    );

    switch (result) {
      case (#err(#InvalidDeadline(_))) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("createIntent rejects empty chain name", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("", null, "ICP"); // Empty chain
    let destination = createChainSpec("ethereum", ?1, "ETH");

    let result = IntentManager.createIntent(
      state, alice, source, destination,
      10_000, 9_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 1800_000_000_000, currentTime
    );

    switch (result) {
      case (#err(#InvalidChain(_))) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("createIntent rejects unsupported chain", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("icp", null, "ICP");
    let destination = createChainSpec("bitcoin", null, "BTC"); // Not in supported_chains

    let result = IntentManager.createIntent(
      state, alice, source, destination,
      10_000, 9_000,
      "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
      currentTime + 1800_000_000_000, currentTime
    );

    switch (result) {
      case (#err(#ChainNotSupported(_))) {}; // Expected
      case _ { assert(false) };
    };
  });

  // ========================================
  // submitQuote Tests
  // ========================================

  test("submitQuote successfully submits quote for pending intent", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let solver = Principal.fromText("2vxsx-fae");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("icp", null, "ICP");
    let destination = createChainSpec("ethereum", ?1, "ETH");

    // Create intent
    let createResult = IntentManager.createIntent(
      state, alice, source, destination,
      100_000, 90_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 3600_000_000_000, currentTime
    );

    let intentId = switch (createResult) {
      case (#ok(id)) id;
      case (#err(_)) { assert(false); 0 };
    };

    // Submit quote
    let quoteResult = IntentManager.submitQuote(
      state,
      intentId,
      solver,
      95_000, // output_amount
      4_000,  // fee
      1_000,  // solver_tip
      null,   // solver_dest_address
      currentTime
    );

    switch (quoteResult) {
      case (#ok(_)) {
        // Verify quote was added
        let intent = IntentManager.getIntent(state, intentId);
        switch (intent) {
          case (?i) {
            assert(i.status == #Quoted);
            assert(i.quotes.size() == 1);
            assert(i.quotes[0].solver == solver);
            assert(i.quotes[0].output_amount == 95_000);
            assert(i.quotes[0].fee == 4_000);
            assert(i.quotes[0].solver_tip == 1_000);
          };
          case null { assert(false) };
        };
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("submitQuote accepts multiple quotes", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let solver1 = Principal.fromText("2vxsx-fae");
    let solver2 = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("icp", null, "ICP");
    let destination = createChainSpec("ethereum", ?1, "ETH");

    // Create intent
    let intentId = switch (IntentManager.createIntent(
      state, alice, source, destination,
      100_000, 90_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 3600_000_000_000, currentTime
    )) {
      case (#ok(id)) id;
      case (#err(_)) { assert(false); 0 };
    };

    // Solver 1 submits quote
    ignore IntentManager.submitQuote(state, intentId, solver1, 95_000, 4_000, 1_000, null, currentTime);

    // Solver 2 submits better quote
    ignore IntentManager.submitQuote(state, intentId, solver2, 96_000, 3_000, 1_000, null, currentTime);

    // Verify both quotes exist
    let intent = IntentManager.getIntent(state, intentId);
    switch (intent) {
      case (?i) {
        assert(i.quotes.size() == 2);
        assert(i.quotes[0].solver == solver1);
        assert(i.quotes[1].solver == solver2);
      };
      case null { assert(false) };
    };
  });

  test("submitQuote rejects non-existent intent", func() {
    let state = createTestState();
    let solver = Principal.fromText("2vxsx-fae");
    let currentTime : Time.Time = 1_000_000_000;

    let result = IntentManager.submitQuote(
      state,
      999, // Doesn't exist
      solver,
      95_000, 4_000, 1_000, null,
      currentTime
    );

    switch (result) {
      case (#err(#NotFound)) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("submitQuote rejects output below min_output", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let solver = Principal.fromText("2vxsx-fae");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("icp", null, "ICP");
    let destination = createChainSpec("ethereum", ?1, "ETH");

    // Create intent with min_output = 90_000
    let intentId = switch (IntentManager.createIntent(
      state, alice, source, destination,
      100_000, 90_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 3600_000_000_000, currentTime
    )) {
      case (#ok(id)) id;
      case (#err(_)) { assert(false); 0 };
    };

    // Try to submit quote below min_output
    let result = IntentManager.submitQuote(
      state, intentId, solver,
      89_000, // Below min_output
      4_000, 1_000, null, currentTime
    );

    switch (result) {
      case (#err(#InvalidQuote(_))) {}; // Expected
      case _ { assert(false) };
    };
  });

  test("submitQuote rejects for expired intent", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let solver = Principal.fromText("2vxsx-fae");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("icp", null, "ICP");
    let destination = createChainSpec("ethereum", ?1, "ETH");

    // Create intent with short deadline
    let intentId = switch (IntentManager.createIntent(
      state, alice, source, destination,
      100_000, 90_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 1000, // Very short deadline
      currentTime
    )) {
      case (#ok(id)) id;
      case (#err(_)) { assert(false); 0 };
    };

    // Wait for intent to expire
    let laterTime = currentTime + 2000;

    let result = IntentManager.submitQuote(
      state, intentId, solver,
      95_000, 4_000, 1_000, null,
      laterTime // After deadline
    );

    switch (result) {
      case (#err(#Expired)) {}; // Expected
      case _ { assert(false) };
    };
  });

  // ========================================
  // cancelIntent Tests
  // ========================================
  // NOTE: cancelIntent is async and cannot be tested in non-async test files
  // These tests should be added to IntentManager.replica.test.mo

  // ========================================
  // getIntent / getUserIntents Tests
  // ========================================

  test("getIntent returns intent by ID", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("icp", null, "ICP");
    let destination = createChainSpec("ethereum", ?1, "ETH");

    let intentId = switch (IntentManager.createIntent(
      state, alice, source, destination,
      100_000, 90_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 3600_000_000_000, currentTime
    )) {
      case (#ok(id)) id;
      case (#err(_)) { assert(false); 0 };
    };

    let intent = IntentManager.getIntent(state, intentId);
    switch (intent) {
      case (?i) {
        assert(i.id == intentId);
        assert(i.user == alice);
      };
      case null { assert(false) };
    };
  });

  test("getIntent returns null for non-existent ID", func() {
    let state = createTestState();

    let intent = IntentManager.getIntent(state, 999);
    assert(intent == null);
  });

  test("getUserIntents returns user's intents", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let bob = Principal.fromText("2vxsx-fae");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("icp", null, "ICP");
    let destination = createChainSpec("ethereum", ?1, "ETH");

    // Alice creates 2 intents
    ignore IntentManager.createIntent(
      state, alice, source, destination,
      10_000, 9_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 3600_000_000_000, currentTime
    );
    ignore IntentManager.createIntent(
      state, alice, source, destination,
      20_000, 18_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 3600_000_000_000, currentTime
    );

    // Bob creates 1 intent
    ignore IntentManager.createIntent(
      state, bob, source, destination,
      30_000, 27_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 3600_000_000_000, currentTime
    );

    // Get Alice's intents
    let aliceIntents = IntentManager.getUserIntents(state, alice);
    assert(aliceIntents.size() == 2);
    assert(aliceIntents[0].user == alice);
    assert(aliceIntents[1].user == alice);

    // Get Bob's intents
    let bobIntents = IntentManager.getUserIntents(state, bob);
    assert(bobIntents.size() == 1);
    assert(bobIntents[0].user == bob);
  });

  test("getUserIntents returns empty array for user with no intents", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");

    let intents = IntentManager.getUserIntents(state, alice);
    assert(intents.size() == 0);
  });

  // ========================================
  // State Transition Tests
  // ========================================

  test("intent transitions from PendingQuote to Quoted after first quote", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let solver = Principal.fromText("2vxsx-fae");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("icp", null, "ICP");
    let destination = createChainSpec("ethereum", ?1, "ETH");

    // Create intent (starts in PendingQuote)
    let intentId = switch (IntentManager.createIntent(
      state, alice, source, destination,
      100_000, 90_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 3600_000_000_000, currentTime
    )) {
      case (#ok(id)) id;
      case (#err(_)) { assert(false); 0 };
    };

    let intent1 = IntentManager.getIntent(state, intentId);
    switch (intent1) {
      case (?i) { assert(i.status == #PendingQuote) };
      case null { assert(false) };
    };

    // Submit quote (should transition to Quoted)
    ignore IntentManager.submitQuote(
      state, intentId, solver,
      95_000, 4_000, 1_000, null, currentTime
    );

    let intent2 = IntentManager.getIntent(state, intentId);
    switch (intent2) {
      case (?i) { assert(i.status == #Quoted) };
      case null { assert(false) };
    };
  });

  test("intent stays in Quoted after additional quotes", func() {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let solver1 = Principal.fromText("2vxsx-fae");
    let solver2 = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let currentTime : Time.Time = 1_000_000_000;

    let source = createChainSpec("icp", null, "ICP");
    let destination = createChainSpec("ethereum", ?1, "ETH");

    let intentId = switch (IntentManager.createIntent(
      state, alice, source, destination,
      100_000, 90_000,
      "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
      currentTime + 3600_000_000_000, currentTime
    )) {
      case (#ok(id)) id;
      case (#err(_)) { assert(false); 0 };
    };

    // First quote
    ignore IntentManager.submitQuote(state, intentId, solver1, 95_000, 4_000, 1_000, null, currentTime);

    let intent1 = IntentManager.getIntent(state, intentId);
    switch (intent1) {
      case (?i) { assert(i.status == #Quoted) };
      case null { assert(false) };
    };

    // Second quote (should stay Quoted)
    ignore IntentManager.submitQuote(state, intentId, solver2, 96_000, 3_000, 1_000, null, currentTime);

    let intent2 = IntentManager.getIntent(state, intentId);
    switch (intent2) {
      case (?i) {
        assert(i.status == #Quoted);
        assert(i.quotes.size() == 2);
      };
      case null { assert(false) };
    };
  });

  // NOTE: "intent transitions to Cancelled" test is async
  // and should be added to IntentManager.replica.test.mo

});
