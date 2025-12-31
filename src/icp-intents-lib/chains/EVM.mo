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
import Cycles "../utils/Cycles";

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

  // EVM RPC types (simplified)
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
  type EthSepoliaService = { #Alchemy; #BlockPi; #PublicNode; #Ankr };
  type EthMainnetService = { #Alchemy; #BlockPi; #Cloudflare; #PublicNode; #Ankr };
  type L2MainnetService = { #Alchemy; #BlockPi; #PublicNode; #Ankr };

  type GetTransactionReceiptResult = {
    #Ok : ?TransactionReceipt;
    #Err : Text;
  };

  type MultiGetTransactionReceiptResult = {
    #Consistent : GetTransactionReceiptResult;
    #Inconsistent : [(RpcService, GetTransactionReceiptResult)];
  };

  type RpcService = {
    #EthSepolia : EthSepoliaService;
    #EthMainnet : EthMainnetService;
    #Chain : Nat64;
    #Provider : Nat64;
  };

  type MultiJsonRequestResult = {
    #Consistent : JsonRequestResult;
    #Inconsistent : [(RpcService, JsonRequestResult)];
  };

  type JsonRequestResult = {
    #Ok : Text;
    #Err : Text;
  };

  /// EVM RPC canister interface (simplified)
  type EVMRPCCanister = actor {
    eth_getTransactionReceipt : (RpcServices, ?RpcConfig, Text) -> async MultiGetTransactionReceiptResult;
    multi_request : (RpcServices, ?RpcConfig, Text) -> async MultiJsonRequestResult;
  };

  type RpcConfig = {
    responseSizeEstimate : ?Nat64;
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
          case (11155111) { #EthSepolia(null) };
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
      case (#Consistent(#Ok(receipt))) { receipt };
      case (#Consistent(#Err(_))) { null };
      case (#Inconsistent(results)) {
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
      case (#Consistent(#Ok(json))) { ?json };
      case (#Inconsistent(results)) {
        for ((_, result) in results.vals()) {
          switch (result) {
            case (#Ok(json)) { return ?json };
            case _ {};
          };
        };
        null
      };
      case _ { null };
    }
  };

  /// Parse transaction value from JSON response
  func parseTransactionValue(json : Text) : ?Nat {
    // Parse "value":"0x..." from JSON
    var parts = Iter.toArray(Text.split(json, #text "\"value\":\""));
    if (parts.size() < 2) {
      parts := Iter.toArray(Text.split(json, #text "\"value\": \""));
    };

    if (parts.size() < 2) {
      return null;
    };

    let afterValue = parts[1];
    let valueParts = Iter.toArray(Text.split(afterValue, #text "\""));
    if (valueParts.size() < 1) {
      return null;
    };

    let hexValue = valueParts[0];
    hexToNat(hexValue)
  };

  /// Convert hex string to Nat
  func hexToNat(hex : Text) : ?Nat {
    let cleanHex = Text.trimStart(hex, #text "0x");
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

  /// Verify EVM deposit transaction
  public func verify(config : Config, request : VerificationRequest) : async VerificationResult {
    // Check cycles
    if (not Cycles.hasSufficientCycles(Cycles.HTTP_OUTCALL_COST * 2)) {
      return #Failed("Insufficient cycles for RPC calls");
    };

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
      // Get transaction receipt
      let receipt_response = await rpc.eth_getTransactionReceipt(
        rpc_services,
        ?{ responseSizeEstimate = ?1000 },
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
      let tx_response = await rpc.multi_request(
        rpc_services,
        ?{ responseSizeEstimate = ?1000 },
        tx_request
      );

      let tx_value = switch (extractJsonString(tx_response)) {
        case (?json) {
          parseTransactionValue(json)
        };
        case null { null };
      };

      // Validate the transaction
      return validateTransaction(receipt, tx_value, request.expected_address, request.expected_amount, proof.tx_hash)
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
    tx_hash : Text
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

    // Success!
    #Success({
      verified_amount = actual_value;
      tx_hash = tx_hash;
      confirmations = receipt.blockNumber; // Using block number as proxy
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
