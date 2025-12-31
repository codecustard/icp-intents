/// Chain verification registry and interface
///
/// Provides pluggable architecture for different blockchain verifiers

import ChainTypes "./ChainTypes";
import Types "../core/Types";
import Errors "../core/Errors";
import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";

module {
  type Chain = ChainTypes.Chain;
  type VerificationRequest = ChainTypes.VerificationRequest;
  type VerificationResult = ChainTypes.VerificationResult;
  type AddressContext = ChainTypes.AddressContext;
  type IntentResult<T> = Types.IntentResult<T>;
  type IntentError = Types.IntentError;

  /// Chain verifier interface
  public type ChainVerifier = {
    /// Verify a deposit on this chain
    verify : (VerificationRequest) -> async VerificationResult;

    /// Generate deposit address for this chain
    generateAddress : (AddressContext, tecdsa_key_name : Text) -> async IntentResult<Text>;

    /// Build and sign transaction for this chain (for reverse flow)
    buildTransaction : (
      utxo : Types.UTXO,
      recipient : Text,
      amount : Nat,
      intent_id : Nat,
      key_name : Text
    ) -> async IntentResult<Blob>;

    /// Broadcast transaction to this chain
    broadcast : (signed_tx : Blob, rpc_url : ?Text) -> async IntentResult<Text>;
  };

  /// Registry state
  public type RegistryState = {
    var chains : HashMap.HashMap<Text, Chain>;
    var verifiers : HashMap.HashMap<Text, Principal>; // chain_name -> verifier_canister
  };

  /// Stable storage format
  public type StableRegistryData = {
    chains : [(Text, Chain)];
    verifiers : [(Text, Principal)];
  };

  /// Initialize registry
  public func init() : RegistryState {
    {
      var chains = HashMap.HashMap<Text, Chain>(10, Text.equal, Text.hash);
      var verifiers = HashMap.HashMap<Text, Principal>(10, Text.equal, Text.hash);
    }
  };

  /// Register a chain
  public func registerChain(
    state : RegistryState,
    name : Text,
    chain : Chain
  ) {
    state.chains.put(Text.toLowercase(name), chain);
    Debug.print("ChainRegistry: Registered chain: " # name);
  };

  /// Register external verifier canister
  public func registerVerifier(
    state : RegistryState,
    chain_name : Text,
    verifier : Principal
  ) {
    state.verifiers.put(Text.toLowercase(chain_name), verifier);
    Debug.print("ChainRegistry: Registered verifier for " # chain_name);
  };

  /// Get chain configuration
  public func getChain(state : RegistryState, name : Text) : ?Chain {
    state.chains.get(Text.toLowercase(name))
  };

  /// Check if chain is supported
  public func isSupported(state : RegistryState, name : Text) : Bool {
    switch (state.chains.get(Text.toLowercase(name))) {
      case null { false };
      case (?_) { true };
    }
  };

  /// Get verifier for chain
  public func getVerifier(state : RegistryState, chain_name : Text) : ?Principal {
    state.verifiers.get(Text.toLowercase(chain_name))
  };

  /// List all supported chains
  public func listChains(state : RegistryState) : [Text] {
    Iter.toArray(state.chains.keys())
  };

  /// Get chain by spec
  public func getChainBySpec(
    state : RegistryState,
    spec : Types.ChainSpec
  ) : ?Chain {
    // First try exact match
    switch (getChain(state, spec.chain)) {
      case (?chain) { ?chain };
      case null {
        // Try matching by chain_id for EVM chains
        switch (spec.chain_id) {
          case (?id) {
            // Search all chains for matching EVM chain_id
            for ((name, chain) in state.chains.entries()) {
              switch (chain) {
                case (#EVM(evm)) {
                  if (evm.chain_id == id) {
                    return ?chain;
                  };
                };
                case (_) {};
              };
            };
            null
          };
          case null { null };
        }
      };
    }
  };

  /// Validate chain specification
  public func validateSpec(
    state : RegistryState,
    spec : Types.ChainSpec
  ) : IntentResult<Chain> {
    switch (getChainBySpec(state, spec)) {
      case null {
        #err(#ChainNotSupported(spec.chain))
      };
      case (?chain) {
        // Additional validation based on chain type
        switch (chain) {
          case (#EVM(evm)) {
            // Verify chain_id matches if provided
            switch (spec.chain_id) {
              case (?id) {
                if (id != evm.chain_id) {
                  return #err(#InvalidChain("Chain ID mismatch"));
                };
              };
              case null {};
            };
          };
          case (_) {};
        };
        #ok(chain)
      };
    }
  };

  /// Export state for upgrade
  public func toStable(state : RegistryState) : StableRegistryData {
    {
      chains = Iter.toArray(state.chains.entries());
      verifiers = Iter.toArray(state.verifiers.entries());
    }
  };

  /// Import state from upgrade
  public func fromStable(data : StableRegistryData) : RegistryState {
    let state = init();

    for ((name, chain) in data.chains.vals()) {
      state.chains.put(name, chain);
    };

    for ((name, verifier) in data.verifiers.vals()) {
      state.verifiers.put(name, verifier);
    };

    state
  };
}
