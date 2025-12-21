/// Core intent lifecycle management module.
/// Orchestrates intent posting, quoting, locking, and fulfillment.
///
/// Example usage:
/// ```motoko
/// import IntentManager "mo:icp-intents/IntentManager";
/// import Types "mo:icp-intents/Types";
///
/// stable var intentState = IntentManager.init(config);
///
/// public shared(msg) func postIntent(req: Types.CreateIntentRequest) : async Types.IntentResult<Nat> {
///   await IntentManager.postIntent(intentState, msg.caller, req, Time.now());
/// };
/// ```

import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Array "mo:base/Array";
import HashMap "mo:base/HashMap";
import Hash "mo:base/Hash";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Buffer "mo:base/Buffer";
import Types "../icp-intents-lib/Types";
import Utils "../icp-intents-lib/Utils";
import Escrow "../icp-intents-lib/Escrow";
import TECDSA "../icp-intents-lib/TECDSA";
import Verification "../icp-intents-lib/Verification";

module {
  type Intent = Types.Intent;
  type Quote = Types.Quote;
  type IntentStatus = Types.IntentStatus;
  type IntentResult<T> = Types.IntentResult<T>;
  type IntentError = Types.IntentError;
  type CreateIntentRequest = Types.CreateIntentRequest;
  type SubmitQuoteRequest = Types.SubmitQuoteRequest;
  type ProtocolConfig = Types.ProtocolConfig;
  type Event = Types.Event;

  /// Intent manager state
  public type State = {
    config: ProtocolConfig;
    intents: HashMap.HashMap<Nat, Intent>;
    var nextIntentId: Nat;
    events: Buffer.Buffer<Event>;
    escrow: Escrow.State;
    tecdsaConfig: TECDSA.Config;
    verificationConfig: Verification.Config;
    supportedChains: [Nat];  // Supported chain IDs
  };

  /// Initialize intent manager
  public func init(
    config: ProtocolConfig,
    tecdsaConfig: TECDSA.Config,
    verificationConfig: Verification.Config,
    supportedChains: [Nat]
  ) : State {
    {
      config = config;
      intents = HashMap.HashMap<Nat, Intent>(10, Nat.equal, Hash.hash);
      var nextIntentId = 1;
      events = Buffer.Buffer<Event>(100);
      escrow = Escrow.init();
      tecdsaConfig = tecdsaConfig;
      verificationConfig = verificationConfig;
      supportedChains = supportedChains;
    }
  };

  /// Helper: Add event to buffer (with cap to prevent unbounded growth)
  func addEvent(state: State, event: Event) {
    let maxEvents = state.config.max_events;

    // If buffer is at capacity, remove oldest event (circular buffer)
    if (state.events.size() >= maxEvents) {
      ignore state.events.remove(0); // Remove first (oldest) event
    };

    state.events.add(event);
  };

  /// Helper: Count active intents (Open, Quoted, Locked)
  func countActiveIntents(state: State) : Nat {
    var count = 0;
    for (intent in state.intents.vals()) {
      switch (intent.status) {
        case (#Open or #Quoted or #Locked) { count += 1 };
        case _ {}; // Fulfilled, Refunded, Cancelled don't count
      };
    };
    count
  };

  /// Post a new intent
  public func postIntent(
    state: State,
    caller: Principal,
    request: CreateIntentRequest,
    currentTime: Time.Time
  ) : async IntentResult<Nat> {
    // Validation
    if (state.config.paused) {
      return #err(#InternalError("System is paused"));
    };

    // Check if we've hit max active intents (prevent memory exhaustion)
    let activeCount = countActiveIntents(state);
    if (activeCount >= state.config.max_active_intents) {
      return #err(#InternalError("Maximum active intents reached. Please try again later."));
    };

    if (not Utils.isValidAmount(request.source_amount, state.config.min_intent_amount)) {
      return #err(#InvalidAmount);
    };

    if (not Utils.isValidTokenId(request.source.token)) {
      return #err(#InvalidToken);
    };

    // Validate destination chain if EVM
    switch (request.destination.chain_id) {
      case (?chainId) {
        if (not Utils.isValidChainId(chainId, state.supportedChains)) {
          return #err(#InvalidChain);
        };
      };
      case null {};
    };

    if (not Utils.isValidEthAddress(request.dest_recipient)) {
      return #err(#InvalidAddress);
    };

    if (not Utils.isValidDeadline(request.deadline, currentTime, state.config.max_intent_lifetime)) {
      return #err(#DeadlinePassed);
    };

    // Create intent
    let intentId = state.nextIntentId;
    state.nextIntentId += 1;

    let intent : Intent = {
      id = intentId;
      user = caller;
      source = request.source;
      destination = request.destination;
      dest_recipient = request.dest_recipient;
      source_amount = request.source_amount;
      min_output = request.min_output;
      created_at = currentTime;
      deadline = request.deadline;
      status = #Open;
      quotes = [];
      selected_quote = null;
      escrow_balance = 0;
      generated_address = null;
      solver_tx_hash = null;
      verified_at = null;
      protocol_fee_bps = state.config.default_protocol_fee_bps;
      custom_rpc_urls = request.custom_rpc_urls;
      verification_hints = request.verification_hints;
      metadata = request.metadata;
    };

    state.intents.put(intentId, intent);

    // Log event
    let event : Event = {
      timestamp = currentTime;
      event_type = #IntentPosted({ intent_id = intentId; user = caller });
    };
    addEvent(state, event);

    #ok(intentId)
  };

  /// Submit a quote for an intent
  public func submitQuote(
    state: State,
    solver: Principal,
    request: SubmitQuoteRequest,
    currentTime: Time.Time
  ) : IntentResult<()> {
    // Get intent
    let intentOpt = state.intents.get(request.intent_id);
    let intent = switch (intentOpt) {
      case (?i) i;
      case null { return #err(#NotFound) };
    };

    // Validate status
    switch (intent.status) {
      case (#Open or #Quoted) {};
      case _ { return #err(#InvalidStatus("Intent is not open for quotes")) };
    };

    // Check deadline
    if (Utils.hasPassed(intent.deadline, currentTime)) {
      return #err(#DeadlinePassed);
    };

    // Validate quote
    if (request.output_amount < intent.min_output) {
      return #err(#InvalidAmount);
    };

    if (not Utils.isInFuture(request.expiry, currentTime)) {
      return #err(#QuoteExpired);
    };

    // Create quote
    let quote : Quote = {
      solver = solver;
      output_amount = request.output_amount;
      fee = request.fee;
      expiry = request.expiry;
      submitted_at = currentTime;
    };

    // Add quote to intent
    let quotes = Buffer.fromArray<Quote>(intent.quotes);
    quotes.add(quote);

    let updated : Intent = {
      intent with
      status = #Quoted;
      quotes = Buffer.toArray(quotes);
    };

    state.intents.put(intent.id, updated);

    // Log event
    let event : Event = {
      timestamp = currentTime;
      event_type = #QuoteSubmitted({
        intent_id = intent.id;
        solver = solver;
        amount = request.output_amount;
      });
    };
    addEvent(state, event);

    #ok(())
  };

  /// Confirm a quote and lock escrow
  public func confirmQuote(
    state: State,
    caller: Principal,
    intentId: Nat,
    quoteIndex: Nat,
    currentTime: Time.Time
  ) : async IntentResult<Text> {
    // Get intent
    let intentOpt = state.intents.get(intentId);
    let intent = switch (intentOpt) {
      case (?i) i;
      case null { return #err(#NotFound) };
    };

    // Validate caller
    if (not Principal.equal(caller, intent.user)) {
      return #err(#Unauthorized);
    };

    // Validate status
    switch (intent.status) {
      case (#Open or #Quoted) {};
      case _ { return #err(#InvalidStatus("Intent already locked or fulfilled")) };
    };

    // Check deadline
    if (Utils.hasPassed(intent.deadline, currentTime)) {
      return #err(#DeadlinePassed);
    };

    // Get selected quote
    if (quoteIndex >= intent.quotes.size()) {
      return #err(#NotFound);
    };

    let selectedQuote = intent.quotes[quoteIndex];

    // Check quote expiry
    if (Utils.hasPassed(selectedQuote.expiry, currentTime)) {
      return #err(#QuoteExpired);
    };

    // Calculate total escrow needed (source_amount + solver fee)
    let totalEscrow = intent.source_amount + selectedQuote.fee;

    // Lock funds in escrow
    let lockResult = Escrow.lock(state.escrow, caller, intent.source.token, totalEscrow);
    switch (lockResult) {
      case (#err(e)) { return #err(e) };
      case (#ok(_)) {};
    };

    // Generate tECDSA address for solver deposit
    let addressResult = await TECDSA.deriveAddress(
      state.tecdsaConfig,
      intentId,
      caller
    );

    let generatedAddress = switch (addressResult) {
      case (#ok(addr)) addr;
      case (#err(e)) {
        // Rollback escrow lock
        ignore Escrow.unlock(state.escrow, caller, intent.source.token, totalEscrow);
        return #err(e);
      };
    };

    // Update intent
    let updated : Intent = {
      intent with
      status = #Locked;
      selected_quote = ?selectedQuote;
      escrow_balance = totalEscrow;
      generated_address = ?generatedAddress;
    };

    state.intents.put(intentId, updated);

    // Log event
    let event : Event = {
      timestamp = currentTime;
      event_type = #IntentLocked({ intent_id = intentId; quote_index = quoteIndex });
    };
    addEvent(state, event);

    #ok(generatedAddress)
  };

  /// Claim fulfillment (solver or anyone can call with tx hash hint)
  public func claimFulfillment(
    state: State,
    intentId: Nat,
    txHashHint: ?Text,
    currentTime: Time.Time
  ) : async IntentResult<()> {
    // Get intent
    let intentOpt = state.intents.get(intentId);
    let intent = switch (intentOpt) {
      case (?i) i;
      case null { return #err(#NotFound) };
    };

    // Validate status
    switch (intent.status) {
      case (#Locked) {};
      case _ { return #err(#InvalidStatus("Intent not locked")) };
    };

    // Get generated address and selected quote
    let depositAddress = switch (intent.generated_address) {
      case (?addr) addr;
      case null { return #err(#InternalError("No deposit address")) };
    };

    let quote = switch (intent.selected_quote) {
      case (?q) q;
      case null { return #err(#InternalError("No selected quote")) };
    };

    // Verify deposit on destination chain
    // Get chain ID from destination (for EVM chains)
    let chainId = switch (intent.destination.chain_id) {
      case (?id) id;
      case null { return #err(#InvalidChain) };
    };

    let verificationResult = await Verification.verifyDeposit(
      state.verificationConfig,
      depositAddress,
      quote.output_amount,
      intent.destination.token,
      chainId,
      txHashHint,
      null  // fromBlock - could optimize by storing block number
    );

    switch (verificationResult) {
      case (#Success(data)) {
        // Release escrow to solver
        let releaseAmount = intent.escrow_balance;
        let protocolFee = Utils.calculateFee(releaseAmount, intent.protocol_fee_bps);
        let solverAmount = Utils.safeSub(releaseAmount, protocolFee);

        // Release to solver
        let releaseResult = Escrow.release(
          state.escrow,
          intent.user,
          intent.source.token,
          solverAmount
        );

        switch (releaseResult) {
          case (#err(e)) { return #err(e) };
          case (#ok(_)) {};
        };

        // Release protocol fee to fee collector
        ignore Escrow.release(
          state.escrow,
          intent.user,
          intent.source.token,
          protocolFee
        );

        // Update intent
        let updated : Intent = {
          intent with
          status = #Fulfilled;
          solver_tx_hash = ?data.tx_hash;
          verified_at = ?currentTime;
        };

        state.intents.put(intentId, updated);

        // Log event
        let event : Event = {
          timestamp = currentTime;
          event_type = #IntentFulfilled({
            intent_id = intentId;
            released_amount = solverAmount;
          });
        };
        addEvent(state, event);

        #ok(())
      };
      case (#Pending) {
        #err(#VerificationFailed("Deposit not yet confirmed"))
      };
      case (#Failed(reason)) {
        #err(#VerificationFailed(reason))
      };
    }
  };

  /// Cancel an intent (user only, before locking)
  public func cancelIntent(
    state: State,
    caller: Principal,
    intentId: Nat,
    currentTime: Time.Time
  ) : IntentResult<()> {
    let intentOpt = state.intents.get(intentId);
    let intent = switch (intentOpt) {
      case (?i) i;
      case null { return #err(#NotFound) };
    };

    if (not Principal.equal(caller, intent.user)) {
      return #err(#Unauthorized);
    };

    switch (intent.status) {
      case (#Open or #Quoted) {};
      case _ { return #err(#InvalidStatus("Cannot cancel locked/fulfilled intent")) };
    };

    let updated : Intent = {
      intent with
      status = #Cancelled;
    };

    state.intents.put(intentId, updated);

    let event : Event = {
      timestamp = currentTime;
      event_type = #IntentCancelled({ intent_id = intentId });
    };
    addEvent(state, event);

    #ok(())
  };

  /// Refund expired intent (anyone can call)
  public func refundIntent(
    state: State,
    intentId: Nat,
    currentTime: Time.Time
  ) : IntentResult<()> {
    let intentOpt = state.intents.get(intentId);
    let intent = switch (intentOpt) {
      case (?i) i;
      case null { return #err(#NotFound) };
    };

    // Check deadline passed
    if (not Utils.hasPassed(intent.deadline, currentTime)) {
      return #err(#InternalError("Deadline not yet passed"));
    };

    // Can only refund locked intents
    switch (intent.status) {
      case (#Locked) {};
      case _ { return #err(#InvalidStatus("Intent not locked")) };
    };

    // Unlock escrow
    ignore Escrow.unlock(
      state.escrow,
      intent.user,
      intent.source.token,
      intent.escrow_balance
    );

    let updated : Intent = {
      intent with
      status = #Refunded;
    };

    state.intents.put(intentId, updated);

    let event : Event = {
      timestamp = currentTime;
      event_type = #IntentRefunded({ intent_id = intentId; reason = "Deadline expired" });
    };
    addEvent(state, event);

    #ok(())
  };

  /// Get intent by ID
  public func getIntent(state: State, id: Nat) : ?Intent {
    state.intents.get(id)
  };

  /// Get paginated intents (billboard)
  public func getIntents(
    state: State,
    offset: Nat,
    limit: Nat
  ) : Types.PagedIntents {
    let allIntents = Iter.toArray(state.intents.vals());

    // Sort by created_at descending (newest first)
    let sorted = Array.sort<Intent>(
      allIntents,
      func(a, b) {
        if (a.created_at > b.created_at) { #less }
        else if (a.created_at < b.created_at) { #greater }
        else { #equal }
      }
    );

    let total = sorted.size();
    let actualLimit = Utils.clamp(limit, 1, 100);
    let end = Nat.min(offset + actualLimit, total);

    let data = if (offset >= total) {
      []
    } else {
      Array.tabulate<Intent>(
        end - offset,
        func(i) { sorted[offset + i] }
      )
    };

    {
      data = data;
      total = total;
      offset = offset;
      limit = actualLimit;
    }
  };

  /// Get intents by user
  public func getUserIntents(state: State, user: Principal) : [Intent] {
    let allIntents = Iter.toArray(state.intents.vals());
    Array.filter<Intent>(allIntents, func(i) { Principal.equal(i.user, user) })
  };

  /// Get intents by solver (where they have submitted quotes)
  public func getSolverIntents(state: State, solver: Principal) : [Intent] {
    let allIntents = Iter.toArray(state.intents.vals());
    Array.filter<Intent>(
      allIntents,
      func(i) {
        Option.isSome(Array.find<Quote>(i.quotes, func(q) { Principal.equal(q.solver, solver) }))
      }
    )
  };

  // ===========================
  // UPGRADE HELPERS
  // ===========================

  /// Serialize state for upgrade
  public func serializeState(state: State) : {
    nextIntentId: Nat;
    intents: [(Nat, Intent)];
    events: [Event];
    escrowAccounts: [((Principal, Text), Types.EscrowAccount)];
  } {
    {
      nextIntentId = state.nextIntentId;
      intents = Iter.toArray(state.intents.entries());
      events = Buffer.toArray(state.events);
      escrowAccounts = Iter.toArray(state.escrow.accounts.entries());
    }
  };

  /// Deserialize state after upgrade
  public func deserializeState(
    config: ProtocolConfig,
    tecdsaConfig: TECDSA.Config,
    verificationConfig: Verification.Config,
    supportedChains: [Nat],
    serialized: {
      nextIntentId: Nat;
      intents: [(Nat, Intent)];
      events: [Event];
      escrowAccounts: [((Principal, Text), Types.EscrowAccount)];
    }
  ) : State {
    let state = init(config, tecdsaConfig, verificationConfig, supportedChains);

    // Restore intents
    for ((id, intent) in serialized.intents.vals()) {
      state.intents.put(id, intent);
    };

    // Restore next ID
    state.nextIntentId := serialized.nextIntentId;

    // Restore events
    for (event in serialized.events.vals()) {
      addEvent(state, event);
    };

    // Restore escrow accounts
    for ((key, account) in serialized.escrowAccounts.vals()) {
      state.escrow.accounts.put(key, account);
    };

    state
  };
}
