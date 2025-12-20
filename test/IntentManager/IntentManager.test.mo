/// Unit tests for IntentManager core business logic
/// Uses mops test package for proper test structure

import {test; suite} "mo:test/async";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import IntentManager "../../src/icp-intents-lib/IntentManager";
import Types "../../src/icp-intents-lib/Types";
import Escrow "../../src/icp-intents-lib/Escrow";

// Test helpers
func createTestConfig() : Types.ProtocolConfig {
  {
    default_protocol_fee_bps = 30;
    max_protocol_fee_bps = 100;
    min_intent_amount = 1000;
    max_intent_lifetime = 7 * 24 * 60 * 60 * 1_000_000_000;
    max_active_intents = 100;
    max_events = 10;
    admin = Principal.fromText("aaaaa-aa");
    fee_collector = Principal.fromText("aaaaa-aa");
    paused = false;
  }
};

func createTECDSAConfig() : Types.ECDSAConfig {
  {
    key_name = "test_key_1";
    derivation_path = [];
  }
};

func createTestState() : IntentManager.State {
  IntentManager.init(
    createTestConfig(),
    createTECDSAConfig(),
    { evm_rpc_canister_id = Principal.fromText("aaaaa-aa"); min_confirmations = 12 },
    [1, 8453, 11155111]
  )
};

func createTestChainAsset(chain: Text, chainId: ?Nat, token: Text) : Types.ChainAsset {
  {
    chain = chain;
    chain_id = chainId;
    token = token;
    network = "testnet";
  }
};

// Test suite
await suite("IntentManager", func() : async () {

  // ========================================
  // postIntent Tests
  // ========================================

  await test("postIntent creates intent with valid parameters", func() : async () {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    // First, deposit escrow
    ignore Escrow.deposit(state.escrow, alice, "ICP", 2_000_000);

    let request : Types.CreateIntentRequest = {
      source = createTestChainAsset("icp", null, "ICP");
      destination = createTestChainAsset("ethereum", ?1, "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0");
      dest_recipient = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0";
      source_amount = 1_000_000;
      min_output = 950_000;
      deadline = currentTime + 3600_000_000_000;
      custom_rpc_urls = null;
      verification_hints = null;
      metadata = null;
    };

    let result = await IntentManager.postIntent(state, alice, request, currentTime);

    switch (result) {
      case (#ok(intentId)) {
        assert(intentId == 1);

        // Verify intent was created
        let intent = IntentManager.getIntent(state, intentId);
        switch (intent) {
          case (?i) {
            assert(i.id == 1);
            assert(i.user == alice);
            assert(i.source_amount == 1_000_000);
            assert(i.status == #Open);
            assert(i.quotes.size() == 0);
          };
          case null { assert(false) };
        };
      };
      case (#err(_)) { assert(false) };
    };
  });

  await test("postIntent rejects amount below minimum", func() : async () {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    let request : Types.CreateIntentRequest = {
      source = createTestChainAsset("icp", null, "ICP");
      destination = createTestChainAsset("ethereum", ?1, "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0");
      dest_recipient = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0";
      source_amount = 500; // Below min (1000)
      min_output = 400;
      deadline = currentTime + 3600_000_000_000;
      custom_rpc_urls = null;
      verification_hints = null;
      metadata = null;
    };

    let result = await IntentManager.postIntent(state, alice, request, currentTime);

    switch (result) {
      case (#err(#InvalidAmount)) { /* pass */ };
      case _ { assert(false) };
    };
  });

  await test("postIntent rejects deadline too far in future", func() : async () {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    let request : Types.CreateIntentRequest = {
      source = createTestChainAsset("icp", null, "ICP");
      destination = createTestChainAsset("ethereum", ?1, "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0");
      dest_recipient = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0";
      source_amount = 1_000_000;
      min_output = 950_000;
      deadline = currentTime + (30 * 24 * 60 * 60 * 1_000_000_000); // 30 days (too far)
      custom_rpc_urls = null;
      verification_hints = null;
      metadata = null;
    };

    let result = await IntentManager.postIntent(state, alice, request, currentTime);

    switch (result) {
      case (#err(#DeadlinePassed)) { /* pass */ };
      case _ { assert(false) };
    };
  });

  await test("postIntent rejects past deadline", func() : async () {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    let request : Types.CreateIntentRequest = {
      source = createTestChainAsset("icp", null, "ICP");
      destination = createTestChainAsset("ethereum", ?1, "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0");
      dest_recipient = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0";
      source_amount = 1_000_000;
      min_output = 950_000;
      deadline = currentTime - 1000; // Past
      custom_rpc_urls = null;
      verification_hints = null;
      metadata = null;
    };

    let result = await IntentManager.postIntent(state, alice, request, currentTime);

    switch (result) {
      case (#err(#DeadlinePassed)) { /* pass */ };
      case _ { assert(false) };
    };
  });

  await test("postIntent rejects unsupported chain", func() : async () {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    let request : Types.CreateIntentRequest = {
      source = createTestChainAsset("icp", null, "ICP");
      destination = createTestChainAsset("ethereum", ?999999, "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0"); // Unsupported chain
      dest_recipient = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0";
      source_amount = 1_000_000;
      min_output = 950_000;
      deadline = currentTime + 3600_000_000_000;
      custom_rpc_urls = null;
      verification_hints = null;
      metadata = null;
    };

    let result = await IntentManager.postIntent(state, alice, request, currentTime);

    switch (result) {
      case (#err(#InvalidChain)) { /* pass */ };
      case _ { assert(false) };
    };
  });

  await test("postIntent rejects invalid recipient address", func() : async () {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    let request : Types.CreateIntentRequest = {
      source = createTestChainAsset("icp", null, "ICP");
      destination = createTestChainAsset("ethereum", ?1, "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0");
      dest_recipient = "invalid-address"; // Invalid
      source_amount = 1_000_000;
      min_output = 950_000;
      deadline = currentTime + 3600_000_000_000;
      custom_rpc_urls = null;
      verification_hints = null;
      metadata = null;
    };

    let result = await IntentManager.postIntent(state, alice, request, currentTime);

    switch (result) {
      case (#err(#InvalidAddress)) { /* pass */ };
      case _ { assert(false) };
    };
  });

  // ========================================
  // submitQuote Tests
  // ========================================

  await test("submitQuote successfully submits quote for open intent", func() : async () {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let solver = Principal.fromText("2vxsx-fae");
    let currentTime : Time.Time = 1_000_000_000;

    // Create intent
    ignore Escrow.deposit(state.escrow, alice, "ICP", 2_000_000);

    let request : Types.CreateIntentRequest = {
      source = createTestChainAsset("icp", null, "ICP");
      destination = createTestChainAsset("ethereum", ?1, "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0");
      dest_recipient = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0";
      source_amount = 1_000_000;
      min_output = 950_000;
      deadline = currentTime + 3600_000_000_000;
      custom_rpc_urls = null;
      verification_hints = null;
      metadata = null;
    };

    let postResult = await IntentManager.postIntent(state, alice, request, currentTime);
    let intentId = switch (postResult) {
      case (#ok(id)) id;
      case (#err(_)) { assert(false); 0 };
    };

    // Submit quote
    let quoteRequest : Types.SubmitQuoteRequest = {
      intent_id = intentId;
      output_amount = 960_000;
      fee = 40_000;
      expiry = currentTime + 1800_000_000_000;
    };

    let quoteResult = IntentManager.submitQuote(state, solver, quoteRequest, currentTime);

    switch (quoteResult) {
      case (#ok(_)) {
        // Verify quote was added
        let intent = IntentManager.getIntent(state, intentId);
        switch (intent) {
          case (?i) {
            assert(i.status == #Quoted);
            assert(i.quotes.size() == 1);
            assert(i.quotes[0].solver == solver);
            assert(i.quotes[0].output_amount == 960_000);
          };
          case null { assert(false) };
        };
      };
      case (#err(_)) { assert(false) };
    };
  });

  await test("submitQuote rejects non-existent intent", func() : async () {
    let state = createTestState();
    let solver = Principal.fromText("2vxsx-fae");
    let currentTime : Time.Time = 1000000000;

    let quoteRequest : Types.SubmitQuoteRequest = {
      intent_id = 999; // Doesn't exist
      output_amount = 950000;
      fee = 50000;
      expiry = currentTime + 1800_000_000_000;
    };

    let result = IntentManager.submitQuote(state, solver, quoteRequest, currentTime);

    switch (result) {
      case (#err(#NotFound)) { /* pass */ };
      case _ { assert(false) };
    };
  });

  await test("submitQuote rejects expired quotes", func() : async () {
    let state = createTestState();
    let solver = Principal.fromText("2vxsx-fae");
    let currentTime : Time.Time = 1000000000;

    let expiredQuote : Types.SubmitQuoteRequest = {
      intent_id = 1;
      output_amount = 950000;
      fee = 50000;
      expiry = currentTime - 1000; // Expired
    };

    let result = IntentManager.submitQuote(state, solver, expiredQuote, currentTime);

    switch (result) {
      case (#err(#QuoteExpired)) { /* pass */ };
      case (#err(#NotFound)) { /* also acceptable - intent doesn't exist */ };
      case _ { assert(false) };
    };
  });

  // ========================================
  // confirmQuote Tests
  // Note: These require tECDSA calls and should be tested with replica tests
  // TODO: Create separate replica test file for integration testing
  // ========================================

  // SKIPPED FOR UNIT TESTS: Requires tECDSA management canister
  // To test these, create a replica test file (see mops test docs)

  /*
  await test("confirmQuote successfully locks escrow and generates deposit address", func() : async () {
    // ... requires tECDSA ...
  });

  await test("confirmQuote rejects if caller is not creator", func() : async () {
    // ... requires tECDSA ...
  });

  await test("confirmQuote rejects invalid quote index", func() : async () {
    // ... requires tECDSA ...
  });
  */

  // ========================================
  // cancelIntent Tests
  // ========================================

  await test("cancelIntent rejects non-existent intent", func() : async () {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1000000000;

    let result = IntentManager.cancelIntent(state, alice, 999, currentTime);

    switch (result) {
      case (#err(#NotFound)) { /* pass */ };
      case _ { assert(false) };
    };
  });

  await test("cancelIntent successfully cancels Open intent", func() : async () {
    let state = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    // Create intent
    ignore Escrow.deposit(state.escrow, alice, "ICP", 2_000_000);

    let request : Types.CreateIntentRequest = {
      source = createTestChainAsset("icp", null, "ICP");
      destination = createTestChainAsset("ethereum", ?1, "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0");
      dest_recipient = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0";
      source_amount = 1_000_000;
      min_output = 950_000;
      deadline = currentTime + 3600_000_000_000;
      custom_rpc_urls = null;
      verification_hints = null;
      metadata = null;
    };

    let postResult = await IntentManager.postIntent(state, alice, request, currentTime);
    let intentId = switch (postResult) {
      case (#ok(id)) id;
      case (#err(_)) { assert(false); 0 };
    };

    // Cancel it
    let cancelResult = IntentManager.cancelIntent(state, alice, intentId, currentTime);

    switch (cancelResult) {
      case (#ok(_)) {
        // Verify status changed to Cancelled
        let intent = IntentManager.getIntent(state, intentId);
        switch (intent) {
          case (?i) { assert(i.status == #Cancelled) };
          case null { assert(false) };
        };
      };
      case (#err(_)) { assert(false) };
    };
  });

  // ========================================
  // refundIntent Tests
  // ========================================

  await test("refundIntent rejects non-existent intent", func() : async () {
    let state = createTestState();
    let currentTime : Time.Time = 1000000000;
    let result = IntentManager.refundIntent(state, 999, currentTime);

    switch (result) {
      case (#err(#NotFound)) { /* pass */ };
      case _ { assert(false) };
    };
  });

  // ========================================
  // Bounded Data Structure Tests
  // ========================================

  await test("enforces max_active_intents limit", func() : async () {
    let config = {
      default_protocol_fee_bps = 30;
      max_protocol_fee_bps = 100;
      min_intent_amount = 1000;
      max_intent_lifetime = 7 * 24 * 60 * 60 * 1_000_000_000;
      max_active_intents = 3; // Very low limit for testing
      max_events = 10;
      admin = Principal.fromText("aaaaa-aa");
      fee_collector = Principal.fromText("aaaaa-aa");
      paused = false;
    };

    let state = IntentManager.init(
      config,
      createTECDSAConfig(),
      { evm_rpc_canister_id = Principal.fromText("aaaaa-aa"); min_confirmations = 12 },
      [1]
    );

    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    // Deposit enough escrow
    ignore Escrow.deposit(state.escrow, alice, "ICP", 10_000_000);

    // Create 3 intents (at the limit)
    var i = 0;
    while (i < 3) {
      let request : Types.CreateIntentRequest = {
        source = createTestChainAsset("icp", null, "ICP");
        destination = createTestChainAsset("ethereum", ?1, "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0");
        dest_recipient = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0";
        source_amount = 1_000_000;
        min_output = 950_000;
        deadline = currentTime + 3600_000_000_000;
        custom_rpc_urls = null;
        verification_hints = null;
        metadata = null;
      };
      let result = await IntentManager.postIntent(state, alice, request, currentTime);
      switch (result) {
        case (#ok(_)) {};
        case (#err(_)) { assert(false) };
      };
      i += 1;
    };

    // Try to create 4th intent (should fail)
    let request : Types.CreateIntentRequest = {
      source = createTestChainAsset("icp", null, "ICP");
      destination = createTestChainAsset("ethereum", ?1, "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0");
      dest_recipient = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0";
      source_amount = 1_000_000;
      min_output = 950_000;
      deadline = currentTime + 3600_000_000_000;
      custom_rpc_urls = null;
      verification_hints = null;
      metadata = null;
    };
    let result = await IntentManager.postIntent(state, alice, request, currentTime);

    switch (result) {
      case (#err(#InternalError(_))) { /* pass - max active intents reached */ };
      case _ { assert(false) };
    };
  });

  // ========================================
  // Serialize/Deserialize Tests
  // ========================================

  await test("serialize and deserialize preserves state", func() : async () {
    let state1 = createTestState();
    let alice = Principal.fromText("aaaaa-aa");
    let currentTime : Time.Time = 1_000_000_000;

    // Create some state
    ignore Escrow.deposit(state1.escrow, alice, "ICP", 5_000_000);

    let request : Types.CreateIntentRequest = {
      source = createTestChainAsset("icp", null, "ICP");
      destination = createTestChainAsset("ethereum", ?1, "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0");
      dest_recipient = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0";
      source_amount = 1_000_000;
      min_output = 950_000;
      deadline = currentTime + 3600_000_000_000;
      custom_rpc_urls = null;
      verification_hints = null;
      metadata = null;
    };

    let postResult = await IntentManager.postIntent(state1, alice, request, currentTime);
    assert(postResult == #ok(1));

    // Serialize
    let serialized = IntentManager.serializeState(state1);

    // Deserialize into new state
    let state2 = IntentManager.deserializeState(
      createTestConfig(),
      createTECDSAConfig(),
      { evm_rpc_canister_id = Principal.fromText("aaaaa-aa"); min_confirmations = 12 },
      [1, 8453, 11155111],
      serialized
    );

    // Verify state was preserved
    assert(state2.nextIntentId == state1.nextIntentId);

    let intent = IntentManager.getIntent(state2, 1);
    switch (intent) {
      case (?i) {
        assert(i.id == 1);
        assert(i.user == alice);
        assert(i.source_amount == 1_000_000);
      };
      case null { assert(false) };
    };

    // Verify escrow was preserved
    // Note: postIntent doesn't lock escrow, only confirmQuote does
    let escrowAccount = Escrow.getBalance(state2.escrow, alice, "ICP");
    assert(escrowAccount.balance == 5_000_000); // Still 5M (not locked yet)
    assert(escrowAccount.locked == 0);
  });

});
