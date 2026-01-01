/// Integration tests for chain verification with real transactions
///
/// HOW TO USE:
/// Run: mops test Verification.replica
///
/// See test/VERIFICATION_TESTING.md for detailed instructions

import {test} "mo:test/async";
import Hoosat "../src/icp-intents-lib/chains/Hoosat";
import EVM "../src/icp-intents-lib/chains/EVM";
import ChainTypes "../src/icp-intents-lib/chains/ChainTypes";
import Debug "mo:base/Debug";
import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";

persistent actor {
  // Hoosat transaction data (replace with your own)
  let HOOSAT_RPC = "https://api.network.hoosat.fi";
  let HOOSAT_TX_ID = "YOUR_HOOSAT_TX_ID_HERE";
  let HOOSAT_ADDRESS = "hoosat:YOUR_HOOSAT_ADDRESS_HERE";
  let HOOSAT_AMOUNT = 10000000000; // Amount in sompi

  // EVM transaction data (Sepolia testnet - replace with your own)
  // Find a transaction at https://sepolia.etherscan.io
  let EVM_CHAIN_ID = 11155111; // Sepolia testnet
  let EVM_TX_HASH = "0xYOUR_EVM_TX_HASH_HERE";
  let EVM_TO_ADDRESS = "0xYOUR_EVM_ADDRESS_HERE"; // Lowercase
  let EVM_VALUE = 1000000000000000; // Amount in wei

  // Manual EVM RPC actor interface (subset of methods we need)
  type EvmRpcActor = actor {
    updateApiKeys : ([(Nat64, ?Text)]) -> async ();
  };

  // Deploy EVM RPC canister with initial cycles
  Debug.print("Deploying EVM RPC canister...");
  Cycles.add<system>(10_000_000_000_000); // 10T cycles for deployment

  // Create EVM RPC canister - mops will auto-deploy dependencies
  let evmRpc : EvmRpcActor = actor("aaaaa-aa"); // Will be replaced with actual canister ID

  // Configure EVM RPC canister with Alchemy API key
  var evmRpcConfigured = false;
  var EVM_RPC_CANISTER = "";

  public func runTests() : async () {

    // One-time setup: Deploy and configure EVM RPC
    if (not evmRpcConfigured) {
      Debug.print("Configuring EVM RPC with Alchemy API key...");

      // Note: In mops test, the evm_rpc canister should be auto-deployed
      // We just need to find its principal and configure it
      try {
        // Replace YOUR_ALCHEMY_API_KEY with your actual Alchemy API key
        await evmRpc.updateApiKeys([(9 : Nat64, ?"YOUR_ALCHEMY_API_KEY")]);
        EVM_RPC_CANISTER := Principal.toText(Principal.fromActor(evmRpc));
        evmRpcConfigured := true;
        Debug.print("✓ EVM RPC configured at: " # EVM_RPC_CANISTER);
      } catch (e) {
        Debug.print("⚠ EVM RPC configuration failed (will skip EVM tests)");
        EVM_RPC_CANISTER := "aaaaa-aa"; // Dummy value
      };
    };


    await test("verify confirmed Hoosat transaction", func() : async () {
      let config : Hoosat.Config = {
        rpc_url = HOOSAT_RPC;
        min_confirmations = 1;
        ecdsa_key_name = "test_key_1";
      };

      let request : ChainTypes.VerificationRequest = {
        chain = #Hoosat({
          network = "mainnet";
          rpc_url = HOOSAT_RPC;
          min_confirmations = 1;
        });
        proof = #UTXO({
          tx_id = HOOSAT_TX_ID;
          output_index = 0;
          amount = 0;
          script_pubkey = Blob.fromArray([]);
          address = "";
          confirmations = 0;
        });
        expected_address = HOOSAT_ADDRESS;
        expected_amount = HOOSAT_AMOUNT;
        custom_rpc_urls = null;
      };

      let result = await Hoosat.verify(config, request);

      Debug.print("Hoosat verification: " # debug_show(result));

      switch (result) {
        case (#Success(data)) {
          Debug.print("✓ Verified with " # debug_show(data.confirmations) # " confirmations");
          assert data.confirmations >= 1;
        };
        case (#Pending(data)) {
          Debug.print("⚠ Pending: " # debug_show(data.current_confirmations) # "/" # debug_show(data.required_confirmations));
          // Accept pending as valid (tx might be very recent)
        };
        case (#Failed(msg)) {
          Debug.print("✗ Failed: " # msg);
          assert false;
        };
      };
    });

    await test("verify with high confirmation requirement returns Pending", func() : async () {
      let config : Hoosat.Config = {
        rpc_url = HOOSAT_RPC;
        min_confirmations = 999999; // Impossibly high
        ecdsa_key_name = "test_key_1";
      };

      let request : ChainTypes.VerificationRequest = {
        chain = #Hoosat({
          network = "mainnet";
          rpc_url = HOOSAT_RPC;
          min_confirmations = 999999;
        });
        proof = #UTXO({
          tx_id = HOOSAT_TX_ID;
          output_index = 0;
          amount = 0;
          script_pubkey = Blob.fromArray([]);
          address = "";
          confirmations = 0;
        });
        expected_address = HOOSAT_ADDRESS;
        expected_amount = HOOSAT_AMOUNT;
        custom_rpc_urls = null;
      };

      let result = await Hoosat.verify(config, request);

      Debug.print("High confirmation test: " # debug_show(result));

      switch (result) {
        case (#Success(_)) {
          Debug.print("✗ Should not succeed with impossible confirmation requirement");
          assert false;
        };
        case (#Pending(data)) {
          Debug.print("✓ Correctly returned Pending");
          assert data.current_confirmations < data.required_confirmations;
          assert data.required_confirmations == 999999;
        };
        case (#Failed(msg)) {
          Debug.print("✗ Unexpected failure: " # msg);
          assert false;
        };
      };
    });

    await test("verify confirmed EVM transaction", func() : async () {
      let config : EVM.Config = {
        evm_rpc_canister = Principal.fromText(EVM_RPC_CANISTER);
        min_confirmations = 1;
        ecdsa_key_name = "test_key_1";
      };

      let request : ChainTypes.VerificationRequest = {
        chain = #EVM({
          chain_id = EVM_CHAIN_ID;
          name = "sepolia";
          network = "testnet";
          rpc_urls = null;
        });
        proof = #EVM({
          tx_hash = EVM_TX_HASH;
          block_number = 0; // Will be fetched by verify()
          from_address = ""; // Will be fetched by verify()
          to_address = ""; // Will be fetched by verify()
          value = 0; // Will be fetched by verify()
          confirmations = 0; // Will be calculated by verify()
        });
        expected_address = EVM_TO_ADDRESS;
        expected_amount = EVM_VALUE;
        custom_rpc_urls = null;
      };

      let result = await EVM.verify(config, request);

      Debug.print("EVM verification: " # debug_show(result));

      switch (result) {
        case (#Success(data)) {
          Debug.print("✓ Verified with " # debug_show(data.confirmations) # " confirmations");
          assert data.confirmations >= 1;
        };
        case (#Pending(data)) {
          Debug.print("⚠ Pending: " # debug_show(data.current_confirmations) # "/" # debug_show(data.required_confirmations));
        };
        case (#Failed(msg)) {
          Debug.print("✗ Failed: " # msg);
          assert false;
        };
      };
    });

    await test("verify EVM with high confirmation requirement returns Pending", func() : async () {
      let config : EVM.Config = {
        evm_rpc_canister = Principal.fromText(EVM_RPC_CANISTER);
        min_confirmations = 999999; // Impossibly high
        ecdsa_key_name = "test_key_1";
      };

      let request : ChainTypes.VerificationRequest = {
        chain = #EVM({
          chain_id = EVM_CHAIN_ID;
          name = "sepolia";
          network = "testnet";
          rpc_urls = null;
        });
        proof = #EVM({
          tx_hash = EVM_TX_HASH;
          block_number = 0; // Will be fetched by verify()
          from_address = ""; // Will be fetched by verify()
          to_address = ""; // Will be fetched by verify()
          value = 0; // Will be fetched by verify()
          confirmations = 0; // Will be calculated by verify()
        });
        expected_address = EVM_TO_ADDRESS;
        expected_amount = EVM_VALUE;
        custom_rpc_urls = null;
      };

      let result = await EVM.verify(config, request);

      Debug.print("EVM high confirmation test: " # debug_show(result));

      switch (result) {
        case (#Success(_)) {
          Debug.print("✗ Should not succeed with impossible confirmation requirement");
          assert false;
        };
        case (#Pending(data)) {
          Debug.print("✓ Correctly returned Pending");
          assert data.current_confirmations < data.required_confirmations;
          assert data.required_confirmations == 999999;
        };
        case (#Failed(msg)) {
          Debug.print("✗ Unexpected failure: " # msg);
          assert false;
        };
      };
    });

  };
};
