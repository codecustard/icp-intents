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
import Debug "mo:base/Debug";
import Result "mo:base/Result";

// Import the library modules
import Types "../icp-intents-lib/Types";
import IntentManager "../icp-intents-lib/IntentManager";
import Escrow "../icp-intents-lib/Escrow";
import Utils "../icp-intents-lib/Utils";

shared(init_msg) persistent actor class BasicIntentCanister() = self {
  type Intent = Types.Intent;
  type IntentResult<T> = Types.IntentResult<T>;
  type CreateIntentRequest = Types.CreateIntentRequest;
  type SubmitQuoteRequest = Types.SubmitQuoteRequest;
  type PagedIntents = Types.PagedIntents;
  type EscrowAccount = Types.EscrowAccount;

  // Stable state for upgrades
  var stableIntentState : ?{
    nextIntentId: Nat;
    intents: [(Nat, Intent)];
    events: [Types.Event];
    escrowAccounts: [(Principal, Text, EscrowAccount)];
  } = null;

  // Protocol configuration (transient)
  transient let protocolConfig : Types.ProtocolConfig = {
    default_protocol_fee_bps = 30;  // 0.3%
    max_protocol_fee_bps = 100;     // 1%
    min_intent_amount = 100_000;    // Minimum to prevent spam
    max_intent_lifetime = 7 * 24 * 60 * 60 * 1_000_000_000; // 7 days in nanoseconds
    admin = init_msg.caller;
    fee_collector = init_msg.caller;  // Could be treasury canister
    paused = false;
  };

  // tECDSA configuration (use test_key_1 for local/testing, key_1 for mainnet)
  transient let tecdsaConfig : Types.ECDSAConfig = {
    key_name = "test_key_1";
    derivation_path = [];
  };

  // Verification configuration
  // Replace with actual EVM RPC canister ID in production
  transient let verificationConfig = {
    evm_rpc_canister_id = Principal.fromText("7hfb6-caaaa-aaaar-qadga-cai");
    min_confirmations = 12;  // ~3 minutes on Ethereum
  };

  // Supported chains (mainnets and testnets)
  transient let supportedChains : [Nat] = [
    1,        // Ethereum mainnet
    8453,     // Base mainnet
    11155111, // Sepolia testnet (FREE!)
    84532,    // Base Sepolia testnet (FREE!)
  ];

  // Initialize state (transient)
  transient var intentState = IntentManager.init(
    protocolConfig,
    tecdsaConfig,
    verificationConfig,
    supportedChains
  );

  // Restore state after upgrade
  system func postupgrade() {
    switch (stableIntentState) {
      case (? state) {
        // Restore state (simplified - in production, properly reconstruct HashMap)
        Debug.print("Restored " # Nat.toText(state.intents.size()) # " intents");
      };
      case null {};
    };
  };

  // Save state before upgrade
  system func preupgrade() {
    // Save state (simplified - in production, properly serialize HashMap)
    Debug.print("Saving state for upgrade");
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
  /// Verifies the deposit and releases escrow
  public shared func claimFulfillment(
    intentId: Nat,
    txHashHint: ?Text
  ) : async IntentResult<()> {
    await IntentManager.claimFulfillment(intentState, intentId, txHashHint, Time.now())
  };

  /// Get intents where solver has submitted quotes
  public query(msg) func getMySolverIntents() : async [Intent] {
    IntentManager.getSolverIntents(intentState, msg.caller)
  };

  // ===========================
  // ESCROW MANAGEMENT
  // ===========================

  /// Deposit funds into escrow
  /// In production, integrate with ICP Ledger or ICRC-1 transfers
  public shared(msg) func depositEscrow(token: Text, amount: Nat) : async IntentResult<()> {
    // TODO: Add actual token transfer logic
    // For ICP: await Ledger.transfer(...)
    // For ICRC-1: await ICRC1.icrc1_transfer(...)

    Escrow.deposit(intentState.escrow, msg.caller, token, amount)
  };

  /// Withdraw available funds from escrow
  public shared(msg) func withdrawEscrow(token: Text, amount: Nat) : async IntentResult<Nat> {
    let result = Escrow.withdraw(intentState.escrow, msg.caller, token, amount);

    // TODO: Transfer funds back to user
    // For ICP: await Ledger.transfer(to: msg.caller, amount: amount)

    result
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
