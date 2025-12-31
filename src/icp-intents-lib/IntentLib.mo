/// ICP Intents SDK - Main Entry Point
///
/// Production-grade cross-chain intent system with:
/// - Multi-chain support (EVM, Bitcoin, Hoosat, Custom)
/// - State machine-based intent lifecycle
/// - Multi-token escrow with invariants
/// - Protocol and solver fees
/// - Threshold ECDSA for address generation
/// - Comprehensive error handling

import Time "mo:base/Time";
import Principal "mo:base/Principal";
import Types "./core/Types";
import State "./core/State";
import Errors "./core/Errors";
import Events "./core/Events";
import ChainTypes "./chains/ChainTypes";
import ChainRegistry "./chains/ChainRegistry";
import TECDSA "./crypto/TECDSA";
import EVM "./chains/EVM";
import Hoosat "./chains/Hoosat";
import IntentManager "./managers/IntentManager";
import Escrow "./managers/Escrow";
import FeeManager "./managers/FeeManager";
import Validation "./utils/Validation";
import Math "./utils/Math";
import Cycles "./utils/Cycles";

module {
  // Re-export core types for SDK users
  public type Intent = Types.Intent;
  public type Quote = Types.Quote;
  public type IntentStatus = Types.IntentStatus;
  public type IntentResult<T> = Types.IntentResult<T>;
  public type IntentError = Types.IntentError;
  public type SystemConfig = Types.SystemConfig;
  public type ChainSpec = Types.ChainSpec;
  public type FeeBreakdown = Types.FeeBreakdown;
  public type UTXO = Types.UTXO;

  // Re-export chain types
  public type Chain = ChainTypes.Chain;
  public type EVMChain = ChainTypes.EVMChain;
  public type HoosatChain = ChainTypes.HoosatChain;
  public type BitcoinChain = ChainTypes.BitcoinChain;
  public type CustomChain = ChainTypes.CustomChain;
  public type VerificationRequest = ChainTypes.VerificationRequest;
  public type VerificationResult = ChainTypes.VerificationResult;
  public type VerificationProof = ChainTypes.VerificationProof;
  public type AddressContext = ChainTypes.AddressContext;

  // Re-export manager types
  public type ManagerState = IntentManager.ManagerState;
  public type StableManagerData = IntentManager.StableManagerData;

  // Re-export utilities
  public let { MAX_BPS; calculateBps; applySlippage; bpsToPercent } = Math;
  public let { balance; checkHealth; hasSufficientCycles } = Cycles;

  /// Initialize the SDK with configuration
  public func init(config : SystemConfig) : ManagerState {
    IntentManager.init(config)
  };

  /// Create a new intent
  public func createIntent(
    state : ManagerState,
    user : Principal,
    source : ChainSpec,
    destination : ChainSpec,
    source_amount : Nat,
    min_output : Nat,
    dest_recipient : Text,
    deadline : Time.Time,
    current_time : Time.Time
  ) : IntentResult<Nat> {
    IntentManager.createIntent(
      state,
      user,
      source,
      destination,
      source_amount,
      min_output,
      dest_recipient,
      deadline,
      current_time
    )
  };

  /// Submit a quote for an intent
  public func submitQuote(
    state : ManagerState,
    intent_id : Nat,
    solver : Principal,
    output_amount : Nat,
    fee : Nat,
    solver_tip : Nat,
    solver_dest_address : ?Text,
    current_time : Time.Time
  ) : IntentResult<()> {
    IntentManager.submitQuote(
      state,
      intent_id,
      solver,
      output_amount,
      fee,
      solver_tip,
      solver_dest_address,
      current_time
    )
  };

  /// Confirm a quote
  public func confirmQuote(
    state : ManagerState,
    intent_id : Nat,
    solver : Principal,
    user : Principal,
    current_time : Time.Time
  ) : IntentResult<()> {
    IntentManager.confirmQuote(state, intent_id, solver, user, current_time)
  };

  /// Verify deposit and mark intent as deposited
  public func verifyAndMarkDeposited(
    state : ManagerState,
    intent_id : Nat,
    verified_amount : Nat,
    current_time : Time.Time
  ) : IntentResult<()> {
    IntentManager.markDeposited(state, intent_id, verified_amount, current_time)
  };

  /// Fulfill an intent
  public func fulfillIntent(
    state : ManagerState,
    intent_id : Nat,
    current_time : Time.Time
  ) : IntentResult<FeeBreakdown> {
    IntentManager.fulfillIntent(state, intent_id, current_time)
  };

  /// Cancel an intent
  public func cancelIntent(
    state : ManagerState,
    intent_id : Nat,
    user : Principal,
    current_time : Time.Time
  ) : IntentResult<()> {
    IntentManager.cancelIntent(state, intent_id, user, current_time)
  };

  /// Get intent by ID
  public func getIntent(state : ManagerState, id : Nat) : ?Intent {
    IntentManager.getIntent(state, id)
  };

  /// Get user's intents
  public func getUserIntents(state : ManagerState, user : Principal) : [Intent] {
    IntentManager.getUserIntents(state, user)
  };

  // Chain Registry Functions

  /// Register a supported chain
  public func registerChain(state : ManagerState, name : Text, chain : Chain) {
    ChainRegistry.registerChain(state.chain_registry, name, chain)
  };

  /// Register external verifier canister
  public func registerVerifier(state : ManagerState, chain_name : Text, verifier : Principal) {
    ChainRegistry.registerVerifier(state.chain_registry, chain_name, verifier)
  };

  /// Check if chain is supported
  public func isChainSupported(state : ManagerState, name : Text) : Bool {
    ChainRegistry.isSupported(state.chain_registry, name)
  };

  /// Get chain configuration
  public func getChain(state : ManagerState, name : Text) : ?Chain {
    ChainRegistry.getChain(state.chain_registry, name)
  };

  /// List all supported chains
  public func listChains(state : ManagerState) : [Text] {
    ChainRegistry.listChains(state.chain_registry)
  };

  // Escrow Functions

  /// Get user's escrow balance for a token
  public func getEscrowBalance(state : ManagerState, user : Principal, token : Text) : Nat {
    Escrow.getBalance(state.escrow, user, token)
  };

  /// Get total locked for a token
  public func getTotalLocked(state : ManagerState, token : Text) : Nat {
    Escrow.getTotalLocked(state.escrow, token)
  };

  /// Verify escrow invariants
  public func verifyEscrowInvariants(state : ManagerState) : Bool {
    Escrow.verifyInvariants(state.escrow)
  };

  // Fee Manager Functions

  /// Calculate fee breakdown for a quote
  public func calculateFees(
    output_amount : Nat,
    protocol_fee_bps : Nat,
    quote : Quote
  ) : FeeBreakdown {
    FeeManager.calculateFees(output_amount, protocol_fee_bps, quote)
  };

  /// Get collected protocol fees for a token
  public func getCollectedFees(state : ManagerState, token : Text) : Nat {
    FeeManager.getCollectedFees(state.fee_manager, token)
  };

  /// Get all collected fees
  public func getAllCollectedFees(state : ManagerState) : [(Text, Nat)] {
    FeeManager.getAllCollectedFees(state.fee_manager)
  };

  // Stable Storage Functions

  /// Export state for upgrade
  public func toStable(state : ManagerState) : StableManagerData {
    IntentManager.toStable(state)
  };

  /// Import state from upgrade
  public func fromStable(data : StableManagerData, config : SystemConfig) : ManagerState {
    IntentManager.fromStable(data, config)
  };

  // Helper Functions

  /// Check if intent is expired
  public func isExpired(intent : Intent, current_time : Time.Time) : Bool {
    Types.isExpired(intent, current_time)
  };

  /// Check if intent can receive quotes
  public func canReceiveQuotes(intent : Intent) : Bool {
    Types.canReceiveQuotes(intent)
  };

  /// Check if intent can be confirmed
  public func canBeConfirmed(intent : Intent) : Bool {
    Types.canBeConfirmed(intent)
  };

  /// Check if intent is in terminal state
  public func isTerminal(intent : Intent) : Bool {
    Types.isTerminal(intent)
  };

  /// Convert error to text
  public func errorToText(error : IntentError) : Text {
    Errors.errorToText(error)
  };

  /// Check if error is retryable
  public func isRetryable(error : IntentError) : Bool {
    Errors.isRetryable(error)
  };

  /// Check if error is terminal
  public func isErrorTerminal(error : IntentError) : Bool {
    Errors.isTerminal(error)
  };

  // Chain-specific modules (for advanced use cases)
  public let EVMModule = EVM;
  public let HoosatModule = Hoosat;
  public let TECDSAModule = TECDSA;
  public let ChainRegistryModule = ChainRegistry;
  public let ValidationModule = Validation;
  public let StateModule = State;
}
