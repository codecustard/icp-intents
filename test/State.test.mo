import { test; suite } = "mo:test";
import State "../src/icp-intents-lib/core/State";
import Types "../src/icp-intents-lib/core/Types";
import Principal "mo:base/Principal";

// Helper to create a test intent in a specific status
func createTestIntent(status : Types.IntentStatus) : Types.Intent {
  {
    id = 0;
    user = Principal.fromText("aaaaa-aa");
    source = { chain = "ethereum"; chain_id = ?1; token = "ETH"; network = "mainnet" };
    destination = { chain = "icp"; chain_id = null; token = "ICP"; network = "mainnet" };
    source_amount = 1000_000;
    min_output = 950_000;
    dest_recipient = "account123";
    created_at = 1000000000000;
    deadline = 2000000000000;
    verified_at = null;
    status = status;
    quotes = [];
    selected_quote = null;
    escrow_balance = 0;
    generated_address = null;
    deposited_utxo = null;
    solver_tx_hash = null;
    protocol_fee_bps = 30;
    custom_rpc_urls = null;
    verification_hints = null;
    metadata = null;
  }
};

suite("State - Transition to Quoted", func() {
  test("transitionToQuoted succeeds from PendingQuote", func() {
    let intent = createTestIntent(#PendingQuote);

    let result = State.transitionToQuoted(intent);

    switch (result) {
      case (#ok(newIntent)) {
        assert(newIntent.status == #Quoted);
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToQuoted is idempotent when already Quoted", func() {
    let intent = createTestIntent(#Quoted);

    let result = State.transitionToQuoted(intent);

    switch (result) {
      case (#ok(newIntent)) {
        assert(newIntent.status == #Quoted);
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToQuoted fails from Confirmed", func() {
    let intent = createTestIntent(#Confirmed);

    let result = State.transitionToQuoted(intent);

    switch (result) {
      case (#ok(_)) { assert(false) };
      case (#err(#InvalidStatus(_))) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToQuoted fails from Deposited", func() {
    let intent = createTestIntent(#Deposited);

    let result = State.transitionToQuoted(intent);

    switch (result) {
      case (#ok(_)) { assert(false) };
      case (#err(#InvalidStatus(_))) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToQuoted fails from Fulfilled", func() {
    let intent = createTestIntent(#Fulfilled);

    let result = State.transitionToQuoted(intent);

    switch (result) {
      case (#ok(_)) { assert(false) };
      case (#err(#InvalidStatus(_))) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });
});

suite("State - Transition to Confirmed", func() {
  test("transitionToConfirmed succeeds from Quoted before deadline", func() {
    let intent = createTestIntent(#Quoted);
    let currentTime = 1500000000000; // Before deadline

    let result = State.transitionToConfirmed(intent, currentTime);

    switch (result) {
      case (#ok(newIntent)) {
        assert(newIntent.status == #Confirmed);
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToConfirmed fails if expired", func() {
    let intent = createTestIntent(#Quoted);
    let currentTime = 3000000000000; // After deadline

    let result = State.transitionToConfirmed(intent, currentTime);

    switch (result) {
      case (#ok(_)) { assert(false) };
      case (#err(#Expired)) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToConfirmed fails from PendingQuote", func() {
    let intent = createTestIntent(#PendingQuote);
    let currentTime = 1500000000000;

    let result = State.transitionToConfirmed(intent, currentTime);

    switch (result) {
      case (#ok(_)) { assert(false) };
      case (#err(#InvalidStatus(_))) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToConfirmed fails from Deposited", func() {
    let intent = createTestIntent(#Deposited);
    let currentTime = 1500000000000;

    let result = State.transitionToConfirmed(intent, currentTime);

    switch (result) {
      case (#ok(_)) { assert(false) };
      case (#err(#InvalidStatus(_))) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });
});

suite("State - Transition to Deposited", func() {
  test("transitionToDeposited succeeds from Confirmed before deadline", func() {
    let intent = createTestIntent(#Confirmed);
    let verifiedAt = 1600000000000;
    let currentTime = 1600000000000;

    let result = State.transitionToDeposited(intent, verifiedAt, currentTime);

    switch (result) {
      case (#ok(newIntent)) {
        assert(newIntent.status == #Deposited);
        assert(newIntent.verified_at == ?verifiedAt);
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToDeposited is idempotent when already Deposited", func() {
    let intent = createTestIntent(#Deposited);
    let verifiedAt = 1600000000000;
    let currentTime = 1600000000000;

    let result = State.transitionToDeposited(intent, verifiedAt, currentTime);

    switch (result) {
      case (#ok(newIntent)) {
        assert(newIntent.status == #Deposited);
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToDeposited fails if expired", func() {
    let intent = createTestIntent(#Confirmed);
    let verifiedAt = 3000000000000;
    let currentTime = 3000000000000;

    let result = State.transitionToDeposited(intent, verifiedAt, currentTime);

    switch (result) {
      case (#ok(_)) { assert(false) };
      case (#err(#Expired)) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToDeposited fails from PendingQuote", func() {
    let intent = createTestIntent(#PendingQuote);
    let verifiedAt = 1600000000000;
    let currentTime = 1600000000000;

    let result = State.transitionToDeposited(intent, verifiedAt, currentTime);

    switch (result) {
      case (#ok(_)) { assert(false) };
      case (#err(#InvalidStatus(_))) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToDeposited fails from Quoted", func() {
    let intent = createTestIntent(#Quoted);
    let verifiedAt = 1600000000000;
    let currentTime = 1600000000000;

    let result = State.transitionToDeposited(intent, verifiedAt, currentTime);

    switch (result) {
      case (#ok(_)) { assert(false) };
      case (#err(#InvalidStatus(_))) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });
});

suite("State - Transition to Fulfilled", func() {
  test("transitionToFulfilled succeeds from Deposited", func() {
    let intent = createTestIntent(#Deposited);
    let currentTime = 1700000000000;

    let result = State.transitionToFulfilled(intent, currentTime);

    switch (result) {
      case (#ok(newIntent)) {
        assert(newIntent.status == #Fulfilled);
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToFulfilled is idempotent when already Fulfilled", func() {
    let intent = createTestIntent(#Fulfilled);
    let currentTime = 1700000000000;

    let result = State.transitionToFulfilled(intent, currentTime);

    switch (result) {
      case (#ok(newIntent)) {
        assert(newIntent.status == #Fulfilled);
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToFulfilled fails from PendingQuote", func() {
    let intent = createTestIntent(#PendingQuote);
    let currentTime = 1700000000000;

    let result = State.transitionToFulfilled(intent, currentTime);

    switch (result) {
      case (#ok(_)) { assert(false) };
      case (#err(#InvalidStatus(_))) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToFulfilled fails from Confirmed", func() {
    let intent = createTestIntent(#Confirmed);
    let currentTime = 1700000000000;

    let result = State.transitionToFulfilled(intent, currentTime);

    switch (result) {
      case (#ok(_)) { assert(false) };
      case (#err(#InvalidStatus(_))) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });
});

suite("State - Transition to Cancelled", func() {
  test("transitionToCancelled succeeds from PendingQuote", func() {
    let intent = createTestIntent(#PendingQuote);

    let result = State.transitionToCancelled(intent);

    switch (result) {
      case (#ok(newIntent)) {
        assert(newIntent.status == #Cancelled);
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToCancelled succeeds from Quoted", func() {
    let intent = createTestIntent(#Quoted);

    let result = State.transitionToCancelled(intent);

    switch (result) {
      case (#ok(newIntent)) {
        assert(newIntent.status == #Cancelled);
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToCancelled succeeds from Confirmed", func() {
    let intent = createTestIntent(#Confirmed);

    let result = State.transitionToCancelled(intent);

    switch (result) {
      case (#ok(newIntent)) {
        assert(newIntent.status == #Cancelled);
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToCancelled succeeds from Deposited", func() {
    let intent = createTestIntent(#Deposited);

    let result = State.transitionToCancelled(intent);

    switch (result) {
      case (#ok(newIntent)) {
        assert(newIntent.status == #Cancelled);
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToCancelled is idempotent when already Cancelled", func() {
    let intent = createTestIntent(#Cancelled);

    let result = State.transitionToCancelled(intent);

    switch (result) {
      case (#ok(newIntent)) {
        assert(newIntent.status == #Cancelled);
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToCancelled fails from Fulfilled", func() {
    let intent = createTestIntent(#Fulfilled);

    let result = State.transitionToCancelled(intent);

    switch (result) {
      case (#ok(_)) { assert(false) };
      case (#err(#InvalidStatus(_))) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });
});

suite("State - Transition to Expired", func() {
  test("transitionToExpired succeeds from PendingQuote after deadline", func() {
    let intent = createTestIntent(#PendingQuote);
    let currentTime = 3000000000000; // After deadline

    let result = State.transitionToExpired(intent, currentTime);

    switch (result) {
      case (#ok(newIntent)) {
        assert(newIntent.status == #Expired);
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToExpired succeeds from Quoted after deadline", func() {
    let intent = createTestIntent(#Quoted);
    let currentTime = 3000000000000;

    let result = State.transitionToExpired(intent, currentTime);

    switch (result) {
      case (#ok(newIntent)) {
        assert(newIntent.status == #Expired);
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToExpired fails before deadline", func() {
    let intent = createTestIntent(#Quoted);
    let currentTime = 1500000000000; // Before deadline

    let result = State.transitionToExpired(intent, currentTime);

    switch (result) {
      case (#ok(_)) { assert(false) };
      case (#err(#InvalidStatus(_))) { assert(true) };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToExpired preserves Fulfilled status", func() {
    let intent = createTestIntent(#Fulfilled);
    let currentTime = 3000000000000;

    let result = State.transitionToExpired(intent, currentTime);

    switch (result) {
      case (#ok(newIntent)) {
        assert(newIntent.status == #Fulfilled); // Should stay Fulfilled
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToExpired preserves Cancelled status", func() {
    let intent = createTestIntent(#Cancelled);
    let currentTime = 3000000000000;

    let result = State.transitionToExpired(intent, currentTime);

    switch (result) {
      case (#ok(newIntent)) {
        assert(newIntent.status == #Cancelled); // Should stay Cancelled
      };
      case (#err(_)) { assert(false) };
    };
  });

  test("transitionToExpired is idempotent when already Expired", func() {
    let intent = createTestIntent(#Expired);
    let currentTime = 3000000000000;

    let result = State.transitionToExpired(intent, currentTime);

    switch (result) {
      case (#ok(newIntent)) {
        assert(newIntent.status == #Expired);
      };
      case (#err(_)) { assert(false) };
    };
  });
});

suite("State - Validate Transition", func() {
  test("validateTransition allows PendingQuote → Quoted", func() {
    assert(State.validateTransition(#PendingQuote, #Quoted));
  });

  test("validateTransition allows PendingQuote → Cancelled", func() {
    assert(State.validateTransition(#PendingQuote, #Cancelled));
  });

  test("validateTransition allows PendingQuote → Expired", func() {
    assert(State.validateTransition(#PendingQuote, #Expired));
  });

  test("validateTransition allows Quoted → Confirmed", func() {
    assert(State.validateTransition(#Quoted, #Confirmed));
  });

  test("validateTransition allows Quoted → Cancelled", func() {
    assert(State.validateTransition(#Quoted, #Cancelled));
  });

  test("validateTransition allows Confirmed → Deposited", func() {
    assert(State.validateTransition(#Confirmed, #Deposited));
  });

  test("validateTransition allows Deposited → Fulfilled", func() {
    assert(State.validateTransition(#Deposited, #Fulfilled));
  });

  test("validateTransition rejects PendingQuote → Confirmed", func() {
    assert(not State.validateTransition(#PendingQuote, #Confirmed));
  });

  test("validateTransition rejects Quoted → Deposited", func() {
    assert(not State.validateTransition(#Quoted, #Deposited));
  });

  test("validateTransition rejects transitions from Fulfilled", func() {
    assert(not State.validateTransition(#Fulfilled, #Cancelled));
    assert(not State.validateTransition(#Fulfilled, #Expired));
    assert(not State.validateTransition(#Fulfilled, #PendingQuote));
  });

  test("validateTransition rejects transitions from Cancelled", func() {
    assert(not State.validateTransition(#Cancelled, #Quoted));
    assert(not State.validateTransition(#Cancelled, #Fulfilled));
  });

  test("validateTransition rejects transitions from Expired", func() {
    assert(not State.validateTransition(#Expired, #Quoted));
    assert(not State.validateTransition(#Expired, #Fulfilled));
  });

  test("validateTransition allows self-transitions", func() {
    assert(State.validateTransition(#PendingQuote, #PendingQuote));
    assert(State.validateTransition(#Quoted, #Quoted));
    assert(State.validateTransition(#Confirmed, #Confirmed));
    assert(State.validateTransition(#Deposited, #Deposited));
  });
});

suite("State - Status Utilities", func() {
  test("statusToText returns correct strings", func() {
    assert(State.statusToText(#PendingQuote) == "PendingQuote");
    assert(State.statusToText(#Quoted) == "Quoted");
    assert(State.statusToText(#Confirmed) == "Confirmed");
    assert(State.statusToText(#Deposited) == "Deposited");
    assert(State.statusToText(#Fulfilled) == "Fulfilled");
    assert(State.statusToText(#Cancelled) == "Cancelled");
    assert(State.statusToText(#Expired) == "Expired");
  });

  test("getNextStatuses returns correct transitions for PendingQuote", func() {
    let next = State.getNextStatuses(#PendingQuote);
    assert(next.size() == 3);
    // Should contain Quoted, Cancelled, Expired
  });

  test("getNextStatuses returns correct transitions for Quoted", func() {
    let next = State.getNextStatuses(#Quoted);
    assert(next.size() == 3);
    // Should contain Confirmed, Cancelled, Expired
  });

  test("getNextStatuses returns correct transitions for Confirmed", func() {
    let next = State.getNextStatuses(#Confirmed);
    assert(next.size() == 3);
    // Should contain Deposited, Cancelled, Expired
  });

  test("getNextStatuses returns correct transitions for Deposited", func() {
    let next = State.getNextStatuses(#Deposited);
    assert(next.size() == 3);
    // Should contain Fulfilled, Cancelled, Expired
  });

  test("getNextStatuses returns empty for terminal states", func() {
    assert(State.getNextStatuses(#Fulfilled).size() == 0);
    assert(State.getNextStatuses(#Cancelled).size() == 0);
    assert(State.getNextStatuses(#Expired).size() == 0);
  });

  test("isTerminal returns true for Fulfilled", func() {
    assert(State.isTerminal(#Fulfilled));
  });

  test("isTerminal returns true for Cancelled", func() {
    assert(State.isTerminal(#Cancelled));
  });

  test("isTerminal returns true for Expired", func() {
    assert(State.isTerminal(#Expired));
  });

  test("isTerminal returns false for PendingQuote", func() {
    assert(not State.isTerminal(#PendingQuote));
  });

  test("isTerminal returns false for Quoted", func() {
    assert(not State.isTerminal(#Quoted));
  });

  test("isTerminal returns false for Confirmed", func() {
    assert(not State.isTerminal(#Confirmed));
  });

  test("isTerminal returns false for Deposited", func() {
    assert(not State.isTerminal(#Deposited));
  });
});
