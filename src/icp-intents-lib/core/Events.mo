/// Structured event logging for intent state transitions
///
/// Enables off-chain indexing and monitoring of intent lifecycle events

import Time "mo:base/Time";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";

module {
  /// Event types for intent lifecycle
  public type IntentEvent = {
    #IntentCreated : {
      intent_id : Nat;
      user : Principal;
      source_chain : Text;
      dest_chain : Text;
      amount : Nat;
      timestamp : Time.Time;
    };
    #QuoteSubmitted : {
      intent_id : Nat;
      solver : Principal;
      quote_index : Nat;
      output_amount : Nat;
      fee : Nat;
      timestamp : Time.Time;
    };
    #QuoteConfirmed : {
      intent_id : Nat;
      solver : Principal;
      quote_index : Nat;
      deposit_address : Text;
      timestamp : Time.Time;
    };
    #DepositVerified : {
      intent_id : Nat;
      chain : Text;
      tx_hash : Text;
      amount : Nat;
      timestamp : Time.Time;
    };
    #IntentFulfilled : {
      intent_id : Nat;
      solver : Principal;
      final_amount : Nat;
      protocol_fee : Nat;
      timestamp : Time.Time;
    };
    #IntentCancelled : {
      intent_id : Nat;
      reason : Text;
      timestamp : Time.Time;
    };
    #IntentExpired : {
      intent_id : Nat;
      deadline : Time.Time;
      timestamp : Time.Time;
    };
    #EscrowLocked : {
      intent_id : Nat;
      user : Principal;
      token : Text;
      amount : Nat;
      timestamp : Time.Time;
    };
    #EscrowReleased : {
      intent_id : Nat;
      recipient : Principal;
      token : Text;
      amount : Nat;
      timestamp : Time.Time;
    };
    #FeeCollected : {
      intent_id : Nat;
      token : Text;
      amount : Nat;
      collector : Principal;
      timestamp : Time.Time;
    };
  };

  /// Event logger with configurable output
  public class EventLogger() {
    /// Emit event to Debug.print for local development
    /// In production, this could write to stable storage or IC event stream
    public func emit(event : IntentEvent) {
      let formatted = formatEvent(event);
      Debug.print("[EVENT] " # formatted);
    };

    /// Format event as structured string for logging
    func formatEvent(event : IntentEvent) : Text {
      switch (event) {
        case (#IntentCreated(e)) {
          "IntentCreated { intent_id: " # Nat.toText(e.intent_id) #
          ", user: " # Principal.toText(e.user) #
          ", " # e.source_chain # " → " # e.dest_chain #
          ", amount: " # Nat.toText(e.amount) # " }"
        };
        case (#QuoteSubmitted(e)) {
          "QuoteSubmitted { intent_id: " # Nat.toText(e.intent_id) #
          ", solver: " # Principal.toText(e.solver) #
          ", output: " # Nat.toText(e.output_amount) #
          ", fee: " # Nat.toText(e.fee) # " }"
        };
        case (#QuoteConfirmed(e)) {
          "QuoteConfirmed { intent_id: " # Nat.toText(e.intent_id) #
          ", solver: " # Principal.toText(e.solver) #
          ", deposit_address: " # e.deposit_address # " }"
        };
        case (#DepositVerified(e)) {
          "DepositVerified { intent_id: " # Nat.toText(e.intent_id) #
          ", chain: " # e.chain #
          ", tx: " # e.tx_hash #
          ", amount: " # Nat.toText(e.amount) # " }"
        };
        case (#IntentFulfilled(e)) {
          "IntentFulfilled { intent_id: " # Nat.toText(e.intent_id) #
          ", solver: " # Principal.toText(e.solver) #
          ", amount: " # Nat.toText(e.final_amount) #
          ", protocol_fee: " # Nat.toText(e.protocol_fee) # " }"
        };
        case (#IntentCancelled(e)) {
          "IntentCancelled { intent_id: " # Nat.toText(e.intent_id) #
          ", reason: " # e.reason # " }"
        };
        case (#IntentExpired(e)) {
          "IntentExpired { intent_id: " # Nat.toText(e.intent_id) #
          ", deadline: " # debug_show(e.deadline) # " }"
        };
        case (#EscrowLocked(e)) {
          "EscrowLocked { intent_id: " # Nat.toText(e.intent_id) #
          ", user: " # Principal.toText(e.user) #
          ", token: " # e.token #
          ", amount: " # Nat.toText(e.amount) # " }"
        };
        case (#EscrowReleased(e)) {
          "EscrowReleased { intent_id: " # Nat.toText(e.intent_id) #
          ", recipient: " # Principal.toText(e.recipient) #
          ", token: " # e.token #
          ", amount: " # Nat.toText(e.amount) # " }"
        };
        case (#FeeCollected(e)) {
          "FeeCollected { intent_id: " # Nat.toText(e.intent_id) #
          ", token: " # e.token #
          ", amount: " # Nat.toText(e.amount) #
          ", collector: " # Principal.toText(e.collector) # " }"
        };
      }
    };
  };
}
