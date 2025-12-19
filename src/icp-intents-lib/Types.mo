/// Core type definitions for the ICP Intents cross-chain swap library.
/// These types can be imported and used in any Motoko canister.
///
/// Example usage:
/// ```motoko
/// import Types "mo:icp-intents/Types";
///
/// let intent : Types.Intent = {
///   id = 1;
///   user = caller;
///   source_amount = 1_000_000_000;
///   // ... other fields
/// };
/// ```

import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Result "mo:base/Result";

module {
  /// Intent status lifecycle
  public type IntentStatus = {
    #Open;      /// Intent posted, accepting quotes
    #Quoted;    /// At least one quote submitted
    #Locked;    /// User confirmed, escrow locked, awaiting solver deposit
    #Fulfilled; /// Verified and funds released
    #Refunded;  /// Deadline passed or cancelled, funds returned
    #Cancelled; /// User cancelled before locking
  };

  /// Fully extensible chain asset definition
  /// Works for ANY blockchain (ICP, EVM, Bitcoin, Solana, etc.)
  public type ChainAsset = {
    chain: Text;        /// "icp", "ethereum", "base", "bitcoin", "solana", etc.
    chain_id: ?Nat;     /// For EVM chains: 1, 8453, 11155111, etc. (null for non-EVM)
    token: Text;        /// "native", ERC20 address, or ICRC-1 canister ID
    network: Text;      /// "mainnet", "testnet", "sepolia", etc.
  };

  /// Quote from a solver
  public type Quote = {
    solver: Principal;
    output_amount: Nat;  /// Amount solver will provide on dest chain
    fee: Nat;            /// Solver's fee in source token units
    expiry: Time.Time;   /// Quote valid until this timestamp
    submitted_at: Time.Time;
  };

  /// Main intent structure (fully extensible for any chain pair!)
  public type Intent = {
    id: Nat;
    user: Principal;

    /// Universal source/destination design (works for ANY chain combo)
    source: ChainAsset;       /// What user is offering
    destination: ChainAsset;  /// What user wants
    dest_recipient: Text;     /// Recipient address on destination chain

    /// Amounts
    source_amount: Nat;       /// Amount user wants to swap
    min_output: Nat;          /// Minimum acceptable output (slippage protection)

    /// Lifecycle timestamps
    created_at: Time.Time;
    deadline: Time.Time;     /// Auto-refund after this time
    status: IntentStatus;

    /// Quote management
    quotes: [Quote];
    selected_quote: ?Quote;  /// Quote user confirmed

    /// Escrow and fulfillment tracking
    escrow_balance: Nat;     /// Actual escrowed amount (includes fee)
    generated_address: ?Text; /// tECDSA-derived deposit address for solver
    solver_tx_hash: ?Text;   /// Tx hash hint from solver (optional)
    verified_at: ?Time.Time; /// Verification success timestamp

    /// Economics
    protocol_fee_bps: Nat;   /// Protocol fee in basis points (30 = 0.3%)

    /// Extensibility hooks (for future/custom chains)
    custom_rpc_urls: ?[Text];     /// User-provided RPC endpoints
    verification_hints: ?Text;    /// Custom verification data (JSON, etc.)
    metadata: ?Text;              /// Arbitrary metadata
  };

  /// Configuration for a supported blockchain
  public type ChainConfig = {
    chain_id: Nat;
    name: Text;
    native_symbol: Text;     /// "ETH", "BNB", etc.
    block_confirmations: Nat; /// Blocks to wait for finality
    is_evm: Bool;            /// True for EVM chains (enables EVM RPC)
  };

  /// Escrow account (per user, per token)
  public type EscrowAccount = {
    owner: Principal;
    token: Text;     /// "ICP" or ICRC-1 canister ID
    balance: Nat;
    locked: Nat;     /// Amount locked in active intents
    available: Nat;  /// balance - locked
  };

  /// tECDSA configuration
  public type ECDSAConfig = {
    key_name: Text;  /// "test_key_1" (testnet) or "key_1" (mainnet)
    derivation_path: [Blob]; /// Base path for derivation
  };

  /// Verification result from chain verification
  public type VerificationResult = {
    #Success: { amount: Nat; tx_hash: Text };
    #Pending;
    #Failed: Text;
  };

  /// Comprehensive error type
  public type IntentError = {
    #NotFound;
    #Unauthorized;
    #InvalidStatus: Text;
    #InsufficientBalance;
    #QuoteExpired;
    #DeadlinePassed;
    #InvalidAmount;
    #InvalidChain;
    #InvalidToken;
    #InvalidAddress;
    #VerificationFailed: Text;
    #ECDSAError: Text;
    #RPCError: Text;
    #AlreadyExists;
    #InternalError: Text;
  };

  /// Standard result type for library functions
  public type IntentResult<T> = Result.Result<T, IntentError>;

  /// Pagination request
  public type PageRequest = {
    offset: Nat;
    limit: Nat;  /// Max 100 recommended
  };

  /// Paginated intent response
  public type PagedIntents = {
    data: [Intent];
    total: Nat;
    offset: Nat;
    limit: Nat;
  };

  /// Event log entry (for monitoring/indexing)
  public type Event = {
    timestamp: Time.Time;
    event_type: EventType;
  };

  public type EventType = {
    #IntentPosted: { intent_id: Nat; user: Principal };
    #QuoteSubmitted: { intent_id: Nat; solver: Principal; amount: Nat };
    #IntentLocked: { intent_id: Nat; quote_index: Nat };
    #DepositVerified: { intent_id: Nat; amount: Nat; tx_hash: Text };
    #IntentFulfilled: { intent_id: Nat; released_amount: Nat };
    #IntentRefunded: { intent_id: Nat; reason: Text };
    #IntentCancelled: { intent_id: Nat };
  };

  /// Protocol-level configuration (customize per deployment)
  public type ProtocolConfig = {
    default_protocol_fee_bps: Nat;  /// Default fee (30 = 0.3%)
    max_protocol_fee_bps: Nat;      /// Maximum allowed (100 = 1%)
    min_intent_amount: Nat;         /// Anti-spam minimum
    max_intent_lifetime: Int;       /// Max deadline duration (nanoseconds)
    max_active_intents: Nat;        /// Maximum concurrent active intents (prevent memory exhaustion)
    max_events: Nat;                /// Maximum events to keep in buffer (circular buffer)
    admin: Principal;
    fee_collector: Principal;
    paused: Bool;
  };

  /// Create intent request (used by library consumers)
  public type CreateIntentRequest = {
    source: ChainAsset;       /// What user is offering
    destination: ChainAsset;  /// What user wants
    dest_recipient: Text;     /// Recipient address on destination chain
    source_amount: Nat;
    min_output: Nat;
    deadline: Time.Time;
    custom_rpc_urls: ?[Text];
    verification_hints: ?Text;
    metadata: ?Text;
  };

  /// Submit quote request
  public type SubmitQuoteRequest = {
    intent_id: Nat;
    output_amount: Nat;
    fee: Nat;
    expiry: Time.Time;
  };
}
