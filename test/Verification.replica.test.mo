/// Integration tests for chain verification with real transactions
/// Run with: mops test

import {test} "mo:test/async";
import Hoosat "../src/icp-intents-lib/chains/Hoosat";
import ChainTypes "../src/icp-intents-lib/chains/ChainTypes";
import Debug "mo:base/Debug";
import Blob "mo:base/Blob";

persistent actor {
  // Real Hoosat transaction data - replace with your own test transaction
  let HOOSAT_RPC = "https://api.network.hoosat.fi";
  let HOOSAT_TX_ID = "YOUR_TX_ID_HERE"; // Get from Hoosat explorer
  let HOOSAT_ADDRESS = "hoosat:qq..."; // Recipient address from transaction
  let HOOSAT_AMOUNT = 100000000; // Expected amount in sompi

  public func runTests() : async () {

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

  };
};
