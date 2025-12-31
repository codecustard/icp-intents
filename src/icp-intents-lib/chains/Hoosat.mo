/// Hoosat blockchain verification and transaction building
///
/// Handles UTXO-based verification and tECDSA-powered transaction creation for Hoosat

import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";
import Error "mo:base/Error";
import HoosatAddress "mo:hoosat-mo/address";
import HoosatSighash "mo:hoosat-mo/sighash";
import HoosatTransaction "mo:hoosat-mo/transaction";
import HoosatTypes "mo:hoosat-mo/types";
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
  type HoosatChain = ChainTypes.HoosatChain;
  type UTXOProof = ChainTypes.UTXOProof;
  type UTXO = Types.UTXO;

  /// Hoosat verification configuration
  public type Config = {
    rpc_url : Text;
    min_confirmations : Nat;
    ecdsa_key_name : Text;
  };

  /// HTTP types for IC outcalls
  type HttpHeader = {
    name : Text;
    value : Text;
  };

  type HttpResponse = {
    status : Nat;
    headers : [HttpHeader];
    body : Blob;
  };

  type ManagementCanister = actor {
    http_request : ({
      url : Text;
      max_response_bytes : ?Nat64;
      method : { #get; #head; #post };
      headers : [HttpHeader];
      body : ?Blob;
      transform : ?{
        function : shared query { response : HttpResponse; context : Blob } -> async HttpResponse;
        context : Blob;
      };
      is_replicated : ?Bool;
    }) -> async HttpResponse;
  };

  func managementCanister() : ManagementCanister {
    actor ("aaaaa-aa")
  };

  /// Extract JSON field value
  func extractJsonField(json : Text, field : Text) : ?Text {
    let pattern = "\"" # field # "\":\"";
    let parts = Text.split(json, #text pattern);
    let iter = parts;
    ignore iter.next();

    switch (iter.next()) {
      case null { null };
      case (?afterField) {
        let valueParts = Text.split(afterField, #text "\"");
        valueParts.next()
      };
    }
  };

  /// Parse Nat from text
  func parseNat(text : Text) : ?Nat {
    var num : Nat = 0;
    for (c in text.chars()) {
      let digit = switch (c) {
        case '0' { 0 };
        case '1' { 1 };
        case '2' { 2 };
        case '3' { 3 };
        case '4' { 4 };
        case '5' { 5 };
        case '6' { 6 };
        case '7' { 7 };
        case '8' { 8 };
        case '9' { 9 };
        case _ { return null };
      };
      num := num * 10 + digit;
    };
    ?num
  };

  /// Check if text contains substring
  func textContains(haystack : Text, needle : Text) : Bool {
    let parts = Iter.toArray(Text.split(haystack, #text needle));
    parts.size() > 1
  };

  /// Verify Hoosat UTXO deposit
  public func verify(config : Config, request : VerificationRequest) : async VerificationResult {
    // Check cycles
    if (not Cycles.hasSufficientCycles(Cycles.HTTP_OUTCALL_COST)) {
      return #Failed("Insufficient cycles for HTTP outcall");
    };

    let proof = switch (request.proof) {
      case (#UTXO(utxo_proof)) { utxo_proof };
      case _ {
        return #Failed("Invalid proof type for Hoosat verification");
      };
    };

    try {
      let management = managementCanister();

      // Normalize address
      let normalizedAddress = if (Text.startsWith(request.expected_address, #text "Hoosat:")) {
        "hoosat:" # Text.trimStart(request.expected_address, #text "Hoosat:")
      } else {
        request.expected_address
      };

      let url = config.rpc_url # "/addresses/" # normalizedAddress # "/utxos";

      Debug.print("Hoosat: Verifying UTXO at " # url);

      let httpResponse = await (with cycles = Cycles.HTTP_OUTCALL_COST) management.http_request({
        url = url;
        max_response_bytes = ?16384;
        method = #get;
        headers = [{
          name = "Accept";
          value = "application/json";
        }];
        body = null;
        transform = null;
        is_replicated = ?false;
      });

      if (httpResponse.status != 200) {
        return #Failed("Hoosat API error: " # Nat.toText(httpResponse.status));
      };

      let responseText = switch (Text.decodeUtf8(httpResponse.body)) {
        case null { return #Failed("Invalid UTF-8 response") };
        case (?text) { text };
      };

      // Check if transaction exists
      if (not textContains(responseText, proof.tx_id)) {
        return #Pending({
          current_confirmations = 0;
          required_confirmations = config.min_confirmations;
        });
      };

      // Extract transaction data
      let txIdPattern = "\"transactionId\":\"" # proof.tx_id # "\"";
      let parts = Text.split(responseText, #text txIdPattern);
      let iter = parts;
      ignore iter.next();

      let afterTxId = switch (iter.next()) {
        case null { return #Failed("Transaction not found in expected format") };
        case (?text) { text };
      };

      // Extract amount
      let amount = switch (extractJsonField(afterTxId, "amount")) {
        case null { return #Failed("Could not extract amount") };
        case (?amountStr) {
          switch (parseNat(amountStr)) {
            case null { return #Failed("Invalid amount format") };
            case (?amt) { amt };
          }
        };
      };

      // Verify amount
      if (amount < request.expected_amount) {
        return #Failed("Insufficient amount: " # Nat.toText(amount) # " < " # Nat.toText(request.expected_amount));
      };

      // Success!
      #Success({
        verified_amount = amount;
        tx_hash = proof.tx_id;
        confirmations = 10; // Default confirmations for Hoosat
        timestamp = 0; // Should be set by caller
      })
    } catch (e) {
      #Failed("HTTP request failed: " # Error.message(e))
    }
  };

  /// Generate Hoosat deposit address
  public func generateAddress(
    config : Config,
    context : AddressContext
  ) : async IntentResult<Text> {
    // Check cycles
    if (not Cycles.hasSufficientCycles(Cycles.ECDSA_PUBKEY_COST)) {
      return #err(#InsufficientCycles);
    };

    try {
      let derivation_path = TECDSA.createDerivationPath(context);

      switch (await TECDSA.getPublicKey(config.ecdsa_key_name, derivation_path)) {
        case (#err(e)) { #err(e) };
        case (#ok(public_key)) {
          // Convert to Hoosat address (ECDSA type)
          let address = HoosatAddress.address_from_pubkey(public_key, HoosatAddress.ECDSA);
          #ok(address)
        };
      }
    } catch (e) {
      #err(#ECDSAError("Failed to generate Hoosat address: " # Error.message(e)))
    }
  };

  /// Build and sign Hoosat transaction
  public func buildTransaction(
    config : Config,
    utxo : UTXO,
    recipient : Text,
    amount : Nat,
    intent_id : Nat,
    key_name : Text
  ) : async IntentResult<Blob> {
    // Check cycles for pubkey + signing
    let required_cycles = Cycles.ECDSA_PUBKEY_COST + Cycles.ECDSA_SIGNING_COST;
    if (not Cycles.hasSufficientCycles(required_cycles)) {
      return #err(#InsufficientCycles);
    };

    try {
      // Derive key path
      // Note: We need the user principal, but UTXO type doesn't store it
      // This would need to be passed separately or retrieved from intent
      let user = Principal.fromText("aaaaa-aa"); // Placeholder - should be from context
      let derivation_path = TECDSA.getDerivationPath(intent_id, user);

      // Get public key
      let public_key = switch (await TECDSA.getPublicKey(key_name, derivation_path)) {
        case (#err(e)) { return #err(e) };
        case (#ok(pk)) { pk };
      };

      // Convert to Hoosat UTXO format
      let utxoScriptHex = Blob.toArray(utxo.script_pubkey) |> HoosatAddress.hex_from_array(_);
      let hoosatUtxo : HoosatTypes.UTXO = {
        transactionId = utxo.tx_id;
        index = Nat32.fromNat(utxo.output_index);
        amount = Nat64.fromNat(utxo.amount);
        scriptPublicKey = utxoScriptHex;
        scriptVersion = 0;
        address = utxo.address;
      };

      // Normalize recipient address
      let normalizedAddress = Text.replace(recipient, #text "hoosat:", "Hoosat:");

      // Decode recipient address
      let recipientScript = switch (HoosatAddress.decode_address(normalizedAddress)) {
        case (?(addrType, payload)) {
          HoosatAddress.pubkey_to_script(payload, addrType)
        };
        case null {
          return #err(#InvalidAddress("Invalid Hoosat address"));
        };
      };

      // Generate change script
      let ourScript = HoosatAddress.pubkey_to_script(
        Blob.toArray(public_key),
        HoosatAddress.ECDSA
      );

      // Build transaction (2000 hootas fee)
      let fee : Nat64 = 2000;
      let tx = HoosatTransaction.build_transaction(
        hoosatUtxo,
        recipientScript,
        Nat64.fromNat(amount),
        fee,
        ourScript
      );

      // Calculate sighash
      let reusedValues : HoosatSighash.SighashReusedValues = {
        var previousOutputsHash = null;
        var sequencesHash = null;
        var sigOpCountsHash = null;
        var outputsHash = null;
        var payloadHash = null;
      };

      let sighash = switch (
        HoosatSighash.calculate_sighash_ecdsa(
          tx,
          0,
          hoosatUtxo,
          HoosatSighash.SigHashAll,
          reusedValues
        )
      ) {
        case (?hash) { Blob.fromArray(hash) };
        case null {
          return #err(#InternalError("Failed to compute sighash"));
        };
      };

      // Sign with tECDSA
      let sign_request : TECDSA.SignRequest = {
        message_hash = sighash;
        derivation_path = derivation_path;
        key_name = key_name;
      };

      let signature = switch (await TECDSA.sign(sign_request)) {
        case (#err(e)) { return #err(e) };
        case (#ok(sig)) { sig };
      };

      // Format signature script
      let signature_bytes = Blob.toArray(signature);
      let sighash_type : Nat8 = 0x01;

      let script_bytes = Array.flatten<Nat8>([
        [Nat8.fromNat(signature_bytes.size() + 1)],
        signature_bytes,
        [sighash_type]
      ]);
      let signatureScript = HoosatAddress.hex_from_array(script_bytes);

      // Update transaction with signature
      let signedTx : HoosatTypes.HoosatTransaction = {
        version = tx.version;
        inputs = Array.map<HoosatTypes.TransactionInput, HoosatTypes.TransactionInput>(
          tx.inputs,
          func(input) {
            {
              previousOutpoint = input.previousOutpoint;
              signatureScript = signatureScript;
              sequence = input.sequence;
              sigOpCount = input.sigOpCount;
            }
          }
        );
        outputs = tx.outputs;
        lockTime = tx.lockTime;
        subnetworkId = tx.subnetworkId;
        gas = tx.gas;
        payload = tx.payload;
      };

      // Serialize transaction
      let serializedTx = HoosatTransaction.serialize_transaction(signedTx);
      #ok(Text.encodeUtf8(serializedTx))
    } catch (e) {
      #err(#SigningFailed("Transaction building failed: " # Error.message(e)))
    }
  };

  /// Broadcast Hoosat transaction
  public func broadcast(
    config : Config,
    signed_tx : Blob,
    _rpc_url : ?Text
  ) : async IntentResult<Text> {
    // Check cycles
    if (not Cycles.hasSufficientCycles(Cycles.HTTP_OUTCALL_COST)) {
      return #err(#InsufficientCycles);
    };

    try {
      let management = managementCanister();
      let url = config.rpc_url # "/transactions";

      Debug.print("Hoosat: Broadcasting to " # url);

      let requestBody = switch (Text.decodeUtf8(signed_tx)) {
        case null {
          return #err(#InternalError("Invalid transaction encoding"));
        };
        case (?body) { body };
      };

      let httpResponse = await (with cycles = Cycles.HTTP_OUTCALL_COST) management.http_request({
        url = url;
        max_response_bytes = ?1024;
        method = #post;
        headers = [{
          name = "Content-Type";
          value = "application/json";
        }];
        body = ?Text.encodeUtf8(requestBody);
        transform = null;
        is_replicated = ?false;
      });

      if (httpResponse.status != 200) {
        let errorBody = switch (Text.decodeUtf8(httpResponse.body)) {
          case (?text) { text };
          case null { "Unknown error" };
        };
        return #err(#NetworkError("Broadcast failed: " # errorBody));
      };

      let responseText = switch (Text.decodeUtf8(httpResponse.body)) {
        case null {
          return #err(#InternalError("Invalid response encoding"));
        };
        case (?text) { text };
      };

      // Extract transaction ID from response
      let tx_id = switch (extractJsonField(responseText, "transactionId")) {
        case (?id) { id };
        case null {
          return #err(#InternalError("Could not extract transaction ID"));
        };
      };

      Debug.print("Hoosat: Broadcast successful, tx_id: " # tx_id);
      #ok(tx_id)
    } catch (e) {
      #err(#NetworkError("Broadcast failed: " # Error.message(e)))
    }
  };
}
