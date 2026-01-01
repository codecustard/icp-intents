/// Replica tests for IntentManager async functionality
/// Tests async functions like cancelIntent that require an async context
/// Run with: mops test

import {test; suite} "mo:test/async";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import IntentManager "../../src/icp-intents-lib/managers/IntentManager";
import Types "../../src/icp-intents-lib/core/Types";
import ChainRegistry "../../src/icp-intents-lib/chains/ChainRegistry";

persistent actor {

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
        case (#Hoosat(_)) {
          ChainRegistry.registerChain(state.chain_registry, "hoosat", chain);
        };
        case (#Bitcoin(_)) {
          ChainRegistry.registerChain(state.chain_registry, "bitcoin", chain);
        };
        case (#Custom(custom)) {
          ChainRegistry.registerChain(state.chain_registry, custom.name, chain);
        };
      };
    };

    // Also register ICP as source chain
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

  public func runTests() : async () {

    await suite("IntentManager - cancelIntent", func() : async () {

      await test("cancelIntent successfully cancels pending intent", func() : async () {
        let state = createTestState();
        let alice = Principal.fromText("aaaaa-aa");
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

        // Cancel it (note: parameter order is state, intent_id, user, current_time)
        let result = await IntentManager.cancelIntent(state, intentId, alice, currentTime);

        switch (result) {
          case (#ok(_)) {
            // Verify status changed
            let intent = IntentManager.getIntent(state, intentId);
            switch (intent) {
              case (?i) { assert(i.status == #Cancelled) };
              case null { assert(false) };
            };
          };
          case (#err(_)) { assert(false) };
        };
      });

      await test("cancelIntent rejects non-existent intent", func() : async () {
        let state = createTestState();
        let alice = Principal.fromText("aaaaa-aa");
        let currentTime : Time.Time = 1_000_000_000;

        let result = await IntentManager.cancelIntent(state, 999, alice, currentTime);

        switch (result) {
          case (#err(#NotFound)) {}; // Expected
          case _ { assert(false) };
        };
      });

      await test("cancelIntent rejects if caller is not creator", func() : async () {
        let state = createTestState();
        let alice = Principal.fromText("aaaaa-aa");
        let bob = Principal.fromText("2vxsx-fae");
        let currentTime : Time.Time = 1_000_000_000;

        let source = createChainSpec("icp", null, "ICP");
        let destination = createChainSpec("ethereum", ?1, "ETH");

        // Alice creates intent
        let intentId = switch (IntentManager.createIntent(
          state, alice, source, destination,
          100_000, 90_000,
          "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
          currentTime + 3600_000_000_000, currentTime
        )) {
          case (#ok(id)) id;
          case (#err(_)) { assert(false); 0 };
        };

        // Bob tries to cancel (should fail)
        let result = await IntentManager.cancelIntent(state, intentId, bob, currentTime);

        switch (result) {
          case (#err(#NotIntentCreator)) {}; // Expected
          case _ { assert(false) };
        };
      });

      await test("intent transitions to Cancelled when cancelled", func() : async () {
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

        // Verify initial state
        let intent1 = IntentManager.getIntent(state, intentId);
        switch (intent1) {
          case (?i) { assert(i.status == #PendingQuote) };
          case null { assert(false) };
        };

        // Cancel
        ignore await IntentManager.cancelIntent(state, intentId, alice, currentTime);

        // Verify final state
        let intent2 = IntentManager.getIntent(state, intentId);
        switch (intent2) {
          case (?i) { assert(i.status == #Cancelled) };
          case null { assert(false) };
        };
      });

    });

    await suite("IntentManager - confirmQuote", func() : async () {

      await test("confirmQuote successfully confirms quote", func() : async () {
        let state = createTestState();
        let alice = Principal.fromText("aaaaa-aa");
        let solver = Principal.fromText("2vxsx-fae");
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

        // Submit quote
        ignore IntentManager.submitQuote(
          state, intentId, solver,
          95_000, 4_000, 1_000, null, currentTime
        );

        // Confirm quote
        let result = IntentManager.confirmQuote(state, intentId, solver, alice, currentTime);

        switch (result) {
          case (#ok(_)) {
            // Verify status changed to Confirmed
            let intent = IntentManager.getIntent(state, intentId);
            switch (intent) {
              case (?i) {
                assert(i.status == #Confirmed);
                // Verify quote was selected
                switch (i.selected_quote) {
                  case (?q) {
                    assert(q.solver == solver);
                    assert(q.output_amount == 95_000);
                  };
                  case null { assert(false) };
                };
              };
              case null { assert(false) };
            };
          };
          case (#err(_)) { assert(false) };
        };
      });

      await test("confirmQuote rejects non-existent intent", func() : async () {
        let state = createTestState();
        let alice = Principal.fromText("aaaaa-aa");
        let solver = Principal.fromText("2vxsx-fae");
        let currentTime : Time.Time = 1_000_000_000;

        let result = IntentManager.confirmQuote(state, 999, solver, alice, currentTime);

        switch (result) {
          case (#err(#NotFound)) {}; // Expected
          case _ { assert(false) };
        };
      });

      await test("confirmQuote rejects if caller is not creator", func() : async () {
        let state = createTestState();
        let alice = Principal.fromText("aaaaa-aa");
        let bob = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
        let solver = Principal.fromText("2vxsx-fae");
        let currentTime : Time.Time = 1_000_000_000;

        let source = createChainSpec("icp", null, "ICP");
        let destination = createChainSpec("ethereum", ?1, "ETH");

        // Alice creates intent
        let intentId = switch (IntentManager.createIntent(
          state, alice, source, destination,
          100_000, 90_000,
          "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
          currentTime + 3600_000_000_000, currentTime
        )) {
          case (#ok(id)) id;
          case (#err(_)) { assert(false); 0 };
        };

        // Submit quote
        ignore IntentManager.submitQuote(
          state, intentId, solver,
          95_000, 4_000, 1_000, null, currentTime
        );

        // Bob tries to confirm (should fail)
        let result = IntentManager.confirmQuote(state, intentId, solver, bob, currentTime);

        switch (result) {
          case (#err(#NotIntentCreator)) {}; // Expected
          case _ { assert(false) };
        };
      });

      await test("confirmQuote rejects if solver has no quote", func() : async () {
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

        // Only solver1 submits quote
        ignore IntentManager.submitQuote(
          state, intentId, solver1,
          95_000, 4_000, 1_000, null, currentTime
        );

        // Try to confirm solver2 who didn't submit quote
        let result = IntentManager.confirmQuote(state, intentId, solver2, alice, currentTime);

        switch (result) {
          case (#err(#NotFound)) {}; // Expected - quote not found
          case _ { assert(false) };
        };
      });

      await test("confirmQuote rejects expired intent", func() : async () {
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
          currentTime + 1000, currentTime
        )) {
          case (#ok(id)) id;
          case (#err(_)) { assert(false); 0 };
        };

        // Submit quote
        ignore IntentManager.submitQuote(
          state, intentId, solver,
          95_000, 4_000, 1_000, null, currentTime
        );

        // Try to confirm after expiry
        let laterTime = currentTime + 2000;
        let result = IntentManager.confirmQuote(state, intentId, solver, alice, laterTime);

        switch (result) {
          case (#err(#Expired)) {}; // Expected
          case _ { assert(false) };
        };
      });

    });

    await suite("IntentManager - markDeposited", func() : async () {

      await test("markDeposited successfully marks intent as deposited", func() : async () {
        let state = createTestState();
        let alice = Principal.fromText("aaaaa-aa");
        let solver = Principal.fromText("2vxsx-fae");
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

        // Submit and confirm quote
        ignore IntentManager.submitQuote(
          state, intentId, solver,
          95_000, 4_000, 1_000, null, currentTime
        );
        ignore IntentManager.confirmQuote(state, intentId, solver, alice, currentTime);

        // Mark as deposited
        let result = IntentManager.markDeposited(state, intentId, 100_000, currentTime);

        switch (result) {
          case (#ok(_)) {
            // Verify status changed to Deposited
            let intent = IntentManager.getIntent(state, intentId);
            switch (intent) {
              case (?i) {
                assert(i.status == #Deposited);
                assert(i.escrow_balance == 100_000);
                switch (i.verified_at) {
                  case (?_) {}; // Should have verified timestamp
                  case null { assert(false) };
                };
              };
              case null { assert(false) };
            };
          };
          case (#err(_)) { assert(false) };
        };
      });

      await test("markDeposited rejects non-existent intent", func() : async () {
        let state = createTestState();
        let currentTime : Time.Time = 1_000_000_000;

        let result = IntentManager.markDeposited(state, 999, 100_000, currentTime);

        switch (result) {
          case (#err(#NotFound)) {}; // Expected
          case _ { assert(false) };
        };
      });

      await test("markDeposited rejects if not in Confirmed state", func() : async () {
        let state = createTestState();
        let alice = Principal.fromText("aaaaa-aa");
        let currentTime : Time.Time = 1_000_000_000;

        let source = createChainSpec("icp", null, "ICP");
        let destination = createChainSpec("ethereum", ?1, "ETH");

        // Create intent (PendingQuote state)
        let intentId = switch (IntentManager.createIntent(
          state, alice, source, destination,
          100_000, 90_000,
          "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
          currentTime + 3600_000_000_000, currentTime
        )) {
          case (#ok(id)) id;
          case (#err(_)) { assert(false); 0 };
        };

        // Try to mark as deposited without confirming quote first
        let result = IntentManager.markDeposited(state, intentId, 100_000, currentTime);

        switch (result) {
          case (#err(#InvalidStatus(_))) {}; // Expected
          case _ { assert(false) };
        };
      });

    });

    await suite("IntentManager - fulfillIntent", func() : async () {

      // NOTE: fulfillIntent requires token ledgers to be registered and available
      // In test environment, these external calls will fail with #InvalidToken
      // Full fulfillment testing requires integration tests with real ledger canisters

      await test("fulfillIntent fails without token registry setup", func() : async () {
        let state = createTestState();
        let alice = Principal.fromText("aaaaa-aa");
        let solver = Principal.fromText("2vxsx-fae");
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

        // Submit and confirm quote
        ignore IntentManager.submitQuote(
          state, intentId, solver,
          95_000, 4_000, 1_000, null, currentTime
        );
        ignore IntentManager.confirmQuote(state, intentId, solver, alice, currentTime);

        // Mark as deposited
        ignore IntentManager.markDeposited(state, intentId, 100_000, currentTime);

        // Try to fulfill - will fail because token ledgers not registered
        let result = await IntentManager.fulfillIntent(state, intentId, currentTime);

        switch (result) {
          case (#err(#InvalidToken(_))) {}; // Expected - no ledger registered
          case _ { assert(false) }; // Any other result is unexpected
        };
      });

      await test("fulfillIntent rejects non-existent intent", func() : async () {
        let state = createTestState();
        let currentTime : Time.Time = 1_000_000_000;

        let result = await IntentManager.fulfillIntent(state, 999, currentTime);

        switch (result) {
          case (#err(#NotFound)) {}; // Expected
          case _ { assert(false) };
        };
      });

      await test("fulfillIntent rejects if not in Deposited state", func() : async () {
        let state = createTestState();
        let alice = Principal.fromText("aaaaa-aa");
        let solver = Principal.fromText("2vxsx-fae");
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

        // Submit and confirm quote but don't mark as deposited
        ignore IntentManager.submitQuote(
          state, intentId, solver,
          95_000, 4_000, 1_000, null, currentTime
        );
        ignore IntentManager.confirmQuote(state, intentId, solver, alice, currentTime);

        // Try to fulfill without deposit
        let result = await IntentManager.fulfillIntent(state, intentId, currentTime);

        switch (result) {
          case (#err(#InvalidStatus(_))) {}; // Expected
          case _ { assert(false) };
        };
      });

    });

    await suite("IntentManager - Full Lifecycle", func() : async () {

      await test("complete intent lifecycle: create → quote → confirm → deposit → fulfill", func() : async () {
        let state = createTestState();
        let alice = Principal.fromText("aaaaa-aa");
        let solver1 = Principal.fromText("2vxsx-fae");
        let solver2 = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
        let currentTime : Time.Time = 1_000_000_000;

        let source = createChainSpec("icp", null, "ICP");
        let destination = createChainSpec("ethereum", ?1, "ETH");

        // Step 1: Create intent
        let intentId = switch (IntentManager.createIntent(
          state, alice, source, destination,
          100_000, 90_000,
          "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0",
          currentTime + 3600_000_000_000, currentTime
        )) {
          case (#ok(id)) id;
          case (#err(_)) { assert(false); 0 };
        };

        // Verify initial state
        let intent1 = IntentManager.getIntent(state, intentId);
        switch (intent1) {
          case (?i) { assert(i.status == #PendingQuote) };
          case null { assert(false) };
        };

        // Step 2: Multiple solvers submit quotes
        ignore IntentManager.submitQuote(
          state, intentId, solver1,
          95_000, 4_000, 1_000, null, currentTime
        );
        ignore IntentManager.submitQuote(
          state, intentId, solver2,
          96_000, 3_000, 1_000, null, currentTime
        );

        // Verify Quoted state
        let intent2 = IntentManager.getIntent(state, intentId);
        switch (intent2) {
          case (?i) {
            assert(i.status == #Quoted);
            assert(i.quotes.size() == 2);
          };
          case null { assert(false) };
        };

        // Step 3: User confirms best quote (solver2)
        ignore IntentManager.confirmQuote(state, intentId, solver2, alice, currentTime);

        // Verify Confirmed state
        let intent3 = IntentManager.getIntent(state, intentId);
        switch (intent3) {
          case (?i) {
            assert(i.status == #Confirmed);
            switch (i.selected_quote) {
              case (?q) { assert(q.solver == solver2) };
              case null { assert(false) };
            };
          };
          case null { assert(false) };
        };

        // Step 4: Deposit verified
        ignore IntentManager.markDeposited(state, intentId, 100_000, currentTime);

        // Verify Deposited state
        let intent4 = IntentManager.getIntent(state, intentId);
        switch (intent4) {
          case (?i) {
            assert(i.status == #Deposited);
            assert(i.escrow_balance == 100_000);
          };
          case null { assert(false) };
        };

        // Step 5: Attempt to fulfill intent
        // NOTE: This will fail because token ledgers aren't registered
        // In a real environment with registered ledgers, this would succeed
        let feeResult = await IntentManager.fulfillIntent(state, intentId, currentTime);

        switch (feeResult) {
          case (#err(#InvalidToken(_))) {
            // Expected in test environment - tokens not registered
            // Lifecycle successfully reached Deposited state
            // (Fulfillment requires actual token transfers to external ledgers)
            assert(true);
          };
          case (#ok(_)) {
            // Would succeed if token ledgers were registered
            assert(false); // Not expected in test environment
          };
          case (#err(_)) { assert(false) }; // Other errors unexpected
        };
      });

    });

  };
};
