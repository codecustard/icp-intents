/// Core types for the intent system
///
/// Defines the main data structures for intents, quotes, and system state

import Time "mo:base/Time";
import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import ChainTypes "../chains/ChainTypes";
import Errors "./Errors";

module {
  // Re-export commonly used types
  public type IntentResult<T> = Errors.IntentResult<T>;
  public type IntentError = Errors.IntentError;
  public type Chain = ChainTypes.Chain;
  public type ChainSpec = ChainTypes.ChainSpec;
  public type VerificationProof = ChainTypes.VerificationProof;

  /// Intent status following strict state machine
  public type IntentStatus = {
    #PendingQuote; // Intent created, awaiting quotes
    #Quoted; // At least one quote submitted
    #Confirmed; // User selected a quote, awaiting deposit
    #Deposited; // Deposit verified, awaiting fulfillment
    #Fulfilled; // Intent completed successfully
    #Cancelled; // Cancelled by user or system
    #Expired; // Past deadline without fulfillment
  };

  /// Core intent structure
  public type Intent = {
    id : Nat;
    user : Principal;

    // Chain specifications
    source : ChainSpec;
    destination : ChainSpec;

    // Amounts
    source_amount : Nat;
    min_output : Nat; // Minimum acceptable output amount

    // Recipient
    dest_recipient : Text; // Destination address/principal

    // Timing
    created_at : Time.Time;
    deadline : Time.Time;
    verified_at : ?Time.Time;

    // Status tracking
    status : IntentStatus;

    // Quote management
    quotes : [Quote];
    selected_quote : ?Quote;

    // Escrow tracking
    escrow_balance : Nat;

    // Deposit tracking
    generated_address : ?Text; // For UTXO chains or solver deposits
    deposited_utxo : ?UTXO; // For UTXO source chains
    solver_tx_hash : ?Text; // Solver's deposit transaction

    // Configuration
    protocol_fee_bps : Nat; // Basis points (e.g., 30 = 0.3%)
    custom_rpc_urls : ?[Text];
    verification_hints : ?Text; // JSON metadata for verification
    metadata : ?Text; // Additional user metadata
  };

  /// Solver quote for an intent
  public type Quote = {
    solver : Principal;
    output_amount : Nat; // Amount solver will provide
    fee : Nat; // Solver's fee
    solver_tip : Nat; // Optional additional tip to solver
    expiry : Time.Time; // Quote expiration
    submitted_at : Time.Time;
    solver_dest_address : ?Text; // Where solver receives source tokens
  };

  /// Request to post a new intent
  public type PostIntentRequest = {
    source : ChainSpec;
    destination : ChainSpec;
    dest_recipient : Text;
    source_amount : Nat;
    min_output : Nat;
    deadline : Time.Time;
    custom_rpc_urls : ?[Text];
    verification_hints : ?Text;
    metadata : ?Text;
  };

  /// Request to submit a quote
  public type SubmitQuoteRequest = {
    intent_id : Nat;
    output_amount : Nat;
    fee : Nat;
    solver_tip : ?Nat;
    expiry : Time.Time;
    solver_dest_address : ?Text;
  };

  /// UTXO representation for Bitcoin-like chains
  public type UTXO = {
    tx_id : Text;
    output_index : Nat;
    amount : Nat;
    script_pubkey : Blob;
    address : Text;
  };

  /// Token configuration
  public type TokenConfig = {
    symbol : Text;
    ledger_principal : Principal;
    decimals : Nat8;
  };

  /// System configuration
  public type SystemConfig = {
    protocol_fee_bps : Nat; // Default protocol fee
    fee_collector : Principal;
    supported_chains : [Chain];
    min_intent_amount : Nat;
    max_intent_amount : Nat;
    default_deadline_duration : Int; // Nanoseconds
    solver_allowlist : ?[Principal]; // None = permissionless
  };

  /// Intent state for storage
  public type IntentState = {
    intents : [(Nat, Intent)];
    next_intent_id : Nat;
    config : SystemConfig;
  };

  /// Escrow balance tracking
  public type EscrowBalance = {
    user : Principal;
    token : Text;
    locked : Nat;
    available : Nat;
  };

  /// Fee breakdown
  public type FeeBreakdown = {
    protocol_fee : Nat;
    solver_fee : Nat;
    solver_tip : Nat;
    total_fees : Nat;
    net_output : Nat;
  };

  /// Intent statistics
  public type IntentStats = {
    total_intents : Nat;
    pending_intents : Nat;
    fulfilled_intents : Nat;
    cancelled_intents : Nat;
    expired_intents : Nat;
    total_volume : Nat; // Sum of all fulfilled amounts
    total_fees_collected : Nat;
  };

  /// Helper functions

  /// Check if intent can receive quotes
  public func canReceiveQuotes(intent : Intent) : Bool {
    switch (intent.status) {
      case (#PendingQuote) { true };
      case (#Quoted) { true };
      case (_) { false };
    }
  };

  /// Check if intent can be confirmed
  public func canBeConfirmed(intent : Intent) : Bool {
    switch (intent.status) {
      case (#Quoted) { true };
      case (_) { false };
    }
  };

  /// Check if intent is expired
  public func isExpired(intent : Intent, currentTime : Time.Time) : Bool {
    currentTime > intent.deadline and intent.status != #Fulfilled
  };

  /// Check if intent is terminal
  public func isTerminal(intent : Intent) : Bool {
    switch (intent.status) {
      case (#Fulfilled) { true };
      case (#Cancelled) { true };
      case (#Expired) { true };
      case (_) { false };
    }
  };

  /// Get active intents (non-terminal)
  public func isActive(intent : Intent) : Bool {
    not isTerminal(intent)
  };
}
