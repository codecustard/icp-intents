/// Unit tests for Escrow module
/// Tests deposit, lock, unlock, release, and withdraw operations

import Debug "mo:base/Debug";
import Escrow "../src/icp-intents-lib/Escrow";
import Principal "mo:base/Principal";

module {
  public func run() {
    Debug.print("=== Escrow Tests ===");

    testDeposit();
    testLockUnlock();
    testRelease();
    testWithdraw();
    testInsufficientBalance();
    testMultipleTokens();

    Debug.print("✓ All Escrow tests passed");
  };

  func testDeposit() {
    Debug.print("Testing escrow deposit...");

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
      case (#err(e)) { Debug.trap("Deposit failed") };
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

    Debug.print("  ✓ Deposit passed");
  };

  func testLockUnlock() {
    Debug.print("Testing lock/unlock...");

    let state = Escrow.init();
    let user = Principal.fromText("aaaaa-aa");
    let token = "ICP";

    // Deposit
    ignore Escrow.deposit(state, user, token, 1000000);

    // Lock 600k
    let lockResult = Escrow.lock(state, user, token, 600000);
    switch (lockResult) {
      case (#ok(_)) {};
      case (#err(e)) { Debug.trap("Lock failed") };
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

    Debug.print("  ✓ Lock/unlock passed");
  };

  func testRelease() {
    Debug.print("Testing release...");

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
      case (#err(e)) { Debug.trap("Release failed") };
    };

    let account = Escrow.getBalance(state, user, token);
    assert(account.balance == 700000);  // 1M - 300k
    assert(account.locked == 300000);   // 600k - 300k
    assert(account.available == 400000); // 700k - 300k

    Debug.print("  ✓ Release passed");
  };

  func testWithdraw() {
    Debug.print("Testing withdraw...");

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
      case (#err(e)) { Debug.trap("Withdraw failed") };
    };

    let account = Escrow.getBalance(state, user, token);
    assert(account.balance == 500000);
    assert(account.locked == 300000);
    assert(account.available == 200000);

    Debug.print("  ✓ Withdraw passed");
  };

  func testInsufficientBalance() {
    Debug.print("Testing insufficient balance errors...");

    let state = Escrow.init();
    let user = Principal.fromText("aaaaa-aa");
    let token = "ICP";

    ignore Escrow.deposit(state, user, token, 1000);

    // Try to lock more than available
    let lockResult = Escrow.lock(state, user, token, 2000);
    switch (lockResult) {
      case (#ok(_)) { Debug.trap("Should have failed") };
      case (#err(#InsufficientBalance)) {};
      case (#err(e)) { Debug.trap("Wrong error type") };
    };

    // Try to withdraw more than available
    let withdrawResult = Escrow.withdraw(state, user, token, 2000);
    switch (withdrawResult) {
      case (#ok(_)) { Debug.trap("Should have failed") };
      case (#err(#InsufficientBalance)) {};
      case (#err(e)) { Debug.trap("Wrong error type") };
    };

    Debug.print("  ✓ Insufficient balance errors passed");
  };

  func testMultipleTokens() {
    Debug.print("Testing multiple tokens...");

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
    assert(icpAccount.available == 500000);

    let tokenAccount2 = Escrow.getBalance(state, user, "ryjl3-tyaaa-aaaaa-aaaba-cai");
    assert(tokenAccount2.available == 500000);

    Debug.print("  ✓ Multiple tokens passed");
  };
}
