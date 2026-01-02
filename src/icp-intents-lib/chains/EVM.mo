/// EVM chain verification implementation
///
/// Provides transaction verification for Ethereum and EVM-compatible chains

import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Char "mo:base/Char";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Error "mo:base/Error";
import Debug "mo:base/Debug";
import Types "../core/Types";
import ChainTypes "../chains/ChainTypes";
import TECDSA "../crypto/TECDSA";

module {
  type IntentResult<T> = Types.IntentResult<T>;
  type IntentError = Types.IntentError;
  type VerificationRequest = ChainTypes.VerificationRequest;
  type VerificationResult = ChainTypes.VerificationResult;
  type AddressContext = ChainTypes.AddressContext;
  type EVMChain = ChainTypes.EVMChain;
  type EVMProof = ChainTypes.EVMProof;

  /// EVM verification configuration
  public type Config = {
    evm_rpc_canister : Principal; // Official EVM RPC canister
    min_confirmations : Nat;
    ecdsa_key_name : Text;
  };

  /// Transaction receipt from EVM RPC
  public type TransactionReceipt = {
    to : ?Text;
    status : ?Nat;
    transactionHash : Text;
    blockNumber : Nat;
    from : Text;
    blockHash : Text;
    transactionIndex : Nat;
    effectiveGasPrice : Nat;
    gasUsed : Nat;
  };

  /// Transaction from EVM RPC
  public type Transaction = {
    hash : Text;
    from : Text;
    to : ?Text;
    value : Nat;
    blockNumber : ?Nat;
  };

  // EVM RPC types (from candid interface)
  type RpcServices = {
    #Custom : { chainId : Nat64; services : [RpcApi] };
    #EthSepolia : ?[EthSepoliaService];
    #EthMainnet : ?[EthMainnetService];
    #ArbitrumOne : ?[L2MainnetService];
    #BaseMainnet : ?[L2MainnetService];
    #OptimismMainnet : ?[L2MainnetService];
  };

  type RpcApi = { url : Text; headers : ?[HttpHeader] };
  type HttpHeader = { name : Text; value : Text };
  // Based on actual canister types from backtrace
  type L2Service = { #Alchemy; #Ankr; #BlockPi; #PublicNode };
  type EthSepoliaService = L2Service; // Shares type with other L2s
  type EthMainnetService = { #Alchemy; #Ankr; #BlockPi; #Cloudflare; #PublicNode };
  type L2MainnetService = L2Service;

  type JsonRpcError = { code : Int64; message : Text };
  type ProviderError = {
    #TooFewCycles : { expected : Nat; received : Nat };
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
    #IcError : { code : RejectionCode; message : Text };
    #InvalidHttpJsonRpcResponse : {
      status : Nat16;
      body : Text;
      parsingError : ?Text;
    };
  };
  type RpcError = {
    #JsonRpcError : JsonRpcError;
    #ProviderError : ProviderError;
    #ValidationError : ValidationError;
    #HttpOutcallError : HttpOutcallError;
  };

  type GetTransactionReceiptResult = {
    #Ok : ?TransactionReceipt;
    #Err : RpcError;
  };

  type MultiGetTransactionReceiptResult = {
    #Consistent : GetTransactionReceiptResult;
    #Inconsistent : [(RpcService, GetTransactionReceiptResult)];
  };

  type RpcService = {
    #EthSepolia : EthSepoliaService;
    #EthMainnet : EthMainnetService;
    #ArbitrumOne : L2MainnetService;
    #BaseMainnet : L2MainnetService;
    #OptimismMainnet : L2MainnetService;
    #Provider : Nat64;
    #Custom : RpcApi;
  };

  type MultiJsonRequestResult = {
    #Consistent : JsonRequestResult;
    #Inconsistent : [(RpcService, JsonRequestResult)];
  };

  type JsonRequestResult = {
    #Ok : Text;
    #Err : RpcError;
  };

  /// EVM RPC canister interface - use actual canister types
  /// Import the real types from deployed canister
  type EVMRPCCanister = actor {
    eth_getTransactionReceipt : (RpcServices, ?RpcConfig, Text) -> async MultiGetTransactionReceiptResult;
    multi_request : (RpcServices, ?RpcConfig, Text) -> async MultiJsonRequestResult;
  };

  type RpcConfig = {
    responseSizeEstimate : ?Nat64;
    responseConsensus : ?ConsensusStrategy;
  };

  type ConsensusStrategy = {
    #Equality;
    #Threshold : { total : ?Nat8; min : Nat8 };
  };

  /// Get EVM RPC canister actor
  func getRpcCanister(canister_id : Principal) : EVMRPCCanister {
    actor (Principal.toText(canister_id))
  };

  /// Convert chain ID to RPC services
  func chainIdToRpcServices(chain_id : Nat, custom_rpc : ?Text) : RpcServices {
    switch (custom_rpc) {
      case (?url) {
        #Custom({
          chainId = Nat64.fromNat(chain_id);
          services = [{ url = url; headers = null }];
        })
      };
      case null {
        switch (chain_id) {
          case (1) { #EthMainnet(null) };
          case (11155111) { #EthSepolia(?[#Alchemy]) }; // Use Alchemy for Sepolia
          case (8453) { #BaseMainnet(null) };
          case (42161) { #ArbitrumOne(null) };
          case (10) { #OptimismMainnet(null) };
          case (_) {
            #Custom({
              chainId = Nat64.fromNat(chain_id);
              services = [];
            })
          };
        };
      };
    };
  };

  /// Extract receipt from multi-provider response
  func extractReceipt(response : MultiGetTransactionReceiptResult) : ?TransactionReceipt {
    switch (response) {
      case (#Consistent(#Ok(receipt))) {
        Debug.print("EVM: Receipt extraction - got receipt: " # debug_show(receipt != null));
        receipt
      };
      case (#Consistent(#Err(err))) {
        Debug.print("EVM: Receipt extraction - error: " # debug_show(err));
        null
      };
      case (#Inconsistent(results)) {
        Debug.print("EVM: Receipt extraction - inconsistent results from " # debug_show(results.size()) # " providers");
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

  /// Extract JSON string from response
  func extractJsonString(response : MultiJsonRequestResult) : ?Text {
    switch (response) {
      case (#Consistent(#Ok(json))) {
        Debug.print("EVM: JSON response OK");
        ?json
      };
      case (#Consistent(#Err(#HttpOutcallError(#InvalidHttpJsonRpcResponse(errData))))) {
        // The body contains the actual JSON response even though it's marked as error
        Debug.print("EVM: Extracting from error body");
        ?errData.body
      };
      case (#Consistent(#Err(err))) {
        Debug.print("EVM: JSON response error: " # debug_show(err));
        null
      };
      case (#Inconsistent(results)) {
        Debug.print("EVM: JSON inconsistent results");
        for ((_, result) in results.vals()) {
          switch (result) {
            case (#Ok(json)) { return ?json };
            case (#Err(#HttpOutcallError(#InvalidHttpJsonRpcResponse(errData)))) {
              return ?errData.body
            };
            case _ {};
          };
        };
        null
      };
    }
  };

  /// Parse transaction value from JSON response
  /// Enhanced with validation and error handling
  func parseTransactionValue(json : Text) : ?Nat {
    // Try both common JSON formatting styles
    let patterns = [
      "\"value\":\"",
      "\"value\": \""
    ];

    var hexValue : ?Text = null;

    label patternLoop for (pattern in patterns.vals()) {
      let parts = Iter.toArray(Text.split(json, #text pattern));
      if (parts.size() >= 2) {
        let afterValue = parts[1];
        let valueParts = Iter.toArray(Text.split(afterValue, #text "\""));
        if (valueParts.size() >= 1) {
          hexValue := ?valueParts[0];
          break patternLoop;
        };
      };
    };

    switch (hexValue) {
      case null { null };
      case (?hex) {
        // Validate it looks like a hex string before parsing
        if (not isValidHexString(hex)) {
          return null;
        };
        hexToNat(hex)
      };
    }
  };

  /// Validate hex string format
  func isValidHexString(hex : Text) : Bool {
    if (Text.size(hex) == 0) {
      return false;
    };

    // Check for 0x prefix
    if (not Text.startsWith(hex, #text "0x")) {
      return false;
    };

    // Prevent excessive length (max 66 chars = 0x + 64 hex digits for uint256)
    if (Text.size(hex) > 66) {
      return false;
    };

    // Validate all characters after 0x are valid hex
    let cleanHex = Text.trimStart(hex, #text "0x");
    for (c in cleanHex.chars()) {
      switch (hexCharToNat(c)) {
        case null { return false };
        case (?_) {};
      };
    };

    true
  };

  /// Convert hex string to Nat
  /// Assumes hex string has already been validated
  func hexToNat(hex : Text) : ?Nat {
    let cleanHex = Text.trimStart(hex, #text "0x");

    // Empty string after removing 0x
    if (Text.size(cleanHex) == 0) {
      return ?0;
    };

    var result : Nat = 0;
    for (c in cleanHex.chars()) {
      let digit = hexCharToNat(c);
      switch (digit) {
        case (?d) {
          result := result * 16 + d;
        };
        case null { return null };
      };
    };
    ?result
  };

  /// Convert hex character to Nat
  func hexCharToNat(c : Char) : ?Nat {
    if (c >= '0' and c <= '9') {
      ?(Nat64.toNat(Nat64.fromNat32(Char.toNat32(c) - Char.toNat32('0'))))
    } else if (c >= 'a' and c <= 'f') {
      ?(Nat64.toNat(Nat64.fromNat32(Char.toNat32(c) - Char.toNat32('a') + 10)))
    } else if (c >= 'A' and c <= 'F') {
      ?(Nat64.toNat(Nat64.fromNat32(Char.toNat32(c) - Char.toNat32('A') + 10)))
    } else {
      null
    }
  };

  /// Calculate confirmations from block numbers (public for testing)
  public func calculateConfirmations(currentBlock : Nat, txBlock : Nat) : Nat {
    if (currentBlock >= txBlock) {
      (currentBlock - txBlock) + 1
    } else {
      0
    }
  };

  /// Verify EVM deposit transaction
  public func verify(config : Config, request : VerificationRequest) : async VerificationResult {
    // Note: Cycles are provided with each RPC call via the EVM RPC canister

    let proof = switch (request.proof) {
      case (#EVM(evm_proof)) { evm_proof };
      case _ {
        return #Failed("Invalid proof type for EVM verification");
      };
    };

    let chain = switch (request.chain) {
      case (#EVM(evm_chain)) { evm_chain };
      case _ {
        return #Failed("Invalid chain type for EVM verification");
      };
    };

    // Note: Chain ID verification would be done via block number/confirmations

    let rpc_services = chainIdToRpcServices(chain.chain_id, null);
    let rpc = getRpcCanister(config.evm_rpc_canister);

    try {
      // Get transaction receipt (with cycles for RPC call)
      let receipt_response = await (with cycles = 1_000_000_000) rpc.eth_getTransactionReceipt(
        rpc_services,
        ?{ responseSizeEstimate = ?1000; responseConsensus = null },
        proof.tx_hash
      );

      let receipt = switch (extractReceipt(receipt_response)) {
        case (?r) { r };
        case null {
          return #Pending({
            current_confirmations = 0;
            required_confirmations = config.min_confirmations;
          });
        };
      };

      // Get transaction details for value
      let tx_request = "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionByHash\",\"params\":[\"" # proof.tx_hash # "\"],\"id\":1}";
      let tx_response = await (with cycles = 1_000_000_000) rpc.multi_request(
        rpc_services,
        ?{ responseSizeEstimate = ?1000; responseConsensus = null },
        tx_request
      );

      let tx_value = switch (extractJsonString(tx_response)) {
        case (?json) {
          Debug.print("EVM: Transaction response: " # json);
          parseTransactionValue(json)
        };
        case null {
          Debug.print("EVM: No transaction response");
          null
        };
      };

      // Get current block number to calculate confirmations
      let block_request = "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}";
      let block_response = await (with cycles = 1_000_000_000) rpc.multi_request(
        rpc_services,
        ?{ responseSizeEstimate = ?200; responseConsensus = null },
        block_request
      );

      let current_block = switch (extractJsonString(block_response)) {
        case (?json) {
          Debug.print("EVM: Block number response: " # json);
          // Response might be just the hex value or wrapped in JSON
          // Try direct hex parsing first
          switch (hexToNat(json)) {
            case (?n) { n };
            case null {
              // Try JSON-RPC format: {"result":"0x..."}
              let parts = Iter.toArray(Text.split(json, #text "\"result\":\""));
              if (parts.size() < 2) {
                return #Failed("Could not parse current block number from: " # json);
              };
              let afterResult = parts[1];
              let resultParts = Iter.toArray(Text.split(afterResult, #text "\""));
              if (resultParts.size() < 1) {
                return #Failed("Could not extract block number");
              };
              switch (hexToNat(resultParts[0])) {
                case (?n) { n };
                case null {
                  return #Failed("Invalid block number format");
                };
              }
            };
          }
        };
        case null {
          return #Failed("Failed to get current block number");
        };
      };

      // Validate the transaction
      return validateTransaction(receipt, tx_value, request.expected_address, request.expected_amount, proof.tx_hash, current_block, config.min_confirmations)
    } catch (e) {
      #Failed("RPC call failed: " # Error.message(e))
    }
  };

  /// Validate transaction receipt and value
  func validateTransaction(
    receipt : TransactionReceipt,
    tx_value : ?Nat,
    expected_address : Text,
    expected_amount : Nat,
    tx_hash : Text,
    current_block : Nat,
    min_confirmations : Nat
  ) : VerificationResult {
    // Check transaction status
    let status = switch (receipt.status) {
      case (?s) { s };
      case null {
        return #Failed("Transaction status unknown");
      };
    };

    if (status != 1) {
      return #Failed("Transaction failed (status: 0)");
    };

    // Verify recipient address
    let receipt_to = switch (receipt.to) {
      case (?t) { Text.toLowercase(t) };
      case null {
        return #Failed("Transaction has no recipient");
      };
    };

    let expected_to = Text.toLowercase(expected_address);
    if (receipt_to != expected_to) {
      return #Failed("Address mismatch: " # receipt_to # " != " # expected_to);
    };

    // Verify amount
    let actual_value = switch (tx_value) {
      case (?v) { v };
      case null {
        return #Failed("Could not parse transaction value");
      };
    };

    if (actual_value < expected_amount) {
      return #Failed("Insufficient amount: " # Nat.toText(actual_value) # " < " # Nat.toText(expected_amount));
    };

    // Calculate confirmations
    let confirmations = calculateConfirmations(current_block, receipt.blockNumber);

    Debug.print("EVM: Confirmations: " # Nat.toText(confirmations) # " / " # Nat.toText(min_confirmations));

    // Check if we have enough confirmations
    if (confirmations < min_confirmations) {
      return #Pending({
        current_confirmations = confirmations;
        required_confirmations = min_confirmations;
      });
    };

    // Success with actual confirmations!
    #Success({
      verified_amount = actual_value;
      tx_hash = tx_hash;
      confirmations = confirmations;
      timestamp = 0; // Should be set by caller with Time.now()
    })
  };

  /// Generate EVM deposit address
  public func generateAddress(
    config : Config,
    context : AddressContext
  ) : async IntentResult<Text> {
    await TECDSA.generateAddress(context.chain, context, config.ecdsa_key_name)
  };

  /// Build EVM transaction (for reverse flow - ICP → EVM)
  public func buildTransaction(
    _config : Config,
    _utxo : Types.UTXO,
    _recipient : Text,
    _amount : Nat,
    _intent_id : Nat,
    _key_name : Text
  ) : async IntentResult<Blob> {
    // EVM transaction building would require:
    // 1. Get nonce from RPC
    // 2. Build raw transaction
    // 3. Sign with tECDSA
    // 4. Return signed transaction

    #err(#InternalError("EVM transaction building not yet implemented"))
  };

  /// Broadcast EVM transaction
  public func broadcast(
    _config : Config,
    _signed_tx : Blob,
    _rpc_url : ?Text
  ) : async IntentResult<Text> {
    // Would use eth_sendRawTransaction
    #err(#InternalError("EVM transaction broadcast not yet implemented"))
  };
}
