/// Unit tests for Escrow module
/// Tests deposit, lock, unlock, release, and withdraw operations

import {test; suite} "mo:test";
import Escrow "../src/icp-intents-lib/Escrow";
import Principal "mo:base/Principal";

suite("Escrow", func() {

  test("deposits funds correctly", func() {
    let state = Escrow.init();
    let user = Principal.fromText("aaaaa-aa");
    let token = "ICP";

    // Initial balance should be 0
    let account1 = Escrow.getBalance(state, user, token);
    assert(account1.balance == 0);

    // Deposit 1M tokens
    let result = Escrow.deposit(state, user, token, 1000000);
    switch (result) {
      case (#ok(_)) {};
      case (#err(_)) { assert(false) }; // Should not fail
    };

    // Check balance
    let account2 = Escrow.getBalance(state, user, token);
    assert(account2.balance == 1000000);
    assert(account2.available == 1000000);
    assert(account2.locked == 0);

    // Deposit more
    ignore Escrow.deposit(state, user, token, 500000);
    let account3 = Escrow.getBalance(state, user, token);
    assert(account3.balance == 1500000);
  });

  test("locks and unlocks funds correctly", func() {
    let state = Escrow.init();
    let user = Principal.fromText("aaaaa-aa");
    let token = "ICP";

    // Deposit
    ignore Escrow.deposit(state, user, token, 1000000);

    // Lock 600k
    let lockResult = Escrow.lock(state, user, token, 600000);
    switch (lockResult) {
      case (#ok(_)) {};
      case (#err(_)) { assert(false) }; // Should not fail
    };

    let account1 = Escrow.getBalance(state, user, token);
    assert(account1.balance == 1000000);
    assert(account1.locked == 600000);
    assert(account1.available == 400000);

    // Unlock 200k
    ignore Escrow.unlock(state, user, token, 200000);
    let account2 = Escrow.getBalance(state, user, token);
    assert(account2.locked == 400000);
    assert(account2.available == 600000);
  });

  test("releases locked funds correctly", func() {
    let state = Escrow.init();
    let user = Principal.fromText("aaaaa-aa");
    let token = "ICP";

    // Deposit and lock
    ignore Escrow.deposit(state, user, token, 1000000);
    ignore Escrow.lock(state, user, token, 600000);

    // Release 300k
    let releaseResult = Escrow.release(state, user, token, 300000);
    switch (releaseResult) {
      case (#ok(amount)) { assert(amount == 300000) };
      case (#err(_)) { assert(false) }; // Should not fail
    };

    let account = Escrow.getBalance(state, user, token);
    assert(account.balance == 700000);  // 1M - 300k
    assert(account.locked == 300000);   // 600k - 300k
    assert(account.available == 400000); // 700k - 300k
  });

  test("withdraws available funds correctly", func() {
    let state = Escrow.init();
    let user = Principal.fromText("aaaaa-aa");
    let token = "ICP";

    // Deposit
    ignore Escrow.deposit(state, user, token, 1000000);

    // Lock some
    ignore Escrow.lock(state, user, token, 300000);

    // Can only withdraw available (700k)
    let withdrawResult = Escrow.withdraw(state, user, token, 500000);
    switch (withdrawResult) {
      case (#ok(amount)) { assert(amount == 500000) };
      case (#err(_)) { assert(false) }; // Should not fail
    };

    let account = Escrow.getBalance(state, user, token);
    assert(account.balance == 500000);
    assert(account.locked == 300000);
    assert(account.available == 200000);
  });

  test("rejects operations with insufficient balance", func() {
    let state = Escrow.init();
    let user = Principal.fromText("aaaaa-aa");
    let token = "ICP";

    ignore Escrow.deposit(state, user, token, 1000);

    // Try to lock more than available
    let lockResult = Escrow.lock(state, user, token, 2000);
    switch (lockResult) {
      case (#ok(_)) { assert(false) }; // Should fail
      case (#err(#InsufficientBalance)) {};
      case (#err(_)) { assert(false) }; // Wrong error type
    };

    // Try to withdraw more than available
    let withdrawResult = Escrow.withdraw(state, user, token, 2000);
    switch (withdrawResult) {
      case (#ok(_)) { assert(false) }; // Should fail
      case (#err(#InsufficientBalance)) {};
      case (#err(_)) { assert(false) }; // Wrong error type
    };
  });

  test("handles multiple tokens independently", func() {
    let state = Escrow.init();
    let user = Principal.fromText("aaaaa-aa");

    // Deposit different tokens
    ignore Escrow.deposit(state, user, "ICP", 1000000);
    ignore Escrow.deposit(state, user, "ryjl3-tyaaa-aaaaa-aaaba-cai", 500000);

    let icpAccount = Escrow.getBalance(state, user, "ICP");
    let tokenAccount = Escrow.getBalance(state, user, "ryjl3-tyaaa-aaaaa-aaaba-cai");

    assert(icpAccount.balance == 1000000);
    assert(tokenAccount.balance == 500000);

    // Locking one token doesn't affect the other
    ignore Escrow.lock(state, user, "ICP", 500000);

    let icpAccount2 = Escrow.getBalance(state, user, "ICP");
    assert(icpAccount2.available == 500000);

    let tokenAccount2 = Escrow.getBalance(state, user, "ryjl3-tyaaa-aaaaa-aaaba-cai");
    assert(tokenAccount2.available == 500000);
  });

});
