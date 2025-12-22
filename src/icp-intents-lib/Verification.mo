/// Cross-chain verification module for EVM chains.
/// Pure validation logic - does NOT make async calls.
/// The caller (actor) is responsible for fetching transaction receipts.
///
/// Architecture:
/// - Actor fetches data from EVM RPC (with proper cycles)
/// - This module validates the fetched data (pure functions)
///
/// Example usage:
/// ```motoko
/// import Verification "mo:icp-intents/Verification";
///
/// // Actor makes RPC call
/// let receipt = await evmRpc.eth_getTransactionReceipt(...);
///
/// // Module validates receipt
/// let result = Verification.validateReceipt(receipt, expectedAddress, expectedAmount);
/// ```

import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Nat16 "mo:base/Nat16";
import Nat64 "mo:base/Nat64";
import Int64 "mo:base/Int64";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Types "../icp-intents-lib/Types";
import Utils "../icp-intents-lib/Utils";

module {
  type IntentResult<T> = Types.IntentResult<T>;
  type IntentError = Types.IntentError;
  type VerificationResult = Types.VerificationResult;

  /// Verification configuration
  public type Config = {
    evm_rpc_canister_id: Principal;  // Official EVM RPC canister
    min_confirmations: Nat;          // Minimum block confirmations
  };

  /// Re-export RPC types for actors to use
  public type RpcServices = RpcServices_;
  public type RpcConfig = RpcConfig_;
  public type TransactionReceipt = TransactionReceipt_;
  public type Transaction = Transaction_;
  public type MultiGetTransactionReceiptResult = MultiGetTransactionReceiptResult_;
  public type MultiGetTransactionResult = MultiGetTransactionResult_;
  public type GetTransactionReceiptResult = GetTransactionReceiptResult_;
  public type GetTransactionResult = GetTransactionResult_;
  public type RpcError = RpcError_;

  /// EVM RPC canister interface (official)
  public type EVMRPCCanister = actor {
    eth_getTransactionReceipt: (RpcServices_, ?RpcConfig_, Text) -> async MultiGetTransactionReceiptResult_;
    eth_getLogs: (GetLogsRequest) -> async GetLogsResult;
    multi_request: (RpcServices_, ?RpcConfig_, Text) -> async MultiJsonRequestResult;
  };

  type MultiJsonRequestResult = {
    #Consistent: JsonRequestResult;
    #Inconsistent: [(RpcService, JsonRequestResult)];
  };

  type JsonRequestResult = {
    #Ok: Text;
    #Err: RpcError_;
  };

  /// RPC request types from official EVM RPC canister
  type RpcServices_ = {
    #Custom: { chainId: Nat64; services: [RpcApi] };
    #EthSepolia: ?[EthSepoliaService];
    #EthMainnet: ?[EthMainnetService];
    #ArbitrumOne: ?[L2MainnetService];
    #BaseMainnet: ?[L2MainnetService];
    #OptimismMainnet: ?[L2MainnetService];
  };

  type RpcConfig_ = {
    responseSizeEstimate: ?Nat64;
    responseConsensus: ?ConsensusStrategy;
  };

  type ConsensusStrategy = {
    #Equality;
    #Threshold: { total: Nat; min: Nat };
  };

  type RpcApi = { url: Text; headers: ?[HttpHeader] };
  type HttpHeader = { name: Text; value: Text };
  type EthSepoliaService = { #Alchemy; #BlockPi; #PublicNode; #Ankr };
  type EthMainnetService = { #Alchemy; #BlockPi; #Cloudflare; #PublicNode; #Ankr };
  type L2MainnetService = { #Alchemy; #BlockPi; #PublicNode; #Ankr };

  type MultiGetTransactionReceiptResult_ = {
    #Consistent: GetTransactionReceiptResult_;
    #Inconsistent: [(RpcService, GetTransactionReceiptResult_)];
  };

  type MultiGetTransactionResult_ = {
    #Consistent: GetTransactionResult_;
    #Inconsistent: [(RpcService, GetTransactionResult_)];
  };

  type RpcService = {
    #EthSepolia: EthSepoliaService;
    #EthMainnet: EthMainnetService;
    #Chain: Nat64;
    #Provider: Nat64;
  };

  type GetTransactionReceiptResult_ = {
    #Ok: ?TransactionReceipt_;
    #Err: RpcError_;
  };

  type GetTransactionResult_ = {
    #Ok: ?Transaction_;
    #Err: RpcError_;
  };

  // JsonRpcError from EVM RPC canister
  type JsonRpcError = {
    code: Int64;
    message: Text;
  };

  // Error types matching official EVM RPC canister
  type ProviderError = {
    #TooFewCycles : { expected: Nat; received: Nat };
    #MissingRequiredProvider;
    #ProviderNotFound;
    #NoPermission;
    #InvalidRpcConfig : Text;
  };

  type ValidationError = {
    #Custom : Text;
    #InvalidHex : Text;
  };

  type RejectionCode = {
    #NoError;
    #CanisterError;
    #SysTransient;
    #DestinationInvalid;
    #Unknown;
    #SysFatal;
    #CanisterReject;
  };

  type HttpOutcallError = {
    #IcError : { code: RejectionCode; message: Text };
    #InvalidHttpJsonRpcResponse : {
      status: Nat16;
      body: Text;
      parsingError: ?Text;
    };
  };

  // RpcError is a variant - matches EVM RPC canister
  type RpcError_ = {
    #JsonRpcError : JsonRpcError;
    #ProviderError : ProviderError;
    #ValidationError : ValidationError;
    #HttpOutcallError : HttpOutcallError;
  };

  type Transaction_ = {
    hash: Text;
    nonce: Nat;
    blockHash: ?Text;
    blockNumber: ?Nat;
    transactionIndex: ?Nat;
    from: Text;
    to: ?Text;
    value: Nat;  // THIS IS WHAT WE NEED!
    gas: Nat;
    gasPrice: Nat;
    input: Text;
  };

  type TransactionReceipt_ = {
    to: ?Text;
    status: ?Nat;
    transactionHash: Text;
    blockNumber: Nat;
    from: Text;
    logs: [LogEntry];
    blockHash: Text;
    // Note: "type" field from EVM RPC is omitted because it's a reserved keyword
    // Candid will ignore extra fields during deserialization
    transactionIndex: Nat;
    effectiveGasPrice: Nat;
    logsBloom: Text;
    contractAddress: ?Text;
    gasUsed: Nat;
    cumulativeGasUsed: Nat;
    root: ?Text;
  };

  type GetLogsRequest = {
    addresses: [Text];
    fromBlock: Text;
    toBlock: Text;
    topics: [[Text]];  // ERC20 Transfer topic filter
    chainId: Nat64;
  };

  type GetLogsResult = {
    #Ok: { logs: [LogEntry] };
    #Err: Text;
  };

  type LogEntry = {
    transactionHash: ?Text;
    blockNumber: ?Nat;
    data: Text;
    blockHash: ?Text;
    transactionIndex: ?Nat;
    topics: [Text];
    address: Text;
    logIndex: ?Nat;
    removed: Bool;
  };

  /// Get EVM RPC canister actor (for use by actors)
  public func getEVMRPC(canisterId: Principal) : EVMRPCCanister {
    actor(Principal.toText(canisterId))
  };

  /// Convert chain ID to RpcServices (helper for actors)
  public func chainIdToRpcServices(chainId: Nat, customRpcUrls: ?[Text]) : RpcServices_ {
    // If custom RPC URLs provided, use them
    switch (customRpcUrls) {
      case (?urls) {
        let services = Array.map<Text, RpcApi>(urls, func(url) {
          { url = url; headers = null }
        });
        #Custom({ chainId = Nat64.fromNat(chainId); services = services })
      };
      case null {
        // Use default providers
        switch (chainId) {
          case (1) { #EthMainnet(null) };      // Ethereum Mainnet
          case (11155111) { #EthSepolia(null) }; // Sepolia testnet
          case (8453) { #BaseMainnet(null) };   // Base Mainnet
          case (42161) { #ArbitrumOne(null) };  // Arbitrum One
          case (10) { #OptimismMainnet(null) }; // Optimism Mainnet
          case (_) {
            // For other chains, use Custom with empty services
            #Custom({ chainId = Nat64.fromNat(chainId); services = [] })
          };
        };
      };
    };
  };

  /// Helper: Extract receipt from multi-provider response
  /// Handles both Consistent and Inconsistent responses
  public func extractReceipt(response: MultiGetTransactionReceiptResult_) : ?TransactionReceipt_ {
    switch (response) {
      case (#Consistent(#Ok(receipt))) { receipt };
      case (#Consistent(#Err(_))) { null };
      case (#Inconsistent(results)) {
        // Try to find a valid receipt from any provider
        for ((_, result) in results.vals()) {
          switch (result) {
            case (#Ok(?receipt)) { return ?receipt };
            case _ {};
          };
        };
        null
      };
    }
  };

  /// Helper: Extract transaction from multi-provider response
  /// Handles both Consistent and Inconsistent responses
  public func extractTransaction(response: MultiGetTransactionResult_) : ?Transaction_ {
    switch (response) {
      case (#Consistent(#Ok(tx))) { tx };
      case (#Consistent(#Err(_))) { null };
      case (#Inconsistent(results)) {
        // Try to find a valid transaction from any provider
        for ((_, result) in results.vals()) {
          switch (result) {
            case (#Ok(?tx)) { return ?tx };
            case _ {};
          };
        };
        null
      };
    }
  };

  /// Helper: Extract JSON string from response (including from "Invalid" errors with status 200)
  public func extractJsonString(response: MultiJsonRequestResult) : ?Text {
    switch (response) {
      case (#Consistent(#Ok(json))) { ?json };
      case (#Consistent(#Err(#HttpOutcallError(#InvalidHttpJsonRpcResponse({ body; status; parsingError }))))) {
        // EVM RPC returns complex objects as "Invalid" because it expects simple values
        // But HTTP 200 means the JSON is actually valid - use the body
        if (status == 200) { ?body } else { null }
      };
      case (#Inconsistent(results)) {
        var foundJson : ?Text = null;
        for ((_, result) in results.vals()) {
          switch (result) {
            case (#Ok(json)) { foundJson := ?json };
            case (#Err(#HttpOutcallError(#InvalidHttpJsonRpcResponse({ body; status; parsingError })))) {
              if (status == 200) { foundJson := ?body };
            };
            case _ {};
          };
        };
        foundJson
      };
      case _ { null };
    }
  };

  /// Helper: Parse transaction value from raw JSON-RPC response
  /// Extracts the "value" field from eth_getTransactionByHash response
  public func parseTransactionValue(response: MultiJsonRequestResult) : ?Nat {
    // Extract JSON string (handles both #Ok and "Invalid" with status 200)
    let jsonString = switch (extractJsonString(response)) {
      case (?json) { json };
      case null { return null };
    };

    // Parse the "value" field from JSON
    // Format: {"jsonrpc":"2.0","id":1,"result":{"value":"0x...",...}}
    // Try both "value":" and "value": " (with space)

    // First try without space
    var parts = Iter.toArray(Text.split(jsonString, #text "\"value\":\""));
    if (parts.size() < 2) {
      // Try with space after colon
      parts := Iter.toArray(Text.split(jsonString, #text "\"value\": \""));
    };

    if (parts.size() < 2) {
      return null;
    };

    // Get the part after "value":"
    let afterValue = parts[1];

    // Find the closing quote (take everything until ")
    let valueParts = Iter.toArray(Text.split(afterValue, #text "\""));
    if (valueParts.size() < 1) {
      return null;
    };

    let hexValue = valueParts[0];
    // Convert hex to Nat
    Utils.hexToNat(hexValue)
  };

  /// Pure function: Validate transaction and receipt for native ETH deposit
  /// This is a pure function - NO async calls, NO side effects
  /// The actor is responsible for fetching the receipt and transaction value
  public func validateTransactionReceipt(
    receipt: ?TransactionReceipt_,
    txValue: ?Nat,
    expectedAddress: Text,
    expectedAmount: Nat,
    txHash: Text
  ) : VerificationResult {
    // Check receipt exists
    let r = switch (receipt) {
      case (?r) r;
      case null { return #Pending };  // Transaction not yet confirmed
    };

    // Check transaction value was parsed
    let actualValue = switch (txValue) {
      case (?v) v;
      case null { return #Failed("Could not parse transaction value") };
    };

    // Check transaction was successful
    let status = switch (r.status) {
      case (?s) s;
      case null { return #Failed("Transaction status unknown") };
    };

    if (status != 1) {
      return #Failed("Transaction failed (status: 0)");
    };

    // Verify recipient address matches
    let receiptTo = switch (r.to) {
      case (?t) Text.toLowercase(t);
      case null { return #Failed("Transaction has no recipient") };
    };

    let expectedTo = Text.toLowercase(expectedAddress);
    if (receiptTo != expectedTo) {
      return #Failed("Transaction sent to wrong address: " # receiptTo);
    };

    // CRITICAL: Verify the ETH value sent
    if (actualValue < expectedAmount) {
      return #Failed("Insufficient ETH sent: expected " # Nat.toText(expectedAmount) # " wei, got " # Nat.toText(actualValue) # " wei");
    };

    // Success! Return verified amount (the actual amount sent)
    #Success({
      amount = actualValue;  // Return actual amount, not expected
      tx_hash = txHash;
    })
  };


  /// Check if verification result is successful
  public func isSuccess(result: VerificationResult) : Bool {
    switch (result) {
      case (#Success(_)) true;
      case _ false;
    }
  };

  /// Check if verification is pending
  public func isPending(result: VerificationResult) : Bool {
    switch (result) {
      case (#Pending) true;
      case _ false;
    }
  };

  /// Get verified amount (if successful)
  public func getVerifiedAmount(result: VerificationResult) : ?Nat {
    switch (result) {
      case (#Success(data)) ?data.amount;
      case _ null;
    }
  };
}
