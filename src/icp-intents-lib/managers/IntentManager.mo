/// Intent lifecycle management
///
/// Orchestrates intent creation, quote submission, verification, and fulfillment

import Time "mo:base/Time";
import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Hash "mo:base/Hash";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Types "../core/Types";
import State "../core/State";
import Events "../core/Events";
import ChainRegistry "../chains/ChainRegistry";
import Escrow "../managers/Escrow";
import FeeManager "../managers/FeeManager";
import TokenRegistry "../tokens/TokenRegistry";
import ICRC2 "../tokens/ICRC2";
import Validation "../utils/Validation";
import Constants "../utils/Constants";
import RateLimits "../utils/RateLimits";

module {
  type Intent = Types.Intent;
  type Quote = Types.Quote;
  type IntentStatus = Types.IntentStatus;
  type IntentResult<T> = Types.IntentResult<T>;
  type IntentError = Types.IntentError;
  type SystemConfig = Types.SystemConfig;
  type ChainSpec = Types.ChainSpec;
  type FeeBreakdown = Types.FeeBreakdown;

  /// Manager state
  public type ManagerState = {
    var intents : HashMap.HashMap<Nat, Intent>;
    var next_id : Nat;
    escrow : Escrow.EscrowState;
    fee_manager : FeeManager.FeeState;
    chain_registry : ChainRegistry.RegistryState;
    token_registry : TokenRegistry.RegistryState;
    event_logger : Events.EventLogger;
    config : SystemConfig;
    // DoS prevention tracking
    var user_intent_counts : HashMap.HashMap<Principal, Nat>;
    var user_active_counts : HashMap.HashMap<Principal, Nat>;
    var total_cycle_consumption : Nat;
  };

  /// Stable storage format
  public type StableManagerData = {
    intents : [(Nat, Intent)];
    next_id : Nat;
    escrow : Escrow.StableEscrowData;
    chain_registry : ChainRegistry.StableRegistryData;
    token_registry : TokenRegistry.StableRegistryData;
    // DoS prevention tracking
    user_intent_counts : [(Principal, Nat)];
    user_active_counts : [(Principal, Nat)];
    total_cycle_consumption : Nat;
  };

  /// Hash function for intent IDs (sequential Nat values)
  func intentIdHash(id : Nat) : Hash.Hash {
    // For sequential IDs, use a simple modulo hash
    // This is efficient and avoids deprecation warning for Hash.hash
    Nat32.fromNat(id % 4294967295)
  };

  /// Initialize manager
  public func init(config : SystemConfig) : ManagerState {
    {
      var intents = HashMap.HashMap<Nat, Intent>(100, Nat.equal, intentIdHash);
      var next_id = 0;
      escrow = Escrow.init();
      fee_manager = FeeManager.init();
      chain_registry = ChainRegistry.init();
      token_registry = TokenRegistry.init();
      event_logger = Events.EventLogger();
      config = config;
      // DoS prevention tracking
      var user_intent_counts = HashMap.HashMap<Principal, Nat>(100, Principal.equal, Principal.hash);
      var user_active_counts = HashMap.HashMap<Principal, Nat>(100, Principal.equal, Principal.hash);
      var total_cycle_consumption = 0;
    }
  };

  /// Helper: Update intent preserving all fields
  func updateIntent(
    base : Intent,
    status : ?IntentStatus,
    quotes : ?[Quote],
    selected_quote : ??Quote,
    escrow_balance : ?Nat,
    verified_at : ??Time.Time,
    _updated_at : Time.Time
  ) : Intent {
    {
      id = base.id;
      user = base.user;
      source = base.source;
      destination = base.destination;
      source_amount = base.source_amount;
      min_output = base.min_output;
      dest_recipient = base.dest_recipient;
      deadline = base.deadline;
      status = switch (status) {case null base.status; case (?s) s };
      quotes = switch (quotes) { case null base.quotes; case (?q) q };
      selected_quote = switch (selected_quote) { case null base.selected_quote; case (?q) q };
      escrow_balance = switch (escrow_balance) { case null base.escrow_balance; case (?e) e };
      protocol_fee_bps = base.protocol_fee_bps;
      created_at = base.created_at;
      verified_at = switch (verified_at) { case null base.verified_at; case (?v) v };
      generated_address = base.generated_address;
      deposited_utxo = base.deposited_utxo;
      solver_tx_hash = base.solver_tx_hash;
      custom_rpc_urls = base.custom_rpc_urls;
      verification_hints = base.verification_hints;
      metadata = base.metadata;
    }
  };

  /// Check if user can create a new intent (rate limit validation)
  func canCreateIntent(state : ManagerState, user : Principal) : IntentResult<()> {
    // Check per-user total intent limit
    let userTotal = switch (state.user_intent_counts.get(user)) {
      case null { 0 };
      case (?count) { count };
    };

    if (userTotal >= RateLimits.MAX_INTENTS_PER_USER) {
      return #err(#RateLimitExceeded("User has reached maximum intent limit (" # Nat.toText(RateLimits.MAX_INTENTS_PER_USER) # ")"));
    };

    // Check per-user active intent limit
    let userActive = switch (state.user_active_counts.get(user)) {
      case null { 0 };
      case (?count) { count };
    };

    if (userActive >= RateLimits.MAX_ACTIVE_INTENTS_PER_USER) {
      return #err(#RateLimitExceeded("User has reached maximum active intent limit (" # Nat.toText(RateLimits.MAX_ACTIVE_INTENTS_PER_USER) # ")"));
    };

    // Check global total intent limit
    if (state.next_id >= RateLimits.MAX_TOTAL_INTENTS_GLOBAL) {
      return #err(#RateLimitExceeded("Global intent limit reached"));
    };

    // Check global active intent limit
    var globalActive = 0;
    for (count in state.user_active_counts.vals()) {
      globalActive += count;
    };

    if (globalActive >= RateLimits.MAX_ACTIVE_INTENTS_GLOBAL) {
      return #err(#RateLimitExceeded("Global active intent limit reached"));
    };

    #ok(())
  };

  /// Increment user counters after intent creation
  func incrementUserCounters(state : ManagerState, user : Principal) {
    // Increment total intent count
    let currentTotal = switch (state.user_intent_counts.get(user)) {
      case null { 0 };
      case (?count) { count };
    };
    state.user_intent_counts.put(user, currentTotal + 1);

    // Increment active intent count
    let currentActive = switch (state.user_active_counts.get(user)) {
      case null { 0 };
      case (?count) { count };
    };
    state.user_active_counts.put(user, currentActive + 1);
  };

  /// Decrement active counter when intent becomes terminal
  func decrementActiveCounter(state : ManagerState, user : Principal) {
    let currentActive = switch (state.user_active_counts.get(user)) {
      case null { return }; // Already 0 or never tracked
      case (?count) {
        if (count > 0) {
          state.user_active_counts.put(user, count - 1);
        };
      };
    };
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
    // Check rate limits FIRST
    switch (canCreateIntent(state, user)) {
      case (#err(e)) { return #err(e) };
      case (#ok(())) {};
    };

    // Validate inputs
    switch (Validation.validateAmount(source_amount, state.config)) {
      case (?err) { return #err(err) };
      case null {};
    };

    switch (Validation.validateMinOutput(min_output, source_amount)) {
      case (?err) { return #err(err) };
      case null {};
    };

    switch (Validation.validateDeadline(deadline, current_time, state.config)) {
      case (?err) { return #err(err) };
      case null {};
    };

    switch (Validation.validateChainSpec(source, state.config)) {
      case (?err) { return #err(err) };
      case null {};
    };

    switch (Validation.validateChainSpec(destination, state.config)) {
      case (?err) { return #err(err) };
      case null {};
    };

    // Validate chains are supported
    switch (ChainRegistry.validateSpec(state.chain_registry, source)) {
      case (#err(e)) { return #err(e) };
      case (#ok(_)) {};
    };

    switch (ChainRegistry.validateSpec(state.chain_registry, destination)) {
      case (#err(e)) { return #err(e) };
      case (#ok(_)) {};
    };

    // Create intent
    let id = state.next_id;
    state.next_id += 1;

    let intent : Intent = {
      id = id;
      user = user;
      source = source;
      destination = destination;
      source_amount = source_amount;
      min_output = min_output;
      dest_recipient = dest_recipient;
      deadline = deadline;
      status = #PendingQuote;
      quotes = [];
      selected_quote = null;
      escrow_balance = 0;
      protocol_fee_bps = state.config.protocol_fee_bps;
      created_at = current_time;
      verified_at = null;
      generated_address = null;
      deposited_utxo = null;
      solver_tx_hash = null;
      custom_rpc_urls = null;
      verification_hints = null;
      metadata = null;
    };

    state.intents.put(id, intent);

    // Log event
    state.event_logger.emit(#IntentCreated({
      intent_id = id;
      user = user;
      source_chain = source.chain;
      dest_chain = destination.chain;
      amount = source_amount;
      timestamp = current_time;
    }));

    Debug.print("IntentManager: Created intent #" # Nat.toText(id));

    // Increment user counters after successful creation
    incrementUserCounters(state, user);

    #ok(id)
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
    // Get intent
    let intent = switch (state.intents.get(intent_id)) {
      case null { return #err(#NotFound) };
      case (?i) { i };
    };

    // Check if expired
    if (Types.isExpired(intent, current_time)) {
      return #err(#Expired);
    };

    // Validate solver is allowed
    switch (Validation.validateSolver(solver, state.config)) {
      case (?err) { return #err(err) };
      case null {};
    };

    // Validate quote amount
    switch (Validation.validateQuoteAmount(output_amount, intent.min_output, intent.source_amount)) {
      case (?err) { return #err(err) };
      case null {};
    };

    // Check intent can receive quotes
    if (not Types.canReceiveQuotes(intent)) {
      return #err(#InvalidStatus("Intent cannot receive quotes in current status"));
    };

    // Create quote (expiry = deadline or 1 hour, whichever is sooner)
    let quote_expiry = if (intent.deadline < current_time + Constants.ONE_HOUR_NANOS) {
      intent.deadline
    } else {
      current_time + Constants.ONE_HOUR_NANOS
    };

    // Validate quote expiry is in the future
    if (quote_expiry <= current_time) {
      return #err(#InvalidDeadline("Intent deadline already passed"));
    };

    let quote : Quote = {
      solver = solver;
      output_amount = output_amount;
      fee = fee;
      solver_tip = solver_tip;
      solver_dest_address = solver_dest_address;
      expiry = quote_expiry;
      submitted_at = current_time;
    };

    // Add quote to intent
    let updated_quotes = Array.append<Quote>(intent.quotes, [quote]);

    // Transition to Quoted status
    let transitioned = State.transitionToQuoted(intent);
    let new_intent = switch (transitioned) {
      case (#err(e)) { return #err(e) };
      case (#ok(i)) { i };
    };

    let updated_intent = updateIntent(
      new_intent,
      ?new_intent.status,
      ?updated_quotes,
      null,
      null,
      null,
      current_time
    );

    state.intents.put(intent_id, updated_intent);

    // Log event
    state.event_logger.emit(#QuoteSubmitted({
      intent_id = intent_id;
      solver = solver;
      output_amount = output_amount;
      fee = fee;
      quote_index = updated_quotes.size() - 1;
      timestamp = current_time;
    }));

    Debug.print("IntentManager: Quote submitted for intent #" # Nat.toText(intent_id) # " by " # Principal.toText(solver));
    #ok(())
  };

  /// Confirm a quote for an intent
  public func confirmQuote(
    state : ManagerState,
    intent_id : Nat,
    solver : Principal,
    user : Principal,
    current_time : Time.Time
  ) : IntentResult<()> {
    // Get intent
    let intent = switch (state.intents.get(intent_id)) {
      case null { return #err(#NotFound) };
      case (?i) { i };
    };

    // Check authorization
    if (intent.user != user) {
      return #err(#NotIntentCreator);
    };

    // Check if expired
    if (Types.isExpired(intent, current_time)) {
      return #err(#Expired);
    };

    // Find quote from solver and get its index
    var quoteIndex : Nat = 0;
    var foundQuote : ?Quote = null;
    for (i in Iter.range(0, intent.quotes.size() - 1)) {
      if (intent.quotes[i].solver == solver) {
        quoteIndex := i;
        foundQuote := ?intent.quotes[i];
      };
    };

    let quote = switch (foundQuote) {
      case null { return #err(#NotFound) };
      case (?q) { q };
    };

    // Transition to Confirmed
    let transitioned = State.transitionToConfirmed(intent, current_time);
    let new_intent = switch (transitioned) {
      case (#err(e)) { return #err(e) };
      case (#ok(i)) { i };
    };

    let updated_intent = updateIntent(
      new_intent,
      ?new_intent.status,
      null,
      ??quote,
      null,
      null,
      current_time
    );

    state.intents.put(intent_id, updated_intent);

    // Get deposit address (either generated or from quote)
    let depositAddress = switch (quote.solver_dest_address) {
      case (?addr) { addr };
      case null {
        // Generate deposit address for source chain
        // Note: This would require chain-specific address generation
        // For now, use empty string but this should be implemented
        ""
      };
    };

    // Log event
    state.event_logger.emit(#QuoteConfirmed({
      intent_id = intent_id;
      solver = solver;
      quote_index = quoteIndex;
      deposit_address = depositAddress;
      timestamp = current_time;
    }));

    Debug.print("IntentManager: Quote confirmed for intent #" # Nat.toText(intent_id));
    #ok(())
  };

  /// Mark intent as deposited (after verification)
  ///
  /// Transitions an intent to Deposited status and locks the verified amount in escrow.
  /// Must be called by the intent creator after deposit verification on the source chain.
  ///
  /// **Security**: Validates caller is the intent creator. Locks escrow before state transition
  /// to prevent race conditions. Rolls back escrow if state transition fails.
  ///
  /// Parameters:
  /// - `state`: The manager state
  /// - `intent_id`: ID of the intent to mark as deposited
  /// - `caller`: Principal calling this function (must be intent creator)
  /// - `verified_amount`: Amount verified on the source chain
  /// - `current_time`: Current timestamp
  ///
  /// Returns:
  /// - `#ok(())` on success
  /// - `#err(#NotFound)` if intent doesn't exist
  /// - `#err(#NotIntentCreator)` if caller is not the intent creator
  /// - `#err(#InvalidStatus)` if intent is not in Confirmed status
  /// - `#err(#Expired)` if intent has expired
  public func markDeposited(
    state : ManagerState,
    intent_id : Nat,
    caller : Principal,
    verified_amount : Nat,
    current_time : Time.Time
  ) : IntentResult<()> {
    let intent = switch (state.intents.get(intent_id)) {
      case null { return #err(#NotFound) };
      case (?i) { i };
    };

    // Verify caller is the intent creator
    if (not Principal.equal(intent.user, caller)) {
      return #err(#NotIntentCreator);
    };

    // Lock funds in escrow BEFORE state transition to maintain consistency
    switch (Escrow.lock(state.escrow, intent.user, intent.source.token, verified_amount)) {
      case (#err(e)) { return #err(e) };
      case (#ok(())) {};
    };

    // Transition to Deposited (only after escrow is locked)
    let transitioned = State.transitionToDeposited(intent, current_time, current_time);
    let new_intent = switch (transitioned) {
      case (#err(e)) {
        // Rollback: unlock the escrow if state transition fails
        ignore Escrow.release(state.escrow, intent.user, intent.source.token, verified_amount);
        return #err(e);
      };
      case (#ok(i)) { i };
    };

    let updated_intent = updateIntent(
      new_intent,
      ?new_intent.status,
      null,
      null,
      ?verified_amount,
      ??current_time,
      current_time
    );

    state.intents.put(intent_id, updated_intent);

    // Log events
    state.event_logger.emit(#DepositVerified({
      intent_id = intent_id;
      chain = intent.source.chain;
      tx_hash = ""; // Should be passed in
      amount = verified_amount;
      timestamp = current_time;
    }));

    state.event_logger.emit(#EscrowLocked({
      intent_id = intent_id;
      user = intent.user;
      token = intent.source.token;
      amount = verified_amount;
      timestamp = current_time;
    }));

    Debug.print("IntentManager: Intent #" # Nat.toText(intent_id) # " marked as deposited");
    #ok(())
  };

  /// Fulfill an intent (release escrow to solver)
  ///
  /// Completes an intent by transferring tokens to the solver and releasing escrow.
  ///
  /// **Security**: Performs risky async operations (token transfer) BEFORE state changes.
  /// This ensures that if the transfer fails, no state changes have occurred.
  /// Releases escrow after state transition with proper error handling.
  ///
  /// Parameters:
  /// - `state`: The manager state
  /// - `intent_id`: ID of the intent to fulfill
  /// - `current_time`: Current timestamp
  ///
  /// Returns:
  /// - `#ok(FeeBreakdown)` with fee details on success
  /// - `#err(...)` if validation fails, transfer fails, or state transition fails
  public func fulfillIntent(
    state : ManagerState,
    intent_id : Nat,
    current_time : Time.Time
  ) : async IntentResult<FeeBreakdown> {
    let intent = switch (state.intents.get(intent_id)) {
      case null { return #err(#NotFound) };
      case (?i) { i };
    };

    let quote = switch (intent.selected_quote) {
      case null { return #err(#InternalError("No quote selected")) };
      case (?q) { q };
    };

    // Validate state transition is possible BEFORE any operations
    // This ensures we fail fast if intent is in wrong state
    let transitioned = State.transitionToFulfilled(intent, current_time);
    let new_intent = switch (transitioned) {
      case (#err(e)) { return #err(e) };
      case (#ok(i)) { i };
    };

    // Calculate fees BEFORE any async operations
    let fees = switch (FeeManager.calculateFees(
      quote.output_amount,
      intent.protocol_fee_bps,
      quote
    )) {
      case null { return #err(#InvalidFee("Fees exceed output amount")) };
      case (?f) { f };
    };

    // Transfer tokens to solver (risky async operation)
    // State transition has been validated but NOT committed yet
    // If this fails, no state changes have occurred
    switch (await releaseToSolver(state, intent, quote.solver, fees.net_output)) {
      case (#err(e)) {
        Debug.print("Failed to release tokens to solver: " # debug_show(e));
        return #err(e);
      };
      case (#ok(_block_index)) {
        Debug.print("Released " # Nat.toText(fees.net_output) # " " # intent.destination.token # " to solver");
      };
    };

    // Release escrow (internal accounting)
    switch (Escrow.release(state.escrow, intent.user, intent.source.token, intent.escrow_balance)) {
      case (#err(e)) {
        // NOTE: This is a critical error - escrow accounting is now inconsistent
        Debug.print("⚠️ CRITICAL: Failed to release escrow for intent #" # Nat.toText(intent_id));
        return #err(e);
      };
      case (#ok(())) {};
    };

    // Record protocol fee
    FeeManager.recordProtocolFee(state.fee_manager, intent.destination.token, fees.protocol_fee);

    let updated_intent = updateIntent(
      new_intent,
      ?#Fulfilled,
      null,
      null,
      ?0,
      null,
      current_time
    );

    state.intents.put(intent_id, updated_intent);

    // Log events
    state.event_logger.emit(#IntentFulfilled({
      intent_id = intent_id;
      solver = quote.solver;
      final_amount = fees.net_output;
      protocol_fee = fees.protocol_fee;
      timestamp = current_time;
    }));

    state.event_logger.emit(#EscrowReleased({
      intent_id = intent_id;
      recipient = quote.solver; // Released to solver
      token = intent.source.token;
      amount = intent.escrow_balance;
      timestamp = current_time;
    }));

    state.event_logger.emit(#FeeCollected({
      intent_id = intent_id;
      token = intent.destination.token;
      amount = fees.protocol_fee;
      collector = intent.user; // Placeholder - should be protocol principal
      timestamp = current_time;
    }));

    Debug.print("IntentManager: Intent #" # Nat.toText(intent_id) # " fulfilled");

    // Decrement active counter after successful fulfillment
    decrementActiveCounter(state, intent.user);

    #ok(fees)
  };

  /// Cancel an intent
  ///
  /// Cancels an intent and refunds any deposited tokens to the user.
  ///
  /// **Security**: Performs risky async operations (token refund) BEFORE state changes.
  /// This ensures that if the refund fails, no state changes have occurred.
  /// Releases escrow after state transition with proper error handling.
  ///
  /// Parameters:
  /// - `state`: The manager state
  /// - `intent_id`: ID of the intent to cancel
  /// - `user`: Principal requesting cancellation (must be intent creator)
  /// - `current_time`: Current timestamp
  ///
  /// Returns:
  /// - `#ok(())` on success
  /// - `#err(...)` if validation fails, refund fails, or state transition fails
  public func cancelIntent(
    state : ManagerState,
    intent_id : Nat,
    user : Principal,
    current_time : Time.Time
  ) : async IntentResult<()> {
    let intent = switch (state.intents.get(intent_id)) {
      case null { return #err(#NotFound) };
      case (?i) { i };
    };

    // Check authorization
    if (intent.user != user) {
      return #err(#NotIntentCreator);
    };

    // Validate state transition is possible BEFORE any operations
    // This ensures we fail fast if intent cannot be cancelled
    let transitioned = State.transitionToCancelled(intent);
    let new_intent = switch (transitioned) {
      case (#err(e)) { return #err(e) };
      case (#ok(i)) { i };
    };

    // Refund tokens to user if deposited (risky async operation)
    // State transition has been validated but NOT committed yet
    // If this fails, no state changes have occurred
    if (intent.escrow_balance > 0) {
      // Transfer tokens back to user
      switch (await refundToUser(state, intent)) {
        case (#err(e)) {
          Debug.print("Failed to refund tokens to user: " # debug_show(e));
          return #err(e);
        };
        case (#ok(_block_index)) {
          Debug.print("Refunded " # Nat.toText(intent.escrow_balance) # " " # intent.source.token # " to user");
        };
      };
    };

    // Release escrow (internal accounting) if there was a balance
    if (intent.escrow_balance > 0) {
      switch (Escrow.release(state.escrow, intent.user, intent.source.token, intent.escrow_balance)) {
        case (#err(e)) {
          // NOTE: This is a critical error - escrow accounting is now inconsistent
          Debug.print("⚠️ CRITICAL: Failed to release escrow for intent #" # Nat.toText(intent_id));
          return #err(e);
        };
        case (#ok(())) {};
      };
    };

    let updated_intent = updateIntent(
      new_intent,
      ?#Cancelled,
      null,
      null,
      ?0,
      null,
      current_time
    );

    state.intents.put(intent_id, updated_intent);

    // Log event
    state.event_logger.emit(#IntentCancelled({
      intent_id = intent_id;
      reason = "Cancelled by user";
      timestamp = current_time;
    }));

    Debug.print("IntentManager: Intent #" # Nat.toText(intent_id) # " cancelled");

    // Decrement active counter after successful cancellation
    decrementActiveCounter(state, intent.user);

    #ok(())
  };

  /// Get intent by ID
  public func getIntent(state : ManagerState, id : Nat) : ?Intent {
    state.intents.get(id)
  };

  /// Get user's intents
  public func getUserIntents(state : ManagerState, user : Principal) : [Intent] {
    let filtered = Array.filter<(Nat, Intent)>(
      Iter.toArray(state.intents.entries()),
      func((_, intent)) { intent.user == user }
    );
    Array.map<(Nat, Intent), Intent>(filtered, func((_, intent)) { intent })
  };

  // DoS Prevention and Monitoring Functions

  /// Clean up old terminal intents to prevent unbounded HashMap growth
  /// Returns the number of intents cleaned up
  public func cleanupTerminalIntents(
    state : ManagerState,
    retention_period : Int,
    current_time : Time.Time,
    max_cleanups : Nat
  ) : Nat {
    var cleaned : Nat = 0;
    let cutoff_time = current_time - retention_period;

    let entries = Iter.toArray(state.intents.entries());

    for ((id, intent) in entries.vals()) {
      if (cleaned >= max_cleanups) {
        return cleaned;
      };

      // Only clean up terminal states that are old enough
      let is_terminal = switch (intent.status) {
        case (#Fulfilled) { true };
        case (#Cancelled) { true };
        case (#Expired) { true };
        case _ { false };
      };

      if (is_terminal and intent.created_at < cutoff_time) {
        state.intents.delete(id);
        cleaned += 1;
      };
    };

    cleaned
  };

  /// Get intent statistics
  public func getIntentStats(state : ManagerState) : {
    total : Nat;
    active : Nat;
    fulfilled : Nat;
    cancelled : Nat;
    expired : Nat;
  } {
    var active = 0;
    var fulfilled = 0;
    var cancelled = 0;
    var expired = 0;

    for (intent in state.intents.vals()) {
      switch (intent.status) {
        case (#PendingQuote or #QuoteReceived or #Confirmed or #Deposited) {
          active += 1;
        };
        case (#Fulfilled) { fulfilled += 1 };
        case (#Cancelled) { cancelled += 1 };
        case (#Expired) { expired += 1 };
      };
    };

    {
      total = state.intents.size();
      active = active;
      fulfilled = fulfilled;
      cancelled = cancelled;
      expired = expired;
    }
  };

  /// Get user's cycle budget information
  public func getUserCycleBudget(state : ManagerState, user : Principal) : ?{
    total_intents : Nat;
    active_intents : Nat;
    remaining_total : Nat;
    remaining_active : Nat;
  } {
    let userTotal = switch (state.user_intent_counts.get(user)) {
      case null { 0 };
      case (?count) { count };
    };

    let userActive = switch (state.user_active_counts.get(user)) {
      case null { 0 };
      case (?count) { count };
    };

    ?{
      total_intents = userTotal;
      active_intents = userActive;
      remaining_total = if (userTotal < RateLimits.MAX_INTENTS_PER_USER) {
        RateLimits.MAX_INTENTS_PER_USER - userTotal
      } else { 0 };
      remaining_active = if (userActive < RateLimits.MAX_ACTIVE_INTENTS_PER_USER) {
        RateLimits.MAX_ACTIVE_INTENTS_PER_USER - userActive
      } else { 0 };
    }
  };

  /// Get cycle consumption statistics
  public func getCycleStats(state : ManagerState) : {
    total_consumed : Nat;
    global_active : Nat;
    global_total : Nat;
    capacity_status : Text;
  } {
    var globalActive = 0;
    for (count in state.user_active_counts.vals()) {
      globalActive += count;
    };

    let activePercent = if (RateLimits.MAX_ACTIVE_INTENTS_GLOBAL > 0) {
      (globalActive * 100) / RateLimits.MAX_ACTIVE_INTENTS_GLOBAL
    } else { 0 };

    let status = if (activePercent >= 90) {
      "CRITICAL"
    } else if (activePercent >= 75) {
      "WARNING"
    } else if (activePercent >= 50) {
      "MODERATE"
    } else {
      "HEALTHY"
    };

    {
      total_consumed = state.total_cycle_consumption;
      global_active = globalActive;
      global_total = state.next_id;
      capacity_status = status;
    }
  };

  // Token Management Functions

  /// Register a token ledger
  public func registerToken(
    state : ManagerState,
    symbol : Text,
    ledger_principal : Principal,
    decimals : Nat8,
    fee : Nat
  ) {
    TokenRegistry.registerToken(state.token_registry, symbol, ledger_principal, decimals, fee)
  };

  /// Get ledger principal for a token
  public func getTokenLedger(state : ManagerState, symbol : Text) : ?Principal {
    TokenRegistry.getLedger(state.token_registry, symbol)
  };

  /// Deposit tokens from user to canister (after quote confirmation)
  ///
  /// Transfers tokens from user to canister and updates escrow accounting.
  ///
  /// **Security**: User must have already called approve() on the token ledger.
  /// The ICRC-2 transferFrom is NON-REVERSIBLE - if markDeposited fails after
  /// successful transfer, tokens will be stuck in canister without escrow accounting.
  /// This critical failure is logged and requires manual recovery by admin.
  ///
  /// Parameters:
  /// - `state`: The manager state
  /// - `intent_id`: ID of the intent to deposit for
  /// - `canister_principal`: Principal of this canister (for transferFrom)
  /// - `current_time`: Current timestamp
  ///
  /// Returns:
  /// - `#ok(block_index)` on success with ledger block index
  /// - `#err(...)` if validation fails, transfer fails, or escrow lock fails
  public func depositTokens(
    state : ManagerState,
    intent_id : Nat,
    canister_principal : Principal,
    current_time : Time.Time
  ) : async IntentResult<Nat> {
    let intent = switch (state.intents.get(intent_id)) {
      case null { return #err(#NotFound) };
      case (?i) { i };
    };

    // Can only deposit if quote is confirmed
    if (intent.status != #Confirmed) {
      return #err(#InvalidStatus("Intent must be in Confirmed status to deposit"));
    };

    // Get token ledger
    let ledger_principal = switch (TokenRegistry.getLedger(state.token_registry, intent.source.token)) {
      case null {
        return #err(#InvalidToken("Token not registered: " # intent.source.token));
      };
      case (?ledger) { ledger };
    };

    // Transfer tokens from user to canister using ICRC-2 transferFrom
    switch (await ICRC2.depositFrom(
      ledger_principal,
      intent.user,
      canister_principal,
      intent.source_amount,
      null // No memo
    )) {
      case (#err(e)) { #err(e) };
      case (#ok(block_index)) {
        // Mark intent as deposited (locks escrow)
        switch (markDeposited(state, intent_id, intent.user, intent.source_amount, current_time)) {
          case (#err(e)) {
            // CRITICAL: Tokens were transferred but escrow lock failed
            // Tokens are now in canister but not tracked in escrow
            // This requires manual recovery by admin
            Debug.print("🚨 CRITICAL FAILURE: Tokens transferred but escrow lock failed for intent #" # Nat.toText(intent_id));
            Debug.print("🚨 User: " # Principal.toText(intent.user));
            Debug.print("🚨 Token: " # intent.source.token);
            Debug.print("🚨 Amount: " # Nat.toText(intent.source_amount));
            Debug.print("🚨 Block Index: " # Nat.toText(block_index));
            Debug.print("🚨 Error: " # debug_show(e));
            Debug.print("🚨 Manual recovery required - admin must refund or lock escrow manually");
            #err(e)
          };
          case (#ok(())) {
            Debug.print("Deposited " # Nat.toText(intent.source_amount) # " " # intent.source.token # " for intent " # Nat.toText(intent_id));
            #ok(block_index)
          };
        }
      };
    }
  };

  /// Release tokens to solver on fulfillment
  func releaseToSolver(
    state : ManagerState,
    intent : Intent,
    solver : Principal,
    amount : Nat
  ) : async IntentResult<Nat> {
    // Get token ledger
    let ledger_principal = switch (TokenRegistry.getLedger(state.token_registry, intent.destination.token)) {
      case null {
        return #err(#InvalidToken("Destination token not registered: " # intent.destination.token));
      };
      case (?ledger) { ledger };
    };

    // Transfer tokens from canister to solver
    await ICRC2.transferTo(
      ledger_principal,
      solver,
      amount,
      ?Text.encodeUtf8("Intent #" # Nat.toText(intent.id) # " solver payout")
    )
  };

  /// Refund tokens to user on cancellation
  func refundToUser(
    state : ManagerState,
    intent : Intent
  ) : async IntentResult<Nat> {
    // Get token ledger
    let ledger_principal = switch (TokenRegistry.getLedger(state.token_registry, intent.source.token)) {
      case null {
        return #err(#InvalidToken("Source token not registered: " # intent.source.token));
      };
      case (?ledger) { ledger };
    };

    // Transfer tokens from canister back to user
    await ICRC2.transferTo(
      ledger_principal,
      intent.user,
      intent.escrow_balance,
      ?Text.encodeUtf8("Intent #" # Nat.toText(intent.id) # " refund")
    )
  };

  /// Export state for upgrade
  public func toStable(state : ManagerState) : StableManagerData {
    {
      intents = Iter.toArray(state.intents.entries());
      next_id = state.next_id;
      escrow = Escrow.toStable(state.escrow);
      chain_registry = ChainRegistry.toStable(state.chain_registry);
      token_registry = TokenRegistry.toStable(state.token_registry);
      // DoS prevention tracking
      user_intent_counts = Iter.toArray(state.user_intent_counts.entries());
      user_active_counts = Iter.toArray(state.user_active_counts.entries());
      total_cycle_consumption = state.total_cycle_consumption;
    }
  };

  /// Import state from upgrade
  public func fromStable(data : StableManagerData, config : SystemConfig) : ManagerState {
    let intents_map = HashMap.HashMap<Nat, Intent>(100, Nat.equal, intentIdHash);
    for ((id, intent) in data.intents.vals()) {
      intents_map.put(id, intent);
    };

    // Restore DoS prevention tracking
    let user_counts = HashMap.HashMap<Principal, Nat>(100, Principal.equal, Principal.hash);
    for ((user, count) in data.user_intent_counts.vals()) {
      user_counts.put(user, count);
    };

    let active_counts = HashMap.HashMap<Principal, Nat>(100, Principal.equal, Principal.hash);
    for ((user, count) in data.user_active_counts.vals()) {
      active_counts.put(user, count);
    };

    {
      var intents = intents_map;
      var next_id = data.next_id;
      escrow = Escrow.fromStable(data.escrow);
      fee_manager = FeeManager.init(); // Cannot restore from stable
      chain_registry = ChainRegistry.fromStable(data.chain_registry);
      token_registry = TokenRegistry.fromStable(data.token_registry);
      event_logger = Events.EventLogger();
      config = config;
      // DoS prevention tracking
      var user_intent_counts = user_counts;
      var user_active_counts = active_counts;
      var total_cycle_consumption = data.total_cycle_consumption;
    }
  };
}
