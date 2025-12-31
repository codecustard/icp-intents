/// Token Ledger Registry
///
/// Maps token symbols to their ICRC ledger principals

import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Text "mo:base/Text";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";

module {
  /// Token ledger information
  public type TokenLedger = {
    symbol : Text; // Token symbol (e.g., "ICP", "ckBTC")
    ledger_principal : Principal; // ICRC ledger canister
    decimals : Nat8; // Token decimals
    fee : Nat; // Transfer fee in base units
  };

  /// Registry state
  public type RegistryState = {
    var ledgers : HashMap.HashMap<Text, TokenLedger>;
  };

  /// Stable storage format
  public type StableRegistryData = {
    ledgers : [(Text, TokenLedger)];
  };

  /// Initialize empty registry
  public func init() : RegistryState {
    {
      var ledgers = HashMap.HashMap<Text, TokenLedger>(10, Text.equal, Text.hash);
    }
  };

  /// Register a token ledger
  public func registerToken(
    state : RegistryState,
    symbol : Text,
    ledger_principal : Principal,
    decimals : Nat8,
    fee : Nat
  ) {
    let ledger : TokenLedger = {
      symbol = symbol;
      ledger_principal = ledger_principal;
      decimals = decimals;
      fee = fee;
    };

    state.ledgers.put(symbol, ledger);
    Debug.print("TokenRegistry: Registered token " # symbol # " -> " # Principal.toText(ledger_principal));
  };

  /// Get ledger principal for a token symbol
  public func getLedger(state : RegistryState, symbol : Text) : ?Principal {
    switch (state.ledgers.get(symbol)) {
      case null { null };
      case (?ledger) { ?ledger.ledger_principal };
    }
  };

  /// Get full token info
  public func getTokenInfo(state : RegistryState, symbol : Text) : ?TokenLedger {
    state.ledgers.get(symbol)
  };

  /// Check if token is registered
  public func isRegistered(state : RegistryState, symbol : Text) : Bool {
    switch (state.ledgers.get(symbol)) {
      case null { false };
      case (?_) { true };
    }
  };

  /// List all registered tokens
  public func listTokens(state : RegistryState) : [Text] {
    Iter.toArray(Iter.map(state.ledgers.entries(), func ((symbol, _) : (Text, TokenLedger)) : Text { symbol }))
  };

  /// Export for upgrades
  public func toStable(state : RegistryState) : StableRegistryData {
    {
      ledgers = Iter.toArray(state.ledgers.entries());
    }
  };

  /// Import from upgrades
  public func fromStable(data : StableRegistryData) : RegistryState {
    let ledgers_map = HashMap.HashMap<Text, TokenLedger>(10, Text.equal, Text.hash);
    for ((symbol, ledger) in data.ledgers.vals()) {
      ledgers_map.put(symbol, ledger);
    };

    {
      var ledgers = ledgers_map;
    }
  };
}
