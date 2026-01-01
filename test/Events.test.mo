import { test; suite } = "mo:test";
import Events "../src/icp-intents-lib/core/Events";
import Principal "mo:base/Principal";
import Time "mo:base/Time";

suite("Events - EventLogger Creation", func() {
  test("EventLogger can be instantiated", func() {
    let logger = Events.EventLogger();
    // If we get here, instantiation succeeded
    assert(true);
  });
});

suite("Events - IntentCreated Event", func() {
  test("emit IntentCreated event does not error", func() {
    let logger = Events.EventLogger();
    let event : Events.IntentEvent = #IntentCreated({
      intent_id = 1;
      user = Principal.fromText("aaaaa-aa");
      source_chain = "ethereum";
      dest_chain = "hoosat";
      amount = 1000_000;
      timestamp = 1000000000000;
    });

    logger.emit(event);
    assert(true);
  });
});

suite("Events - QuoteSubmitted Event", func() {
  test("emit QuoteSubmitted event does not error", func() {
    let logger = Events.EventLogger();
    let event : Events.IntentEvent = #QuoteSubmitted({
      intent_id = 1;
      solver = Principal.fromText("aaaaa-aa");
      quote_index = 0;
      output_amount = 1000_000;
      fee = 5_000;
      timestamp = 1000000000000;
    });

    logger.emit(event);
    assert(true);
  });
});

suite("Events - QuoteConfirmed Event", func() {
  test("emit QuoteConfirmed event does not error", func() {
    let logger = Events.EventLogger();
    let event : Events.IntentEvent = #QuoteConfirmed({
      intent_id = 1;
      solver = Principal.fromText("aaaaa-aa");
      quote_index = 0;
      deposit_address = "0x1234567890abcdef";
      timestamp = 1000000000000;
    });

    logger.emit(event);
    assert(true);
  });
});

suite("Events - DepositVerified Event", func() {
  test("emit DepositVerified event does not error", func() {
    let logger = Events.EventLogger();
    let event : Events.IntentEvent = #DepositVerified({
      intent_id = 1;
      chain = "ethereum";
      tx_hash = "0xabcdef1234567890";
      amount = 1000_000;
      timestamp = 1000000000000;
    });

    logger.emit(event);
    assert(true);
  });
});

suite("Events - IntentFulfilled Event", func() {
  test("emit IntentFulfilled event does not error", func() {
    let logger = Events.EventLogger();
    let event : Events.IntentEvent = #IntentFulfilled({
      intent_id = 1;
      solver = Principal.fromText("aaaaa-aa");
      final_amount = 990_000;
      protocol_fee = 3_000;
      timestamp = 1000000000000;
    });

    logger.emit(event);
    assert(true);
  });
});

suite("Events - IntentCancelled Event", func() {
  test("emit IntentCancelled event does not error", func() {
    let logger = Events.EventLogger();
    let event : Events.IntentEvent = #IntentCancelled({
      intent_id = 1;
      reason = "User requested cancellation";
      timestamp = 1000000000000;
    });

    logger.emit(event);
    assert(true);
  });
});

suite("Events - IntentExpired Event", func() {
  test("emit IntentExpired event does not error", func() {
    let logger = Events.EventLogger();
    let event : Events.IntentEvent = #IntentExpired({
      intent_id = 1;
      deadline = 1000000000000;
      timestamp = 1000000010000;
    });

    logger.emit(event);
    assert(true);
  });
});

suite("Events - EscrowLocked Event", func() {
  test("emit EscrowLocked event does not error", func() {
    let logger = Events.EventLogger();
    let event : Events.IntentEvent = #EscrowLocked({
      intent_id = 1;
      user = Principal.fromText("aaaaa-aa");
      token = "ICP";
      amount = 1000_000;
      timestamp = 1000000000000;
    });

    logger.emit(event);
    assert(true);
  });
});

suite("Events - EscrowReleased Event", func() {
  test("emit EscrowReleased event does not error", func() {
    let logger = Events.EventLogger();
    let event : Events.IntentEvent = #EscrowReleased({
      intent_id = 1;
      recipient = Principal.fromText("aaaaa-aa");
      token = "ICP";
      amount = 1000_000;
      timestamp = 1000000000000;
    });

    logger.emit(event);
    assert(true);
  });
});

suite("Events - FeeCollected Event", func() {
  test("emit FeeCollected event does not error", func() {
    let logger = Events.EventLogger();
    let event : Events.IntentEvent = #FeeCollected({
      intent_id = 1;
      token = "ICP";
      amount = 3_000;
      collector = Principal.fromText("aaaaa-aa");
      timestamp = 1000000000000;
    });

    logger.emit(event);
    assert(true);
  });
});

suite("Events - Multiple Events", func() {
  test("can emit multiple events in sequence", func() {
    let logger = Events.EventLogger();

    let event1 : Events.IntentEvent = #IntentCreated({
      intent_id = 1;
      user = Principal.fromText("aaaaa-aa");
      source_chain = "ethereum";
      dest_chain = "hoosat";
      amount = 1000_000;
      timestamp = 1000000000000;
    });

    let event2 : Events.IntentEvent = #QuoteSubmitted({
      intent_id = 1;
      solver = Principal.fromText("2vxsx-fae");
      quote_index = 0;
      output_amount = 950_000;
      fee = 5_000;
      timestamp = 1000000001000;
    });

    let event3 : Events.IntentEvent = #QuoteConfirmed({
      intent_id = 1;
      solver = Principal.fromText("2vxsx-fae");
      quote_index = 0;
      deposit_address = "0x1234567890abcdef";
      timestamp = 1000000002000;
    });

    logger.emit(event1);
    logger.emit(event2);
    logger.emit(event3);

    assert(true);
  });

  test("can use same logger for different event types", func() {
    let logger = Events.EventLogger();

    logger.emit(#IntentCreated({
      intent_id = 1;
      user = Principal.fromText("aaaaa-aa");
      source_chain = "ethereum";
      dest_chain = "hoosat";
      amount = 1000_000;
      timestamp = 1000000000000;
    }));

    logger.emit(#EscrowLocked({
      intent_id = 1;
      user = Principal.fromText("aaaaa-aa");
      token = "ICP";
      amount = 1000_000;
      timestamp = 1000000000000;
    }));

    logger.emit(#IntentCancelled({
      intent_id = 1;
      reason = "Test cancellation";
      timestamp = 1000000001000;
    }));

    assert(true);
  });
});

suite("Events - Edge Cases", func() {
  test("handles zero amounts", func() {
    let logger = Events.EventLogger();
    let event : Events.IntentEvent = #IntentCreated({
      intent_id = 1;
      user = Principal.fromText("aaaaa-aa");
      source_chain = "ethereum";
      dest_chain = "hoosat";
      amount = 0;
      timestamp = 1000000000000;
    });

    logger.emit(event);
    assert(true);
  });

  test("handles large intent IDs", func() {
    let logger = Events.EventLogger();
    let event : Events.IntentEvent = #IntentCreated({
      intent_id = 999_999_999;
      user = Principal.fromText("aaaaa-aa");
      source_chain = "ethereum";
      dest_chain = "hoosat";
      amount = 1000_000;
      timestamp = 1000000000000;
    });

    logger.emit(event);
    assert(true);
  });

  test("handles empty reason text", func() {
    let logger = Events.EventLogger();
    let event : Events.IntentEvent = #IntentCancelled({
      intent_id = 1;
      reason = "";
      timestamp = 1000000000000;
    });

    logger.emit(event);
    assert(true);
  });

  test("handles long chain names", func() {
    let logger = Events.EventLogger();
    let event : Events.IntentEvent = #IntentCreated({
      intent_id = 1;
      user = Principal.fromText("aaaaa-aa");
      source_chain = "very-long-chain-name-for-testing-purposes";
      dest_chain = "another-very-long-chain-name";
      amount = 1000_000;
      timestamp = 1000000000000;
    });

    logger.emit(event);
    assert(true);
  });
});
