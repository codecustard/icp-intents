/// Intent state machine and transition logic
///
/// Enforces valid state transitions and business rules

import Types "./Types";
import Errors "./Errors";
import Time "mo:base/Time";
import Debug "mo:base/Debug";

module {
  type Intent = Types.Intent;
  type IntentStatus = Types.IntentStatus;
  type IntentError = Types.IntentError;
  type IntentResult<T> = Types.IntentResult<T>;

  /// Valid state transitions
  /// PendingQuote → Quoted → Confirmed → Deposited → Fulfilled
  ///             ↓         ↓         ↓         ↓
  ///          Cancelled/Expired

  /// Transition intent to Quoted status
  public func transitionToQuoted(intent : Intent) : IntentResult<Intent> {
    switch (intent.status) {
      case (#PendingQuote) {
        #ok({ intent with status = #Quoted })
      };
      case (#Quoted) {
        // Already quoted, just return
        #ok(intent)
      };
      case (_) {
        #err(#InvalidStatus("Cannot transition from " # statusToText(intent.status) # " to Quoted"))
      };
    }
  };

  /// Transition intent to Confirmed status
  public func transitionToConfirmed(intent : Intent, currentTime : Time.Time) : IntentResult<Intent> {
    // Check expiry first
    if (currentTime > intent.deadline) {
      return #err(#Expired);
    };

    switch (intent.status) {
      case (#Quoted) {
        #ok({ intent with status = #Confirmed })
      };
      case (_) {
        #err(#InvalidStatus("Cannot transition from " # statusToText(intent.status) # " to Confirmed"))
      };
    }
  };

  /// Transition intent to Deposited status
  public func transitionToDeposited(intent : Intent, verifiedAt : Time.Time, currentTime : Time.Time) : IntentResult<Intent> {
    // Check expiry
    if (currentTime > intent.deadline) {
      return #err(#Expired);
    };

    switch (intent.status) {
      case (#Confirmed) {
        #ok({
          intent with
          status = #Deposited;
          verified_at = ?verifiedAt;
        })
      };
      case (#Deposited) {
        // Already deposited
        #ok(intent)
      };
      case (_) {
        #err(#InvalidStatus("Cannot transition from " # statusToText(intent.status) # " to Deposited"))
      };
    }
  };

  /// Transition intent to Fulfilled status
  public func transitionToFulfilled(intent : Intent, _currentTime : Time.Time) : IntentResult<Intent> {
    // Fulfilled can happen from Deposited status
    switch (intent.status) {
      case (#Deposited) {
        #ok({ intent with status = #Fulfilled })
      };
      case (#Fulfilled) {
        // Already fulfilled
        #ok(intent)
      };
      case (_) {
        #err(#InvalidStatus("Cannot transition from " # statusToText(intent.status) # " to Fulfilled"))
      };
    }
  };

  /// Transition intent to Cancelled status
  public func transitionToCancelled(intent : Intent) : IntentResult<Intent> {
    // Can cancel from most states except Fulfilled
    switch (intent.status) {
      case (#Fulfilled) {
        #err(#InvalidStatus("Cannot cancel fulfilled intent"))
      };
      case (#Cancelled) {
        #ok(intent) // Already cancelled
      };
      case (_) {
        #ok({ intent with status = #Cancelled })
      };
    }
  };

  /// Transition intent to Expired status
  public func transitionToExpired(intent : Intent, currentTime : Time.Time) : IntentResult<Intent> {
    // Only transition to expired if past deadline and not already terminal
    if (currentTime <= intent.deadline) {
      return #err(#InvalidStatus("Intent has not reached deadline yet"));
    };

    switch (intent.status) {
      case (#Fulfilled) {
        #ok(intent) // Already fulfilled, don't mark as expired
      };
      case (#Cancelled) {
        #ok(intent) // Already cancelled
      };
      case (#Expired) {
        #ok(intent) // Already expired
      };
      case (_) {
        #ok({ intent with status = #Expired })
      };
    }
  };

  /// Validate state transition
  public func validateTransition(from : IntentStatus, to : IntentStatus) : Bool {
    switch (from, to) {
      // PendingQuote transitions
      case (#PendingQuote, #Quoted) { true };
      case (#PendingQuote, #Cancelled) { true };
      case (#PendingQuote, #Expired) { true };

      // Quoted transitions
      case (#Quoted, #Confirmed) { true };
      case (#Quoted, #Cancelled) { true };
      case (#Quoted, #Expired) { true };

      // Confirmed transitions
      case (#Confirmed, #Deposited) { true };
      case (#Confirmed, #Cancelled) { true };
      case (#Confirmed, #Expired) { true };

      // Deposited transitions
      case (#Deposited, #Fulfilled) { true };
      case (#Deposited, #Cancelled) { true };
      case (#Deposited, #Expired) { true };

      // Terminal states (no transitions out)
      case (#Fulfilled, _) { false };
      case (#Cancelled, _) { false };
      case (#Expired, _) { false };

      // Self-transitions (idempotent)
      case (s1, s2) { s1 == s2 };
    }
  };

  /// Convert status to text
  public func statusToText(status : IntentStatus) : Text {
    switch (status) {
      case (#PendingQuote) { "PendingQuote" };
      case (#Quoted) { "Quoted" };
      case (#Confirmed) { "Confirmed" };
      case (#Deposited) { "Deposited" };
      case (#Fulfilled) { "Fulfilled" };
      case (#Cancelled) { "Cancelled" };
      case (#Expired) { "Expired" };
    }
  };

  /// Get next allowed statuses
  public func getNextStatuses(status : IntentStatus) : [IntentStatus] {
    switch (status) {
      case (#PendingQuote) { [#Quoted, #Cancelled, #Expired] };
      case (#Quoted) { [#Confirmed, #Cancelled, #Expired] };
      case (#Confirmed) { [#Deposited, #Cancelled, #Expired] };
      case (#Deposited) { [#Fulfilled, #Cancelled, #Expired] };
      case (#Fulfilled) { [] };
      case (#Cancelled) { [] };
      case (#Expired) { [] };
    }
  };

  /// Check if status is terminal
  public func isTerminal(status : IntentStatus) : Bool {
    switch (status) {
      case (#Fulfilled) { true };
      case (#Cancelled) { true };
      case (#Expired) { true };
      case (_) { false };
    }
  };
}
