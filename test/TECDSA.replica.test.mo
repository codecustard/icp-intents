/// Replica tests for tECDSA address generation
/// Tests the TECDSA module in isolation on a local replica
/// Run with: mops test

import {test} "mo:test/async";
import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import TECDSA "../src/icp-intents-lib/TECDSA";

persistent actor {

  public func runTests() : async () {

    await test("generates valid Ethereum address", func() : async () {
      let config : TECDSA.Config = {
        key_name = "test_key_1"; // Local replica uses test_key_1
      };

      let intentId : Nat = 1;
      let user = Principal.fromText("aaaaa-aa");

      // Generate address
      let result = await TECDSA.deriveAddress(config, intentId, user);

      switch (result) {
        case (#ok(address)) {
          // Verify address starts with 0x
          assert(address.size() == 42); // 0x + 40 hex chars

          // Extract prefix
          let prefix = if (address.size() >= 2) {
            let chars = address.chars();
            let c1 = switch (chars.next()) { case (?c) c; case null ' ' };
            let c2 = switch (chars.next()) { case (?c) c; case null ' ' };
            [c1, c2]
          } else {
            ['?', '?']
          };

          assert(prefix[0] == '0');
          assert(prefix[1] == 'x');
        };
        case (#err(e)) {
          // Print error for debugging
          assert(false);
        };
      };
    });

    await test("different intent IDs generate different addresses", func() : async () {
      let config : TECDSA.Config = {
        key_name = "test_key_1";
      };

      let user = Principal.fromText("aaaaa-aa");

      // Generate address for intent 1
      let result1 = await TECDSA.deriveAddress(config, 1, user);
      let address1 = switch (result1) {
        case (#ok(addr)) addr;
        case (#err(_)) { assert(false); "" };
      };

      // Generate address for intent 2
      let result2 = await TECDSA.deriveAddress(config, 2, user);
      let address2 = switch (result2) {
        case (#ok(addr)) addr;
        case (#err(_)) { assert(false); "" };
      };

      // Addresses should be different
      assert(address1 != address2);
    });

    await test("different users generate different addresses", func() : async () {
      let config : TECDSA.Config = {
        key_name = "test_key_1";
      };

      let intentId : Nat = 1;
      let user1 = Principal.fromText("aaaaa-aa");
      let user2 = Principal.fromText("2vxsx-fae");

      // Generate address for user1
      let result1 = await TECDSA.deriveAddress(config, intentId, user1);
      let address1 = switch (result1) {
        case (#ok(addr)) addr;
        case (#err(_)) { assert(false); "" };
      };

      // Generate address for user2
      let result2 = await TECDSA.deriveAddress(config, intentId, user2);
      let address2 = switch (result2) {
        case (#ok(addr)) addr;
        case (#err(_)) { assert(false); "" };
      };

      // Addresses should be different
      assert(address1 != address2);
    });

    await test("same intent and user generate same address (deterministic)", func() : async () {
      let config : TECDSA.Config = {
        key_name = "test_key_1";
      };

      let intentId : Nat = 42;
      let user = Principal.fromText("aaaaa-aa");

      // Generate address twice
      let result1 = await TECDSA.deriveAddress(config, intentId, user);
      let address1 = switch (result1) {
        case (#ok(addr)) addr;
        case (#err(_)) { assert(false); "" };
      };

      let result2 = await TECDSA.deriveAddress(config, intentId, user);
      let address2 = switch (result2) {
        case (#ok(addr)) addr;
        case (#err(_)) { assert(false); "" };
      };

      // Should generate the same address (deterministic derivation)
      assert(address1 == address2);
    });

    // Note: Derivation path is generated internally based on intentId and user
    // The TECDSA module uses getDerivationPath(intentId, user) internally

  };
};
