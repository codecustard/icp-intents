/// Unit tests for Escrow module
/// Tests lock, release, and balance tracking operations

import {test; suite} "mo:test";
import Escrow "../src/icp-intents-lib/managers/Escrow";
import Principal "mo:base/Principal";

suite("Escrow", func() {

  test("locks funds correctly", func() {
    let state = Escrow.init();
    let user = Principal.fromText("aaaaa-aa");
    let token = "ICP";

    // Initial balance should be 0
    let balance1 = Escrow.getBalance(state, user, token);
    assert(balance1 == 0);

    // Lock 1M tokens
    let result = Escrow.lock(state, user, token, 1000000);
    switch (result) {
      case (#ok(_)) {};
      case (#err(_)) { assert(false) }; // Should not fail
    };

    // Check balance
    let balance2 = Escrow.getBalance(state, user, token);
    assert(balance2 == 1000000);

    // Lock more
    ignore Escrow.lock(state, user, token, 500000);
    let balance3 = Escrow.getBalance(state, user, token);
    assert(balance3 == 1500000);

    // Check total locked
    let totalLocked = Escrow.getTotalLocked(state, token);
    assert(totalLocked == 1500000);
  });

  test("releases locked funds correctly", func() {
    let state = Escrow.init();
    let user = Principal.fromText("aaaaa-aa");
    let token = "ICP";

    // Lock funds
    ignore Escrow.lock(state, user, token, 1000000);

    // Release 300k
    let releaseResult = Escrow.release(state, user, token, 300000);
    switch (releaseResult) {
      case (#ok(_)) {};
      case (#err(_)) { assert(false) }; // Should not fail
    };

    let balance = Escrow.getBalance(state, user, token);
    assert(balance == 700000); // 1M - 300k

    let totalLocked = Escrow.getTotalLocked(state, token);
    assert(totalLocked == 700000);
  });

  test("rejects release with insufficient balance", func() {
    let state = Escrow.init();
    let user = Principal.fromText("aaaaa-aa");
    let token = "ICP";

    ignore Escrow.lock(state, user, token, 1000);

    // Try to release more than locked
    let releaseResult = Escrow.release(state, user, token, 2000);
    switch (releaseResult) {
      case (#ok(_)) { assert(false) }; // Should fail
      case (#err(#InsufficientBalance)) {};
      case (#err(_)) { assert(false) }; // Wrong error type
    };
  });

  test("handles multiple tokens independently", func() {
    let state = Escrow.init();
    let user = Principal.fromText("aaaaa-aa");

    // Lock different tokens
    ignore Escrow.lock(state, user, "ICP", 1000000);
    ignore Escrow.lock(state, user, "ryjl3-tyaaa-aaaaa-aaaba-cai", 500000);

    let icpBalance = Escrow.getBalance(state, user, "ICP");
    let tokenBalance = Escrow.getBalance(state, user, "ryjl3-tyaaa-aaaaa-aaaba-cai");

    assert(icpBalance == 1000000);
    assert(tokenBalance == 500000);

    // Releasing one token doesn't affect the other
    ignore Escrow.release(state, user, "ICP", 500000);

    let icpBalance2 = Escrow.getBalance(state, user, "ICP");
    assert(icpBalance2 == 500000);

    let tokenBalance2 = Escrow.getBalance(state, user, "ryjl3-tyaaa-aaaaa-aaaba-cai");
    assert(tokenBalance2 == 500000);
  });

  test("handles multiple users independently", func() {
    let state = Escrow.init();
    let alice = Principal.fromText("aaaaa-aa");
    let bob = Principal.fromText("2vxsx-fae");
    let token = "ICP";

    // Lock for both users
    ignore Escrow.lock(state, alice, token, 1000000);
    ignore Escrow.lock(state, bob, token, 2000000);

    let aliceBalance = Escrow.getBalance(state, alice, token);
    let bobBalance = Escrow.getBalance(state, bob, token);

    assert(aliceBalance == 1000000);
    assert(bobBalance == 2000000);

    // Total locked should be sum of both
    let totalLocked = Escrow.getTotalLocked(state, token);
    assert(totalLocked == 3000000);
  });

  test("rejects locking zero amount", func() {
    let state = Escrow.init();
    let user = Principal.fromText("aaaaa-aa");
    let token = "ICP";

    let result = Escrow.lock(state, user, token, 0);
    switch (result) {
      case (#ok(_)) { assert(false) }; // Should fail
      case (#err(#InvalidAmount(_))) {};
      case (#err(_)) { assert(false) }; // Wrong error type
    };
  });

  test("verifies invariants correctly", func() {
    let state = Escrow.init();
    let alice = Principal.fromText("aaaaa-aa");
    let bob = Principal.fromText("2vxsx-fae");
    let token = "ICP";

    // Lock for both users
    ignore Escrow.lock(state, alice, token, 1000000);
    ignore Escrow.lock(state, bob, token, 2000000);

    // Invariants should be valid
    assert(Escrow.verifyInvariants(state));

    // After release
    ignore Escrow.release(state, alice, token, 500000);
    assert(Escrow.verifyInvariants(state));
  });

  test("stable storage preserves state", func() {
    let state1 = Escrow.init();
    let user = Principal.fromText("aaaaa-aa");

    // Lock some funds
    ignore Escrow.lock(state1, user, "ICP", 1000000);
    ignore Escrow.lock(state1, user, "ckBTC", 500000);

    // Convert to stable
    let stableData = Escrow.toStable(state1);

    // Restore from stable
    let state2 = Escrow.fromStable(stableData);

    // Verify state preserved
    let icpBalance = Escrow.getBalance(state2, user, "ICP");
    let btcBalance = Escrow.getBalance(state2, user, "ckBTC");

    assert(icpBalance == 1000000);
    assert(btcBalance == 500000);
    assert(Escrow.verifyInvariants(state2));
  });

});
