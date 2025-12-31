/// Chain-specific types and abstractions
///
/// Provides a pluggable architecture for different blockchain types

import Principal "mo:base/Principal";
import Blob "mo:base/Blob";

module {
  /// Unified chain identifier supporting multiple blockchain types
  public type Chain = {
    #EVM : EVMChain;
    #Hoosat : HoosatChain;
    #Bitcoin : BitcoinChain;
    #Custom : CustomChain;
  };

  /// EVM-compatible chain configuration
  public type EVMChain = {
    chain_id : Nat;
    name : Text; // e.g., "ethereum", "base", "sepolia"
    network : Text; // "mainnet" or "testnet"
    rpc_urls : ?[Text]; // Optional custom RPC URLs
  };

  /// Hoosat UTXO chain configuration
  public type HoosatChain = {
    network : Text; // "mainnet" or "testnet"
    rpc_url : Text; // Hoosat API endpoint
    min_confirmations : Nat; // Required confirmations
  };

  /// Bitcoin UTXO chain configuration (future support)
  public type BitcoinChain = {
    network : Text; // "mainnet" or "testnet"
    min_confirmations : Nat;
  };

  /// Custom chain for future extensibility
  public type CustomChain = {
    name : Text;
    network : Text;
    verification_canister : ?Principal; // Optional external verifier
    metadata : ?Text; // JSON config
  };

  /// Chain specification for intent creation
  public type ChainSpec = {
    chain : Text; // Chain name (e.g., "ethereum", "hoosat", "bitcoin")
    chain_id : ?Nat; // For EVM chains
    token : Text; // Token symbol or address
    network : Text; // "mainnet" or "testnet"
  };

  /// Verification proof types
  public type VerificationProof = {
    #EVM : EVMProof;
    #UTXO : UTXOProof;
    #Custom : CustomProof;
  };

  /// EVM transaction proof
  public type EVMProof = {
    tx_hash : Text;
    block_number : Nat;
    from_address : Text;
    to_address : Text;
    value : Nat;
    confirmations : Nat;
  };

  /// UTXO transaction proof (Bitcoin, Hoosat, etc.)
  public type UTXOProof = {
    tx_id : Text;
    output_index : Nat;
    amount : Nat;
    script_pubkey : Blob;
    address : Text;
    confirmations : Nat;
  };

  /// Custom proof for extensibility
  public type CustomProof = {
    proof_type : Text;
    data : Blob;
  };

  /// Verification request
  public type VerificationRequest = {
    chain : Chain;
    expected_address : Text;
    expected_amount : Nat;
    proof : VerificationProof;
    custom_rpc_urls : ?[Text];
  };

  /// Verification result
  public type VerificationResult = {
    #Success : {
      verified_amount : Nat;
      tx_hash : Text;
      confirmations : Nat;
      timestamp : Int;
    };
    #Failed : Text;
    #Pending : {
      current_confirmations : Nat;
      required_confirmations : Nat;
    };
  };

  /// Address derivation context
  public type AddressContext = {
    chain : Chain;
    intent_id : Nat;
    user : Principal;
  };

  /// Helper functions

  /// Get chain identifier string
  public func chainToText(chain : Chain) : Text {
    switch (chain) {
      case (#EVM(evm)) { evm.name # ":" # debug_show(evm.chain_id) };
      case (#Hoosat(h)) { "hoosat:" # h.network };
      case (#Bitcoin(b)) { "bitcoin:" # b.network };
      case (#Custom(c)) { c.name # ":" # c.network };
    }
  };

  /// Get network from chain
  public func getNetwork(chain : Chain) : Text {
    switch (chain) {
      case (#EVM(evm)) { evm.network };
      case (#Hoosat(h)) { h.network };
      case (#Bitcoin(b)) { b.network };
      case (#Custom(c)) { c.network };
    }
  };

  /// Check if chain is UTXO-based
  public func isUTXOChain(chain : Chain) : Bool {
    switch (chain) {
      case (#Hoosat(_)) { true };
      case (#Bitcoin(_)) { true };
      case (_) { false };
    }
  };

  /// Check if chain is EVM-based
  public func isEVMChain(chain : Chain) : Bool {
    switch (chain) {
      case (#EVM(_)) { true };
      case (_) { false };
    }
  };
}
