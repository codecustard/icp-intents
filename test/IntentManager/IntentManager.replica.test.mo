/// Replica tests for IntentManager confirmQuote functionality
/// Tests the full flow including tECDSA address generation
/// Run with: mops test

import {test; suite} "mo:test/async";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import IntentManager "../../src/icp-intents-lib/IntentManager";
import Types "../../src/icp-intents-lib/Types";
import Escrow "../../src/icp-intents-lib/Escrow";

persistent actor {

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
      key_name = "test_key_1"; // Local replica uses test_key_1
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

  public func runTests() : async () {

    await suite("IntentManager - confirmQuote", func() : async () {

      await test("confirmQuote successfully locks escrow and generates deposit address", func() : async () {
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
        ignore IntentManager.submitQuote(state, solver, quoteRequest, currentTime);

        // Confirm quote (calls tECDSA)
        let confirmResult = await IntentManager.confirmQuote(state, alice, intentId, 0, currentTime);

        switch (confirmResult) {
          case (#ok(depositAddress)) {
            // Verify deposit address was generated
            assert(depositAddress.size() == 42); // 0x + 40 hex chars

            let chars = depositAddress.chars();
            let c1 = switch (chars.next()) { case (?c) c; case null ' ' };
            let c2 = switch (chars.next()) { case (?c) c; case null ' ' };
            assert(c1 == '0');
            assert(c2 == 'x');

            // Verify intent status changed to Locked
            let intent = IntentManager.getIntent(state, intentId);
            switch (intent) {
              case (?i) {
                assert(i.status == #Locked);
                switch (i.selected_quote) {
                  case (?quote) {
                    assert(quote.solver == solver);
                    assert(quote.output_amount == 960_000);
                  };
                  case null { assert(false) };
                };

                // Verify deposit address stored in intent
                switch (i.generated_address) {
                  case (?addr) {
                    assert(addr == depositAddress);
                  };
                  case null { assert(false) };
                };
              };
              case null { assert(false) };
            };

            // Verify escrow was locked (source_amount + fee)
            let escrowAccount = Escrow.getBalance(state.escrow, alice, "ICP");
            assert(escrowAccount.locked == 1_040_000); // 1M source + 40k fee
            assert(escrowAccount.available == 960_000); // 2M - 1.04M locked
          };
          case (#err(_)) { assert(false) };
        };
      });

      await test("confirmQuote generates different addresses for different intents", func() : async () {
        let state = createTestState();
        let alice = Principal.fromText("aaaaa-aa");
        let solver = Principal.fromText("2vxsx-fae");
        let currentTime : Time.Time = 1_000_000_000;

        // Deposit escrow
        ignore Escrow.deposit(state.escrow, alice, "ICP", 10_000_000);

        // Create and confirm first intent
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

        let postResult1 = await IntentManager.postIntent(state, alice, request, currentTime);
        let intentId1 = switch (postResult1) {
          case (#ok(id)) id;
          case (#err(_)) { assert(false); 0 };
        };

        let quoteRequest1 : Types.SubmitQuoteRequest = {
          intent_id = intentId1;
          output_amount = 960_000;
          fee = 40_000;
          expiry = currentTime + 1800_000_000_000;
        };
        ignore IntentManager.submitQuote(state, solver, quoteRequest1, currentTime);

        let confirmResult1 = await IntentManager.confirmQuote(state, alice, intentId1, 0, currentTime);
        let address1 = switch (confirmResult1) {
          case (#ok(addr)) addr;
          case (#err(_)) { assert(false); "" };
        };

        // Create and confirm second intent
        let postResult2 = await IntentManager.postIntent(state, alice, request, currentTime);
        let intentId2 = switch (postResult2) {
          case (#ok(id)) id;
          case (#err(_)) { assert(false); 0 };
        };

        let quoteRequest2 : Types.SubmitQuoteRequest = {
          intent_id = intentId2;
          output_amount = 960_000;
          fee = 40_000;
          expiry = currentTime + 1800_000_000_000;
        };
        ignore IntentManager.submitQuote(state, solver, quoteRequest2, currentTime);

        let confirmResult2 = await IntentManager.confirmQuote(state, alice, intentId2, 0, currentTime);
        let address2 = switch (confirmResult2) {
          case (#ok(addr)) addr;
          case (#err(_)) { assert(false); "" };
        };

        // Verify addresses are different (derived with different intent IDs)
        assert(address1 != address2);
      });

      await test("confirmQuote rejects if caller is not creator", func() : async () {
        let state = createTestState();
        let alice = Principal.fromText("aaaaa-aa");
        let bob = Principal.fromText("2vxsx-fae");
        let currentTime : Time.Time = 1_000_000_000;

        // Alice creates intent
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

        // Solver submits quote
        let quoteRequest : Types.SubmitQuoteRequest = {
          intent_id = intentId;
          output_amount = 960_000;
          fee = 40_000;
          expiry = currentTime + 1800_000_000_000;
        };
        ignore IntentManager.submitQuote(state, bob, quoteRequest, currentTime);

        // Bob tries to confirm (should fail - only Alice can)
        let confirmResult = await IntentManager.confirmQuote(state, bob, intentId, 0, currentTime);

        switch (confirmResult) {
          case (#err(#Unauthorized)) { /* pass */ };
          case _ { assert(false) };
        };
      });

      await test("confirmQuote rejects invalid quote index", func() : async () {
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

        // Try to confirm quote that doesn't exist (no quotes submitted)
        let confirmResult = await IntentManager.confirmQuote(state, alice, intentId, 0, currentTime);

        switch (confirmResult) {
          case (#err(#NotFound)) { /* pass */ };
          case _ { assert(false) };
        };
      });

    });

  };
};
