/// Multi-token escrow manager with invariant enforcement
///
/// Manages locked funds across multiple tokens with upgrade safety

import Types "../core/Types";
import Errors "../core/Errors";
import HashMap "mo:base/HashMap";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Array "mo:base/Array";

module {
  type IntentResult<T> = Types.IntentResult<T>;
  type IntentError = Types.IntentError;
  type EscrowBalance = Types.EscrowBalance;

  /// Composite key for user-token pairs
  type EscrowKey = Text;

  /// Escrow state for stable storage
  public type EscrowState = {
    var balances : HashMap.HashMap<Text, Nat>; // key -> amount
    var total_locked : HashMap.HashMap<Text, Nat>; // token -> total
  };

  /// Stable storage format
  public type StableEscrowData = {
    balances : [(Text, Nat)];
    total_locked : [(Text, Nat)];
  };

  /// Initialize escrow state
  public func init() : EscrowState {
    {
      var balances = HashMap.HashMap<Text, Nat>(100, Text.equal, Text.hash);
      var total_locked = HashMap.HashMap<Text, Nat>(20, Text.equal, Text.hash);
    }
  };

  /// Create escrow key
  func makeKey(user : Principal, token : Text) : Text {
    Principal.toText(user) # ":" # token
  };

  /// Lock funds in escrow
  ///
  /// Records that a user has deposited funds that should be held in escrow.
  /// This is internal accounting only - actual token transfers happen separately.
  ///
  /// **Security**: Validates amount > 0. Updates both user balance and total locked
  /// for the token to maintain invariants.
  ///
  /// Parameters:
  /// - `state`: The escrow state
  /// - `user`: Principal of the user locking funds
  /// - `token`: Token symbol (e.g., "ICP", "ckBTC")
  /// - `amount`: Amount to lock in token's base units
  ///
  /// Returns:
  /// - `#ok(())` on success
  /// - `#err(#InvalidAmount)` if amount is zero
  public func lock(
    state : EscrowState,
    user : Principal,
    token : Text,
    amount : Nat
  ) : IntentResult<()> {
    if (amount == 0) {
      return #err(#InvalidAmount("Cannot lock zero amount"));
    };

    let key = makeKey(user, token);

    // Get current balance
    let currentBalance = switch (state.balances.get(key)) {
      case null { 0 };
      case (?bal) { bal };
    };

    // Lock the amount
    let newBalance = currentBalance + amount;
    state.balances.put(key, newBalance);

    // Update total locked for token
    let currentTotal = switch (state.total_locked.get(token)) {
      case null { 0 };
      case (?total) { total };
    };
    state.total_locked.put(token, currentTotal + amount);

    Debug.print("Escrow: Locked " # Nat.toText(amount) # " " # token # " for " # Principal.toText(user));
    #ok(())
  };

  /// Release funds from escrow
  public func release(
    state : EscrowState,
    user : Principal,
    token : Text,
    amount : Nat
  ) : IntentResult<()> {
    if (amount == 0) {
      return #ok(()); // Nothing to release
    };

    let key = makeKey(user, token);

    // Get current balance
    let currentBalance = switch (state.balances.get(key)) {
      case null {
        return #err(#InsufficientBalance);
      };
      case (?bal) { bal };
    };

    // Check sufficient balance
    if (currentBalance < amount) {
      return #err(#InsufficientBalance);
    };

    // Release the amount (safe: checked above)
    let newBalance = Nat.sub(currentBalance, amount);
    if (newBalance == 0) {
      state.balances.delete(key);
    } else {
      state.balances.put(key, newBalance);
    };

    // Update total locked for token
    let currentTotal = switch (state.total_locked.get(token)) {
      case null { 0 };
      case (?total) { total };
    };

    if (currentTotal >= amount) {
      let newTotal = Nat.sub(currentTotal, amount);
      if (newTotal == 0) {
        state.total_locked.delete(token);
      } else {
        state.total_locked.put(token, newTotal);
      };
    };

    Debug.print("Escrow: Released " # Nat.toText(amount) # " " # token # " for " # Principal.toText(user));
    #ok(())
  };

  /// Get user's locked balance for a token
  public func getBalance(
    state : EscrowState,
    user : Principal,
    token : Text
  ) : Nat {
    let key = makeKey(user, token);
    switch (state.balances.get(key)) {
      case null { 0 };
      case (?bal) { bal };
    }
  };

  /// Get total locked for a token across all users
  public func getTotalLocked(state : EscrowState, token : Text) : Nat {
    switch (state.total_locked.get(token)) {
      case null { 0 };
      case (?total) { total };
    }
  };

  /// Verify escrow invariants (for upgrade safety)
  public func verifyInvariants(state : EscrowState) : Bool {
    // Verify that total_locked matches sum of individual balances
    for ((token, expectedTotal) in state.total_locked.entries()) {
      var actualTotal : Nat = 0;
      for ((key, amount) in state.balances.entries()) {
        let parts = Iter.toArray(Text.split(key, #char ':'));
        if (parts.size() == 2 and parts[1] == token) {
          actualTotal += amount;
        };
      };

      if (actualTotal != expectedTotal) {
        Debug.print("⚠️ Escrow invariant violated for " # token #
                    ": expected " # Nat.toText(expectedTotal) #
                    ", got " # Nat.toText(actualTotal));
        return false;
      };
    };
    true
  };

  /// Export escrow state for upgrade
  public func toStable(state : EscrowState) : StableEscrowData {
    {
      balances = Iter.toArray(state.balances.entries());
      total_locked = Iter.toArray(state.total_locked.entries());
    }
  };

  /// Import escrow state from upgrade
  public func fromStable(data : StableEscrowData) : EscrowState {
    let state = init();

    for ((key, amount) in data.balances.vals()) {
      state.balances.put(key, amount);
    };

    for ((token, total) in data.total_locked.vals()) {
      state.total_locked.put(token, total);
    };

    // Verify invariants after restore
    if (not verifyInvariants(state)) {
      Debug.print("⚠️ WARNING: Escrow invariants violated after restore!");
    };

    state
  };
}
