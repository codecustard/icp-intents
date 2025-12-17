/// Escrow management for ICP and ICRC-1 tokens.
/// This module can be used standalone or integrated into the intent system.
///
/// Example usage in a DEX:
/// ```motoko
/// import Escrow "mo:icp-intents/Escrow";
/// import Types "mo:icp-intents/Types";
///
/// stable var escrowState = Escrow.init();
///
/// // In your canister
/// public shared(msg) func deposit(amount: Nat, token: Text) : async Types.IntentResult<()> {
///   await Escrow.deposit(escrowState, msg.caller, token, amount);
/// };
/// ```

import Principal "mo:base/Principal";
import Result "mo:base/Result";
import HashMap "mo:base/HashMap";
import Hash "mo:base/Hash";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Types "../icp-intents-lib/Types";
import Utils "../icp-intents-lib/Utils";

module {
  type IntentResult<T> = Types.IntentResult<T>;
  type IntentError = Types.IntentError;
  type EscrowAccount = Types.EscrowAccount;

  /// Escrow state (store in stable var)
  public type State = {
    accounts: HashMap.HashMap<(Principal, Text), EscrowAccount>;
  };

  /// Initialize escrow state
  public func init() : State {
    {
      accounts = HashMap.HashMap<(Principal, Text), EscrowAccount>(
        10,
        func(a: (Principal, Text), b: (Principal, Text)) : Bool {
          Principal.equal(a.0, b.0) and Text.equal(a.1, b.1)
        },
        func(a: (Principal, Text)) : Hash.Hash {
          let p1 = Principal.hash(a.0);
          let p2 = Text.hash(a.1);
          p1 ^ p2
        }
      );
    }
  };

  /// Get or create escrow account
  public func getOrCreateAccount(
    state: State,
    owner: Principal,
    token: Text
  ) : EscrowAccount {
    let key = (owner, token);
    switch (state.accounts.get(key)) {
      case (?account) account;
      case null {
        let newAccount : EscrowAccount = {
          owner = owner;
          token = token;
          balance = 0;
          locked = 0;
          available = 0;
        };
        state.accounts.put(key, newAccount);
        newAccount
      };
    }
  };

  /// Deposit funds into escrow (from user)
  /// In production, this should be integrated with:
  /// - ICP ledger transfers (for "ICP")
  /// - ICRC-1 transfers (for ICRC tokens)
  public func deposit(
    state: State,
    owner: Principal,
    token: Text,
    amount: Nat
  ) : IntentResult<()> {
    if (amount == 0) {
      return #err(#InvalidAmount);
    };

    if (not Utils.isValidTokenId(token)) {
      return #err(#InvalidToken);
    };

    let account = getOrCreateAccount(state, owner, token);
    let newBalance = account.balance + amount;
    let newAvailable = newBalance - account.locked;

    let updated : EscrowAccount = {
      owner = account.owner;
      token = account.token;
      balance = newBalance;
      locked = account.locked;
      available = newAvailable;
    };

    state.accounts.put((owner, token), updated);
    #ok(())
  };

  /// Lock funds for an intent
  public func lock(
    state: State,
    owner: Principal,
    token: Text,
    amount: Nat
  ) : IntentResult<()> {
    if (amount == 0) {
      return #err(#InvalidAmount);
    };

    let account = getOrCreateAccount(state, owner, token);

    if (account.available < amount) {
      return #err(#InsufficientBalance);
    };

    let newLocked = account.locked + amount;
    let newAvailable = account.balance - newLocked;

    let updated : EscrowAccount = {
      owner = account.owner;
      token = account.token;
      balance = account.balance;
      locked = newLocked;
      available = newAvailable;
    };

    state.accounts.put((owner, token), updated);
    #ok(())
  };

  /// Unlock funds (e.g., on intent cancellation)
  public func unlock(
    state: State,
    owner: Principal,
    token: Text,
    amount: Nat
  ) : IntentResult<()> {
    let account = getOrCreateAccount(state, owner, token);

    if (account.locked < amount) {
      return #err(#InternalError("Unlock amount exceeds locked balance"));
    };

    let newLocked = Utils.safeSub(account.locked, amount);
    let newAvailable = account.balance - newLocked;

    let updated : EscrowAccount = {
      owner = account.owner;
      token = account.token;
      balance = account.balance;
      locked = newLocked;
      available = newAvailable;
    };

    state.accounts.put((owner, token), updated);
    #ok(())
  };

  /// Release locked funds (transfer out of escrow)
  /// This deducts from both balance and locked
  /// Returns the released amount
  public func release(
    state: State,
    owner: Principal,
    token: Text,
    amount: Nat
  ) : IntentResult<Nat> {
    let account = getOrCreateAccount(state, owner, token);

    if (account.locked < amount) {
      return #err(#InsufficientBalance);
    };

    if (account.balance < amount) {
      return #err(#InternalError("Balance < locked (invariant violated)"));
    };

    let newBalance = account.balance - amount;
    let newLocked = account.locked - amount;
    let newAvailable = newBalance - newLocked;

    let updated : EscrowAccount = {
      owner = account.owner;
      token = account.token;
      balance = newBalance;
      locked = newLocked;
      available = newAvailable;
    };

    state.accounts.put((owner, token), updated);
    #ok(amount)
  };

  /// Get account balance
  public func getBalance(
    state: State,
    owner: Principal,
    token: Text
  ) : EscrowAccount {
    getOrCreateAccount(state, owner, token)
  };

  /// Withdraw available funds (not locked)
  public func withdraw(
    state: State,
    owner: Principal,
    token: Text,
    amount: Nat
  ) : IntentResult<Nat> {
    let account = getOrCreateAccount(state, owner, token);

    if (account.available < amount) {
      return #err(#InsufficientBalance);
    };

    let newBalance = account.balance - amount;
    let newAvailable = newBalance - account.locked;

    let updated : EscrowAccount = {
      owner = account.owner;
      token = account.token;
      balance = newBalance;
      locked = account.locked;
      available = newAvailable;
    };

    state.accounts.put((owner, token), updated);
    #ok(amount)
  };

  /// Get all accounts for a user (for queries)
  public func getUserAccounts(
    state: State,
    owner: Principal
  ) : [EscrowAccount] {
    let entries = Iter.toArray(state.accounts.entries());
    let filtered = Iter.toArray(
      Iter.filter<((Principal, Text), EscrowAccount)>(
        entries.vals(),
        func(entry) { Principal.equal(entry.0.0, owner) }
      )
    );
    Array.map<((Principal, Text), EscrowAccount), EscrowAccount>(
      filtered,
      func(entry) { entry.1 }
    )
  };

  /// Pre-upgrade: Serialize state
  public func preUpgrade(state: State) : [(Principal, Text, EscrowAccount)] {
    let entries = Iter.toArray(state.accounts.entries());
    Array.map<((Principal, Text), EscrowAccount), (Principal, Text, EscrowAccount)>(
      entries,
      func(entry) {
        (entry.0.0, entry.0.1, entry.1)
      }
    )
  };

  /// Post-upgrade: Restore state
  public func postUpgrade(
    data: [(Principal, Text, EscrowAccount)]
  ) : State {
    let state = init();
    for ((owner, token, account) in data.vals()) {
      state.accounts.put((owner, token), account);
    };
    state
  };
}
