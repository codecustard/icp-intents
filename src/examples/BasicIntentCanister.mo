/// Example: Basic Intent Canister
/// Shows how to use the ICP Intents library to build a complete intent-based swap system.
///
/// This canister demonstrates:
/// 1. User-facing endpoints (posting intents, viewing billboard)
/// 2. Solver-facing endpoints (submitting quotes, claiming fulfillment)
/// 3. Escrow management (deposit, withdraw)
/// 4. Automated background tasks (deadline checking, verification polling)
///
/// Deploy with:
/// ```
/// dfx deploy BasicIntentCanister
/// ```

import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Timer "mo:base/Timer";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Option "mo:base/Option";
import ExperimentalCycles "mo:base/ExperimentalCycles";

// Import the library modules
import Types "../icp-intents-lib/Types";
import IntentManager "../icp-intents-lib/IntentManager";
import Escrow "../icp-intents-lib/Escrow";
import Utils "../icp-intents-lib/Utils";
import Verification "../icp-intents-lib/Verification";
import HoosatVerification "../icp-intents-lib/HoosatVerification";

// Import ICRC-1/ICRC-2 token types
import ICRC2 "mo:icrc2-types";

shared(init_msg) persistent actor class BasicIntentCanister() = self {
  type Intent = Types.Intent;
  type IntentResult<T> = Types.IntentResult<T>;
  type CreateIntentRequest = Types.CreateIntentRequest;
  type SubmitQuoteRequest = Types.SubmitQuoteRequest;
  type PagedIntents = Types.PagedIntents;
  type EscrowAccount = Types.EscrowAccount;

  // STABLE STATE - Persists across upgrades (implicitly stable in persistent actor)
  var stableIntentState : ?{
    nextIntentId: Nat;
    intents: [(Nat, Intent)];
    events: [Types.Event];
    escrowAccounts: [((Principal, Text), EscrowAccount)];
  } = null;

  // Admin principal - set on first deployment, persists across upgrades
  var adminPrincipal : Principal = init_msg.caller;
  var feeCollectorPrincipal : Principal = init_msg.caller;

  // Token ledger configuration
  // Maps token identifiers to their ICRC-1 ledger canister IDs
  // Example: "ICP" -> ryjl3-tyaaa-aaaaa-aaaba-cai
  var tokenLedgers : [(Text, Principal)] = [];

  // Helper function to get ledger for a token
  func getLedger(token: Text) : ?ICRC2.Service {
    for ((tokenId, ledgerPrincipal) in tokenLedgers.vals()) {
      if (tokenId == token) {
        return ?(actor (Principal.toText(ledgerPrincipal)) : ICRC2.Service);
      };
    };
    null
  };

  // Protocol configuration (reconstructed on each upgrade)
  let protocolConfig : Types.ProtocolConfig = {
    default_protocol_fee_bps = 30;  // 0.3%
    max_protocol_fee_bps = 100;     // 1%
    min_intent_amount = 100_000;    // Minimum to prevent spam
    max_intent_lifetime = 7 * 24 * 60 * 60 * 1_000_000_000; // 7 days in nanoseconds
    max_active_intents = 10_000;    // Maximum concurrent active intents (prevents memory exhaustion)
    max_events = 1_000;              // Maximum events in buffer (circular buffer)
    admin = adminPrincipal;
    fee_collector = feeCollectorPrincipal;
    paused = false;
  };

  // tECDSA configuration (use test_key_1 for local/testing, key_1 for mainnet)
  let tecdsaConfig : Types.ECDSAConfig = {
    key_name = "test_key_1";
    derivation_path = [];
  };

  // Verification configuration
  // Replace with actual EVM RPC canister ID in production
  let verificationConfig = {
    evm_rpc_canister_id = Principal.fromText("7hfb6-caaaa-aaaar-qadga-cai");
    min_confirmations = 12;  // ~3 minutes on Ethereum
  };

  // Supported chains (mainnets and testnets)
  let supportedChains : [Nat] = [
    1,        // Ethereum mainnet
    8453,     // Base mainnet
    11155111, // Sepolia testnet (FREE!)
    84532,    // Base Sepolia testnet (FREE!)
  ];

  // Transient (non-stable) state - reconstructed from stable data on upgrade
  transient var intentState = IntentManager.init(
    protocolConfig,
    tecdsaConfig,
    verificationConfig,
    supportedChains
  );

  // Save state before upgrade
  system func preupgrade() {
    Debug.print("Saving state for upgrade...");
    stableIntentState := ?IntentManager.serializeState(intentState);
    Debug.print("Saved " # Nat.toText(intentState.intents.size()) # " intents");
  };

  // Restore state after upgrade
  system func postupgrade() {
    switch (stableIntentState) {
      case (?serialized) {
        Debug.print("Restoring state from upgrade...");
        intentState := IntentManager.deserializeState(
          protocolConfig,
          tecdsaConfig,
          verificationConfig,
          supportedChains,
          serialized
        );
        Debug.print("Restored " # Nat.toText(intentState.intents.size()) # " intents");
        // Clear stable state to free memory
        stableIntentState := null;
      };
      case null {
        Debug.print("Fresh initialization - no state to restore");
      };
    };
  };

  // ===========================
  // USER-FACING ENDPOINTS
  // ===========================

  /// Post a new intent
  public shared(msg) func postIntent(request: CreateIntentRequest) : async IntentResult<Nat> {
    await IntentManager.postIntent(intentState, msg.caller, request, Time.now())
  };

  /// Get intent by ID
  public query func getIntent(id: Nat) : async ?Intent {
    IntentManager.getIntent(intentState, id)
  };

  /// Get paginated billboard of intents
  public query func getIntents(offset: Nat, limit: Nat) : async PagedIntents {
    IntentManager.getIntents(intentState, offset, limit)
  };

  /// Get user's own intents
  public query(msg) func getMyIntents() : async [Intent] {
    IntentManager.getUserIntents(intentState, msg.caller)
  };

  /// Confirm a quote and lock escrow
  /// Returns the generated deposit address for the solver
  public shared(msg) func confirmQuote(
    intentId: Nat,
    quoteIndex: Nat
  ) : async IntentResult<Text> {
    await IntentManager.confirmQuote(intentState, msg.caller, intentId, quoteIndex, Time.now())
  };

  /// Cancel an open intent
  public shared(msg) func cancelIntent(intentId: Nat) : async IntentResult<()> {
    IntentManager.cancelIntent(intentState, msg.caller, intentId, Time.now())
  };

  // ===========================
  // SOLVER-FACING ENDPOINTS
  // ===========================

  /// Submit a quote for an intent
  public shared(msg) func submitQuote(request: SubmitQuoteRequest) : async IntentResult<()> {
    IntentManager.submitQuote(intentState, msg.caller, request, Time.now())
  };

  /// Claim fulfillment for a locked intent
  /// Verifies the deposit, releases escrow, and pays solver
  public shared func claimFulfillment(
    intentId: Nat,
    txHashHint: ?Text
  ) : async IntentResult<()> {
    let currentTime = Time.now();

    // STEP 1: Prepare verification (pure function)
    let verificationRequest = switch (IntentManager.prepareClaimFulfillment(intentState, intentId, txHashHint)) {
      case (#err(e)) { return #err(e) };
      case (#ok(req)) { req };
    };

    // STEP 2: Get intent for custom RPC URLs
    let intent = switch (IntentManager.getIntent(intentState, intentId)) {
      case null { return #err(#NotFound) };
      case (?i) { i };
    };

    // STEP 3: Verify based on destination chain
    let verificationResult = if (Text.equal(intent.destination.chain, "hoosat")) {
      // Hoosat UTXO verification
      let hoosatConfig : HoosatVerification.HoosatConfig = {
        rpc_url = switch (intent.custom_rpc_urls) {
          case (?urls) { if (urls.size() > 0) { urls[0] } else { "" } };
          case null { "" };
        };
        network = intent.destination.network;
        confirmations = 10;
        ecdsa_key_name = tecdsaConfig.key_name;
      };

      let hoosatRequest : HoosatVerification.HoosatVerificationRequest = {
        tx_id = verificationRequest.txHash;
        expected_address = verificationRequest.depositAddress;
        expected_amount = verificationRequest.expectedAmount;
        output_index = 0; // Typically first output
      };

      switch (await HoosatVerification.verifyUTXO(hoosatRequest, hoosatConfig)) {
        case (#Success(utxo)) {
          #Success({
            amount = utxo.amount;
            tx_hash = verificationRequest.txHash;
          })
        };
        case (#Failed(msg)) { #Failed(msg) };
      };
    } else {
      // Ethereum verification (existing flow)
      // For EVM chains, chainId must be present
      let chainId = switch (verificationRequest.chainId) {
        case (?id) { id };
        case null { return #err(#InvalidChain) };
      };

      let evmRpc = Verification.getEVMRPC(verificationConfig.evm_rpc_canister_id);
      let rpcServices = Verification.chainIdToRpcServices(chainId, intent.custom_rpc_urls);

      // Fetch receipt (for success status and destination address)
      let rpcResponse = await (with cycles = 10_000_000_000) evmRpc.eth_getTransactionReceipt(
        rpcServices,
        null,
        verificationRequest.txHash
      );

      // Fetch transaction using multi_request (to get value field)
      let jsonRpcRequest = "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionByHash\",\"params\":[\"" # verificationRequest.txHash # "\"],\"id\":1}";

      let txResponse = await (with cycles = 10_000_000_000) evmRpc.multi_request(
        rpcServices,
        null,
        jsonRpcRequest
      );

      // Extract from multi-provider responses
      let receipt = Verification.extractReceipt(rpcResponse);
      let txValue = Verification.parseTransactionValue(txResponse);

      // If parsing failed, return error
      if (Option.isNull(txValue)) {
        let jsonStr = Verification.extractJsonString(txResponse);
        let errorMsg = switch (jsonStr) {
          case (?json) { "Could not parse transaction value. JSON: " # json };
          case null {
            let rpcErrorMsg = switch (txResponse) {
              case (#Consistent(#Err(err))) { "EVM RPC error: " # debug_show(err) };
              case (#Inconsistent(results)) { "EVM RPC inconsistent responses: " # debug_show(results) };
              case _ { "Could not parse transaction value. No JSON response received." };
            };
            rpcErrorMsg
          };
        };
        return #err(#VerificationFailed(errorMsg));
      };

      // Validate receipt AND transaction value
      Verification.validateTransactionReceipt(
        receipt,
        txValue,
        verificationRequest.depositAddress,
        verificationRequest.expectedAmount,
        verificationRequest.txHash
      )
    };

    // STEP 6: Finalize fulfillment (pure function - updates state)
    let finalizeResult = IntentManager.finalizeFulfillment(
      intentState,
      intentId,
      verificationResult,
      verificationRequest.txHash,
      currentTime
    );

    switch (finalizeResult) {
      case (#err(e)) { return #err(e) };
      case (#ok(())) {
        // STEP 7: Handle token transfers (actor responsibility)
        // Get token from source ChainAsset
        let sourceToken = intent.source.token;

        // Calculate amounts
        let solverAmount = intent.source_amount;
        let protocolFee = Utils.calculateFee(intent.source_amount, protocolConfig.default_protocol_fee_bps);
        let totalLocked = solverAmount + protocolFee;

        // Get solver principal from selected quote
        let solver = switch (intent.selected_quote) {
          case null { return #err(#InvalidStatus("No quote selected")) };
          case (?quote) { quote.solver };
        };

        // Release escrow (unlock and release)
        ignore Escrow.unlock(intentState.escrow, intent.user, sourceToken, totalLocked);
        ignore Escrow.release(intentState.escrow, intent.user, sourceToken, totalLocked);

        // Get ledger for token
        let ledger = switch (getLedger(sourceToken)) {
          case null { return #err(#InvalidToken) };
          case (?l) { l };
        };

        // Transfer to solver
        let solverTransferArgs : ICRC2.TransferArgs = {
          from_subaccount = null;
          to = {
            owner = solver;
            subaccount = null;
          };
          amount = solverAmount;
          fee = null;
          memo = null;
          created_at_time = null;
        };

        let solverTransferResult = await ledger.icrc1_transfer(solverTransferArgs);

        switch (solverTransferResult) {
          case (#Err(_)) {
            // Transfer to solver failed - this is critical
            Debug.print("CRITICAL: Failed to pay solver for intent " # Nat.toText(intentId));
            return #err(#InternalError("Failed to transfer tokens to solver"));
          };
          case (#Ok(_)) {};
        };

        // Transfer fee to fee collector (if fee > 0)
        if (protocolFee > 0) {
          let feeTransferArgs : ICRC2.TransferArgs = {
            from_subaccount = null;
            to = {
              owner = feeCollectorPrincipal;
              subaccount = null;
            };
            amount = protocolFee;
            fee = null;
            memo = null;
            created_at_time = null;
          };

          let feeTransferResult = await ledger.icrc1_transfer(feeTransferArgs);

          switch (feeTransferResult) {
            case (#Err(_)) {
              // Fee transfer failed - log but don't fail the whole operation
              Debug.print("WARNING: Failed to collect protocol fee for intent " # Nat.toText(intentId));
            };
            case (#Ok(_)) {};
          };
        };

        #ok(())
      };
    };
  };

  /// Get intents where solver has submitted quotes
  public query(msg) func getMySolverIntents() : async [Intent] {
    IntentManager.getSolverIntents(intentState, msg.caller)
  };

  // ===========================
  // ESCROW MANAGEMENT
  // ===========================

  /// Deposit funds into escrow
  /// Uses ICRC-2 transferFrom to pull tokens from user (requires prior approval)
  public shared(msg) func depositEscrow(token: Text, amount: Nat) : async IntentResult<()> {
    // Get the ledger for this token
    let ledger = switch (getLedger(token)) {
      case null { return #err(#InvalidToken) };
      case (?l) { l };
    };

    // Use ICRC-2 transferFrom to pull tokens from user to canister
    // User must approve the canister first
    let transferFromArgs : ICRC2.TransferFromArgs = {
      spender_subaccount = null;
      from = {
        owner = msg.caller;
        subaccount = null;
      };
      to = {
        owner = Principal.fromActor(self);
        subaccount = null;
      };
      amount = amount;
      fee = null;  // Use default fee
      memo = null;
      created_at_time = null;
    };

    let transferResult = await ledger.icrc2_transfer_from(transferFromArgs);

    switch (transferResult) {
      case (#Ok(_blockIndex)) {
        // Transfer succeeded, credit user's escrow balance
        Escrow.deposit(intentState.escrow, msg.caller, token, amount)
      };
      case (#Err(#InsufficientFunds { balance = _ })) {
        #err(#InsufficientBalance)
      };
      case (#Err(#InsufficientAllowance { allowance = _ })) {
        #err(#InternalError("Insufficient allowance - please approve tokens first"))
      };
      case (#Err(#BadFee { expected_fee = _ })) {
        #err(#InternalError("Bad fee"))
      };
      case (#Err(_)) {
        #err(#InternalError("Transfer failed"))
      };
    };
  };

  /// Withdraw available funds from escrow
  /// Deducts from escrow, then transfers tokens back to user
  public shared(msg) func withdrawEscrow(token: Text, amount: Nat) : async IntentResult<Nat> {
    // First withdraw from escrow (updates state)
    let withdrawResult = Escrow.withdraw(intentState.escrow, msg.caller, token, amount);

    switch (withdrawResult) {
      case (#err(e)) { return #err(e) };
      case (#ok(withdrawnAmount)) {
        // Get the ledger for this token
        let ledger = switch (getLedger(token)) {
          case null { return #err(#InvalidToken) };
          case (?l) { l };
        };

        // Transfer tokens from canister back to user
        let transferArgs : ICRC2.TransferArgs = {
          from_subaccount = null;
          to = {
            owner = msg.caller;
            subaccount = null;
          };
          amount = withdrawnAmount;
          fee = null;  // Use default fee
          memo = null;
          created_at_time = null;
        };

        let transferResult = await ledger.icrc1_transfer(transferArgs);

        switch (transferResult) {
          case (#Ok(_blockIndex)) {
            // Transfer succeeded
            #ok(withdrawnAmount)
          };
          case (#Err(_)) {
            // Transfer failed - credit the amount back to escrow
            ignore Escrow.deposit(intentState.escrow, msg.caller, token, withdrawnAmount);
            #err(#InternalError("Transfer failed"))
          };
        };
      };
    };
  };

  /// Get escrow balance
  public query(msg) func getEscrowBalance(token: Text) : async EscrowAccount {
    Escrow.getBalance(intentState.escrow, msg.caller, token)
  };

  /// Get all escrow accounts for caller
  public query(msg) func getMyEscrowAccounts() : async [EscrowAccount] {
    Escrow.getUserAccounts(intentState.escrow, msg.caller)
  };

  // ===========================
  // BACKGROUND TASKS
  // ===========================

  func checkExpiredIntents() : async () {
    let currentTime = Time.now();
    let allIntents = IntentManager.getIntents(intentState, 0, 1000);  // Get all

    for (intent in allIntents.data.vals()) {
      if (Utils.hasPassed(intent.deadline, currentTime)) {
        switch (intent.status) {
          case (#Locked) {
            ignore IntentManager.refundIntent(intentState, intent.id, currentTime);
            Debug.print("Refunded expired intent: " # Nat.toText(intent.id));
          };
          case _ {};
        };
      };
    };
  };

  /// Background task: Check for expired intents and trigger refunds
  /// Runs every 5 minutes
  transient let _refundTimer = Timer.recurringTimer<system>(
    #seconds(300),
    func() : async () {
      await checkExpiredIntents();
    }
  );

  // ===========================
  // ADMIN ENDPOINTS
  // ===========================

  /// Pause the system (admin only)
  public shared(msg) func pauseSystem() : async Result.Result<(), Text> {
    if (not Principal.equal(msg.caller, protocolConfig.admin)) {
      return #err("Unauthorized");
    };
    // In production, update config in stable var
    #ok(())
  };

  /// Transfer admin rights (admin only)
  public shared(msg) func setAdmin(newAdmin: Principal) : async Result.Result<(), Text> {
    if (not Principal.equal(msg.caller, adminPrincipal)) {
      return #err("Unauthorized: Only current admin can transfer admin rights");
    };
    adminPrincipal := newAdmin;
    Debug.print("Admin transferred to: " # Principal.toText(newAdmin));
    #ok(())
  };

  /// Update fee collector (admin only)
  public shared(msg) func setFeeCollector(newFeeCollector: Principal) : async Result.Result<(), Text> {
    if (not Principal.equal(msg.caller, adminPrincipal)) {
      return #err("Unauthorized: Admin only");
    };
    feeCollectorPrincipal := newFeeCollector;
    Debug.print("Fee collector updated to: " # Principal.toText(newFeeCollector));
    #ok(())
  };

  /// Register a token and its ICRC-1 ledger canister (admin only)
  /// Example: registerToken("ICP", "ryjl3-tyaaa-aaaaa-aaaba-cai")
  public shared(msg) func registerToken(
    tokenId: Text,
    ledgerCanisterId: Principal
  ) : async Result.Result<(), Text> {
    if (not Principal.equal(msg.caller, adminPrincipal)) {
      return #err("Unauthorized: Admin only");
    };

    // Check if token already registered, update if so
    var found = false;
    let updatedLedgers = Array.map<(Text, Principal), (Text, Principal)>(
      tokenLedgers,
      func((id, principal)) {
        if (id == tokenId) {
          found := true;
          (tokenId, ledgerCanisterId)
        } else {
          (id, principal)
        }
      }
    );

    if (found) {
      tokenLedgers := updatedLedgers;
      Debug.print("Updated token " # tokenId # " -> " # Principal.toText(ledgerCanisterId));
    } else {
      // Add new token
      tokenLedgers := Array.append(
        tokenLedgers,
        [(tokenId, ledgerCanisterId)]
      );
      Debug.print("Registered token " # tokenId # " -> " # Principal.toText(ledgerCanisterId));
    };

    #ok(())
  };

  /// Get registered tokens (query)
  public query func getRegisteredTokens() : async [(Text, Principal)] {
    tokenLedgers
  };

  /// Get current admin (query)
  public query func getAdmin() : async Principal {
    adminPrincipal
  };

  /// Get system stats
  public query func getStats() : async {
    total_intents: Nat;
    open_intents: Nat;
    fulfilled_intents: Nat;
  } {
    let allIntents = IntentManager.getIntents(intentState, 0, 10000);
    var open = 0;
    var fulfilled = 0;

    for (intent in allIntents.data.vals()) {
      switch (intent.status) {
        case (#Open or #Quoted) { open += 1 };
        case (#Fulfilled) { fulfilled += 1 };
        case _ {};
      };
    };

    {
      total_intents = allIntents.total;
      open_intents = open;
      fulfilled_intents = fulfilled;
    }
  };

  /// Get canister cycles balance (monitoring)
  public query func getCyclesBalance() : async Nat {
    ExperimentalCycles.balance()
  };

  /// Check if cycles balance is critically low
  public query func isLowOnCycles() : async {
    balance: Nat;
    isLow: Bool;
    threshold: Nat;
  } {
    let balance = ExperimentalCycles.balance();
    let threshold = 1_000_000_000_000; // 1T cycles (minimum safe threshold)
    {
      balance = balance;
      isLow = balance < threshold;
      threshold = threshold;
    }
  };

  // ===========================
  // HELPER ENDPOINTS
  // ===========================

  /// Validate an Ethereum address
  public query func validateAddress(address: Text) : async Bool {
    Utils.isValidEthAddress(address)
  };

  /// Calculate protocol fee for an amount
  public query func calculateFee(amount: Nat) : async Nat {
    Utils.calculateFee(amount, protocolConfig.default_protocol_fee_bps)
  };
}
