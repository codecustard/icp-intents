/// Simple Intent Pool Example
///
/// Demonstrates basic usage of the refactored ICP Intents library
/// Single-canister deployment with built-in EVM and Hoosat verification

import IntentLib "../../src/icp-intents-lib/IntentLib";
import EVM "../../src/icp-intents-lib/chains/EVM";
import Hoosat "../../src/icp-intents-lib/chains/Hoosat";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Debug "mo:base/Debug";

persistent actor SimpleIntentPool {

  /// Stable storage for upgrades
  var stable_data : ?IntentLib.StableManagerData = null;

  /// System configuration
  transient let config : IntentLib.SystemConfig = {
    protocol_fee_bps = 30; // 0.3% protocol fee
    fee_collector = Principal.fromText("aaaaa-aa"); // TODO: Set actual fee collector
    supported_chains = []; // Chains registered dynamically in initializeChains()
    min_intent_amount = 1_000_000; // Minimum 1M units
    max_intent_amount = 1_000_000_000_000_000; // Maximum 1 quadrillion units
    default_deadline_duration = 86_400_000_000_000; // 24 hours default
    solver_allowlist = null; // All solvers allowed
  };

  /// Runtime state
  transient var state : IntentLib.ManagerState = IntentLib.init(config);

  /// EVM configuration
  transient let evm_config : EVM.Config = {
    evm_rpc_canister = Principal.fromText("7hfb6-caaaa-aaaar-qadga-cai");
    min_confirmations = 6;
    ecdsa_key_name = "key_1"; // Use "test_key_1" for testnet
  };

  /// Hoosat configuration
  transient let hoosat_config : Hoosat.Config = {
    rpc_url = "https://api.network.hoosat.fi";
    min_confirmations = 10;
    ecdsa_key_name = "key_1";
  };

  /// Initialize supported chains
  private func initializeChains() {
    // Register Ethereum Mainnet
    IntentLib.registerChain(state, "ethereum", #EVM({
      chain_id = 1;
      name = "Ethereum Mainnet";
      network = "mainnet";
      rpc_urls = null;
    }));

    // Register Ethereum Sepolia (testnet)
    IntentLib.registerChain(state, "sepolia", #EVM({
      chain_id = 11155111;
      name = "Ethereum Sepolia";
      network = "testnet";
      rpc_urls = null;
    }));

    // Register Hoosat
    IntentLib.registerChain(state, "hoosat", #Hoosat({
      network = "mainnet";
      rpc_url = "https://api.network.hoosat.fi";
      min_confirmations = 10;
    }));

    // Register ICP (native IC tokens via ICRC-2)
    IntentLib.registerChain(state, "icp", #Custom({
      name = "Internet Computer";
      network = "mainnet";
      verification_canister = null; // No external verification needed for ICRC-2 tokens
      metadata = null;
    }));

    Debug.print("Initialized chains: " # debug_show(IntentLib.listChains(state)));
  };

  // Initialize on deployment
  initializeChains();

  // Token Management Functions

  /// Register a token ledger
  public shared({ caller = _ }) func registerToken(
    symbol : Text,
    ledger_principal : Principal,
    decimals : Nat8,
    fee : Nat
  ) : async () {
    // TODO: Add admin check
    IntentLib.registerToken(state, symbol, ledger_principal, decimals, fee);
    Debug.print("Registered token: " # symbol # " -> " # Principal.toText(ledger_principal));
  };

  /// Get token ledger principal
  public query func getTokenLedger(symbol : Text) : async ?Principal {
    IntentLib.getTokenLedger(state, symbol)
  };

  /// Deposit tokens from user to canister (after quote confirmation)
  /// User must have already called approve() on the token ledger
  public shared func depositTokens(intent_id : Nat) : async IntentLib.IntentResult<Nat> {
    let canister_principal = Principal.fromActor(SimpleIntentPool);
    await IntentLib.depositTokens(state, intent_id, canister_principal, Time.now())
  };

  /// Create a new intent
  ///
  /// Example: Swap 1 ETH on Ethereum for at least 50 HOO on Hoosat
  public shared({ caller }) func createIntent(
    source_chain : Text,
    source_token : Text,
    source_amount : Nat,
    dest_chain : Text,
    dest_token : Text,
    min_output : Nat,
    dest_recipient : Text,
    deadline_seconds : Nat // Deadline in seconds from now
  ) : async IntentLib.IntentResult<Nat> {
    let source : IntentLib.ChainSpec = {
      chain = source_chain;
      chain_id = null; // Auto-detect from chain name
      token = source_token;
      network = "mainnet";
    };

    let destination : IntentLib.ChainSpec = {
      chain = dest_chain;
      chain_id = null;
      token = dest_token;
      network = "mainnet";
    };

    let deadline = Time.now() + (deadline_seconds * 1_000_000_000);

    IntentLib.createIntent(
      state,
      caller,
      source,
      destination,
      source_amount,
      min_output,
      dest_recipient,
      deadline,
      Time.now()
    )
  };

  /// Submit a quote for an intent (solver function)
  public shared({ caller }) func submitQuote(
    intent_id : Nat,
    output_amount : Nat,
    solver_fee : Nat,
    solver_tip : Nat
  ) : async IntentLib.IntentResult<()> {
    IntentLib.submitQuote(
      state,
      intent_id,
      caller,
      output_amount,
      solver_fee,
      solver_tip,
      null, // solver can optionally provide their dest address
      Time.now()
    )
  };

  /// Confirm a quote (user selects best quote)
  public shared({ caller }) func confirmQuote(
    intent_id : Nat,
    solver : Principal
  ) : async IntentLib.IntentResult<()> {
    IntentLib.confirmQuote(
      state,
      intent_id,
      solver,
      caller,
      Time.now()
    )
  };

  /// Verify EVM deposit and mark intent as deposited
  public shared func verifyEVMDeposit(
    intent_id : Nat,
    tx_hash : Text
  ) : async IntentLib.IntentResult<()> {
    let intent = switch (IntentLib.getIntent(state, intent_id)) {
      case null { return #err(#NotFound) };
      case (?i) { i };
    };

    // Get chain config
    let chain = switch (IntentLib.getChain(state, intent.source.chain)) {
      case null {
        return #err(#ChainNotSupported(intent.source.chain));
      };
      case (?c) { c };
    };

    // Generate expected deposit address
    let context : IntentLib.AddressContext = {
      chain = chain;
      intent_id = intent_id;
      user = intent.user;
    };

    let expected_address = switch (await EVM.generateAddress(evm_config, context)) {
      case (#ok(addr)) { addr };
      case (#err(e)) { return #err(e) };
    };

    // Verify the deposit
    let request : IntentLib.VerificationRequest = {
      chain = chain;
      proof = #EVM({
        tx_hash = tx_hash;
        block_number = 0;
        from_address = "";
        to_address = expected_address;
        value = intent.source_amount;
        confirmations = 0;
      });
      expected_address = expected_address;
      expected_amount = intent.source_amount;
      custom_rpc_urls = null;
    };

    switch (await EVM.verify(evm_config, request)) {
      case (#Success(data)) {
        // Mark as deposited
        IntentLib.verifyAndMarkDeposited(
          state,
          intent_id,
          data.verified_amount,
          Time.now()
        )
      };
      case (#Pending(_)) {
        #err(#InvalidStatus("Deposit not yet confirmed"))
      };
      case (#Failed(msg)) {
        #err(#VerificationFailed(msg))
      };
    }
  };

  /// Verify Hoosat deposit and mark intent as deposited
  public shared func verifyHoosatDeposit(
    intent_id : Nat,
    tx_id : Text
  ) : async IntentLib.IntentResult<()> {
    let intent = switch (IntentLib.getIntent(state, intent_id)) {
      case null { return #err(#NotFound) };
      case (?i) { i };
    };

    let chain = switch (IntentLib.getChain(state, intent.source.chain)) {
      case null {
        return #err(#ChainNotSupported(intent.source.chain));
      };
      case (?c) { c };
    };

    // Generate expected deposit address
    let context : IntentLib.AddressContext = {
      chain = chain;
      intent_id = intent_id;
      user = intent.user;
    };

    let expected_address = switch (await Hoosat.generateAddress(hoosat_config, context)) {
      case (#ok(addr)) { addr };
      case (#err(e)) { return #err(e) };
    };

    // Verify the deposit
    let request : IntentLib.VerificationRequest = {
      chain = chain;
      proof = #UTXO({
        tx_id = tx_id;
        output_index = 0;
        amount = intent.source_amount;
        script_pubkey = "";
        confirmations = 0;
        address = expected_address;
      });
      expected_address = expected_address;
      expected_amount = intent.source_amount;
      custom_rpc_urls = null;
    };

    switch (await Hoosat.verify(hoosat_config, request)) {
      case (#Success(data)) {
        IntentLib.verifyAndMarkDeposited(
          state,
          intent_id,
          data.verified_amount,
          Time.now()
        )
      };
      case (#Pending(_)) {
        #err(#InvalidStatus("Deposit not yet confirmed"))
      };
      case (#Failed(msg)) {
        #err(#VerificationFailed(msg))
      };
    }
  };

  /// Fulfill an intent (after solver delivers on dest chain)
  public shared func fulfillIntent(intent_id : Nat) : async IntentLib.IntentResult<IntentLib.FeeBreakdown> {
    await IntentLib.fulfillIntent(state, intent_id, Time.now())
  };

  /// Cancel an intent
  public shared({ caller }) func cancelIntent(intent_id : Nat) : async IntentLib.IntentResult<()> {
    await IntentLib.cancelIntent(state, intent_id, caller, Time.now())
  };

  // Query Functions

  /// Get intent by ID
  public query func getIntent(id : Nat) : async ?IntentLib.Intent {
    IntentLib.getIntent(state, id)
  };

  /// Get user's intents
  public query func getUserIntents(user : Principal) : async [IntentLib.Intent] {
    IntentLib.getUserIntents(state, user)
  };

  /// Get supported chains
  public query func getSupportedChains() : async [Text] {
    IntentLib.listChains(state)
  };

  /// Get escrow balance for user and token
  public query func getEscrowBalance(user : Principal, token : Text) : async Nat {
    IntentLib.getEscrowBalance(state, user, token)
  };

  /// Get collected protocol fees
  public query func getProtocolFees() : async [(Text, Nat)] {
    IntentLib.getAllCollectedFees(state)
  };

  /// Generate deposit address for an intent
  public shared func generateDepositAddress(intent_id : Nat) : async IntentLib.IntentResult<Text> {
    let intent = switch (IntentLib.getIntent(state, intent_id)) {
      case null { return #err(#NotFound) };
      case (?i) { i };
    };

    let chain = switch (IntentLib.getChain(state, intent.source.chain)) {
      case null {
        return #err(#ChainNotSupported(intent.source.chain));
      };
      case (?c) { c };
    };

    let context : IntentLib.AddressContext = {
      chain = chain;
      intent_id = intent_id;
      user = intent.user;
    };

    // Generate address based on chain type
    switch (chain) {
      case (#EVM(_)) {
        await EVM.generateAddress(evm_config, context)
      };
      case (#Hoosat(_)) {
        await Hoosat.generateAddress(hoosat_config, context)
      };
      case (_) {
        #err(#ChainNotSupported("Address generation not supported for this chain"))
      };
    }
  };

  // Admin Functions

  /// Register a new chain (admin only)
  public shared({ caller = _ }) func registerChain(
    name : Text,
    chain : IntentLib.Chain
  ) : async () {
    // TODO: Add admin check using caller
    IntentLib.registerChain(state, name, chain);
  };

  // System Functions

  /// Upgrade hooks
  system func preupgrade() {
    stable_data := ?IntentLib.toStable(state);
    Debug.print("Pre-upgrade: Exported state");
  };

  system func postupgrade() {
    state := switch (stable_data) {
      case (?data) {
        Debug.print("Post-upgrade: Importing state");
        IntentLib.fromStable(data, config)
      };
      case null {
        Debug.print("Post-upgrade: No stable data, using fresh state");
        state
      };
    };
    stable_data := null;

    // Re-initialize chains after upgrade
    initializeChains();

    // Verify escrow invariants
    if (not IntentLib.verifyEscrowInvariants(state)) {
      Debug.print("⚠️ WARNING: Escrow invariants violated after upgrade!");
    } else {
      Debug.print("✓ Escrow invariants verified");
    };
  };
}
