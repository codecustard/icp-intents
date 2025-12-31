/// Hoosat blockchain verification and transaction building module.
/// Handles UTXO-based verification and tECDSA-powered transaction creation.
///
/// Key features:
/// - Generate Hoosat deposit addresses using tECDSA
/// - Verify UTXO deposits via Hoosat RPC
/// - Build and sign transactions to release funds to solvers
/// - Support for both Schnorr and ECDSA signatures

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
import Types "../icp-intents-lib/Types";

module {
  type UTXO = Types.UTXO;
  type IntentResult<T> = Types.IntentResult<T>;
  type IntentError = Types.IntentError;

  /// Configuration for Hoosat network
  public type HoosatConfig = {
    rpc_url: Text;           /// Hoosat RPC endpoint
    network: Text;           /// "mainnet" or "testnet"
    confirmations: Nat;      /// Required confirmations (typically 10+)
    ecdsa_key_name: Text;    /// tECDSA key name
  };

  /// Verification request for a Hoosat deposit
  public type HoosatVerificationRequest = {
    tx_id: Text;             /// Transaction hash to verify
    expected_address: Text;  /// Expected deposit address
    expected_amount: Nat;    /// Expected amount in hootas (smallest unit)
    output_index: Nat;       /// Which output to check (typically 0 or 1)
  };

  /// Result of UTXO verification
  public type VerificationResult = {
    #Success: UTXO;
    #Failed: Text;
  };

  /// HTTP header for IC HTTP outcalls
  public type HttpHeader = {
    name : Text;
    value : Text;
  };

  /// HTTP transform function for IC HTTP outcalls
  public type TransformContext = {
    function : shared query TransformArgs -> async HttpResponse;
    context : Blob;
  };

  /// Transform arguments
  public type TransformArgs = {
    response : HttpResponse;
    context : Blob;
  };

  /// HTTP response from IC outcall
  public type HttpResponse = {
    status : Nat;
    headers : [HttpHeader];
    body : Blob;
  };

  /// IC Management canister interface for tECDSA and HTTP outcalls
  public type ManagementCanister = actor {
    ecdsa_public_key : ({
      canister_id : ?Principal;
      derivation_path : [Blob];
      key_id : { curve : { #secp256k1 }; name : Text };
    }) -> async ({ public_key : Blob; chain_code : Blob });

    sign_with_ecdsa : ({
      message_hash : Blob;
      derivation_path : [Blob];
      key_id : { curve : { #secp256k1 }; name : Text };
    }) -> async ({ signature : Blob });

    http_request : ({
      url : Text;
      max_response_bytes : ?Nat64;
      method : { #get; #head; #post };
      headers : [HttpHeader];
      body : ?Blob;
      transform : ?TransformContext;
      is_replicated : ?Bool;
    }) -> async HttpResponse;
  };

  /// Get management canister actor
  public func getManagementCanister() : ManagementCanister {
    actor("aaaaa-aa")
  };

  /// Extract a field value from JSON text (simple parser for specific fields)
  /// Returns the string value between quotes after the field name
  func extractJsonField(json: Text, field: Text) : ?Text {
    let pattern = "\"" # field # "\":\"";
    let parts = Text.split(json, #text pattern);
    let iter = parts;
    ignore iter.next(); // Skip first part before field

    switch (iter.next()) {
      case null { null };
      case (?afterField) {
        // Find the closing quote
        let valueParts = Text.split(afterField, #text "\"");
        valueParts.next()
      };
    }
  };

  /// Parse Nat from Text (handles string numbers from JSON)
  func parseNat(text: Text) : ?Nat {
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

  /// Check if text contains substring (needed because Text.contains requires literal patterns)
  func textContains(haystack: Text, needle: Text) : Bool {
    let parts = Iter.toArray(Text.split(haystack, #text needle));
    parts.size() > 1
  };

  /// Generate a Hoosat deposit address for an intent using tECDSA
  /// Uses ECDSA signature type (33-byte compressed public key)
  public func generateDepositAddress(
    intentId: Nat,
    config: HoosatConfig
  ) : async IntentResult<Text> {
    try {
      let management = getManagementCanister();

      // Derive unique key for this intent
      let derivation_path = [
        Blob.fromArray([0, 0, 0, 0]), // Intent namespace
        Text.encodeUtf8(Nat.toText(intentId))
      ];

      // Get public key from tECDSA
      let { public_key } = await management.ecdsa_public_key({
        canister_id = null;
        derivation_path = derivation_path;
        key_id = {
          curve = #secp256k1;
          name = config.ecdsa_key_name;
        };
      });

      // Convert to Hoosat address (ECDSA type, 33 bytes compressed)
      let address = HoosatAddress.address_from_pubkey(public_key, HoosatAddress.ECDSA);

      #ok(address)
    } catch (_) {
      #err(#InternalError("Failed to generate Hoosat address"))
    }
  };

  /// Verify that a UTXO exists and matches expected criteria
  /// Calls Hoosat REST API to verify the deposit
  public func verifyUTXO(
    request: HoosatVerificationRequest,
    config: HoosatConfig
  ) : async VerificationResult {
    try {
      let management = getManagementCanister();

      // Use provided RPC URL or default to mainnet
      let baseUrl = if (Text.size(config.rpc_url) > 0) {
        config.rpc_url
      } else {
        "https://api.network.hoosat.fi"
      };

      // Call GET /addresses/{address}/utxos
      // Normalize address to lowercase (API requires lowercase "hoosat:" prefix)
      let normalizedAddress = if (Text.startsWith(request.expected_address, #text "Hoosat:")) {
        "hoosat:" # Text.trimStart(request.expected_address, #text "Hoosat:")
      } else {
        request.expected_address
      };

      let url = baseUrl # "/addresses/" # normalizedAddress # "/utxos";

      Debug.print("HoosatVerification: Calling " # url);

      let httpResponse = try {
        await (with cycles = 230_000_000_000) management.http_request({
          url = url;
          max_response_bytes = ?16384; // 16KB for UTXO list
          method = #get;
          headers = [{
            name = "Accept";
            value = "application/json";
          }];
          body = null;
          transform = null;
          is_replicated = ?false;
        })
      } catch (err) {
        let errorMsg = Error.message(err);
        Debug.print("HoosatVerification: HTTP request error: " # errorMsg);
        return #Failed("HTTP request error: " # errorMsg);
      };

      Debug.print("HoosatVerification: HTTP response status: " # Nat.toText(httpResponse.status));

      if (httpResponse.status != 200) {
        return #Failed("Hoosat API returned status " # Nat.toText(httpResponse.status));
      };

      // Parse response body
      let responseText = switch (Text.decodeUtf8(httpResponse.body)) {
        case null { return #Failed("Invalid UTF-8 in response") };
        case (?text) { text };
      };

      Debug.print("HoosatVerification: Response: " # responseText);

      // Parse JSON array to find matching UTXO
      // Response format: [{"outpoint": {"transactionId": "...", "index": 0}, "utxoEntry": {"amount": "...", ...}}]

      // Simple approach: search for the transaction ID in the response
      if (not textContains(responseText, request.tx_id)) {
        return #Failed("Transaction " # request.tx_id # " not found in UTXOs for address");
      };

      // Extract the UTXO data by finding the matching transaction
      // Look for the pattern: "transactionId":"<tx_id>"
      let txIdPattern = "\"transactionId\":\"" # request.tx_id # "\"";

      // Find the substring starting from our transaction
      let parts = Text.split(responseText, #text txIdPattern);
      let iter = parts;
      ignore iter.next(); // Skip before match

      let afterTxId = switch (iter.next()) {
        case null { return #Failed("Transaction ID not found in expected format") };
        case (?text) { text };
      };

      // Now extract amount from the portion AFTER our transaction ID
      let amountOpt = extractJsonField(afterTxId, "amount");
      let amount = switch (amountOpt) {
        case null { return #Failed("Could not extract amount from response for transaction " # request.tx_id) };
        case (?amountStr) {
          switch (parseNat(amountStr)) {
            case null { return #Failed("Invalid amount format: " # amountStr) };
            case (?amt) { amt };
          }
        };
      };

      // Verify amount matches expected
      if (amount < request.expected_amount) {
        return #Failed("Amount mismatch: expected " # Nat.toText(request.expected_amount) # " but got " # Nat.toText(amount));
      };

      // Extract scriptPublicKey from the same transaction (it's a hex string in JSON)
      let scriptPubKey = switch (extractJsonField(afterTxId, "scriptPublicKey")) {
        case null { Blob.fromArray([]) };
        case (?spk) { Blob.fromArray(HoosatAddress.array_from_hex(spk)) };
      };

      // Success - construct UTXO
      let utxo : UTXO = {
        tx_id = request.tx_id;
        output_index = request.output_index;
        amount = amount;
        script_pubkey = scriptPubKey;
        address = request.expected_address;
      };

      #Success(utxo)
    } catch (_) {
      #Failed("HTTP request failed or response parsing error")
    }
  };

  /// Build and sign a Hoosat transaction to release funds to solver
  /// This spends the deposited UTXO and sends it to the solver's address
  public func buildAndSignTransaction(
    utxo: UTXO,
    recipientAddress: Text,
    amount: Nat,
    intentId: Nat,
    config: HoosatConfig
  ) : async IntentResult<Blob> {
    try {
      let management = getManagementCanister();

      // Derive the same key used for deposit address
      let derivation_path = [
        Blob.fromArray([0, 0, 0, 0]),
        Text.encodeUtf8(Nat.toText(intentId))
      ];

      // Get public key
      let { public_key } = await (with cycles = 10_000_000_000) management.ecdsa_public_key({
        canister_id = null;
        derivation_path = derivation_path;
        key_id = {
          curve = #secp256k1;
          name = config.ecdsa_key_name;
        };
      });

      Debug.print("HoosatVerification: Signing public key: " # HoosatAddress.hex_from_array(Blob.toArray(public_key)));

      // Convert Types.UTXO to HoosatTypes.UTXO
      let utxoScriptHex = Blob.toArray(utxo.script_pubkey) |> HoosatAddress.hex_from_array(_);
      Debug.print("HoosatVerification: UTXO scriptPublicKey: " # utxoScriptHex);

      let hoosatUtxo : HoosatTypes.UTXO = {
        transactionId = utxo.tx_id;
        index = Nat32.fromNat(utxo.output_index);
        amount = Nat64.fromNat(utxo.amount);
        scriptPublicKey = utxoScriptHex;
        scriptVersion = 0;
        address = utxo.address;
      };

      // Normalize address: ensure it starts with capital "Hoosat:"
      let normalizedAddress = Text.replace(recipientAddress, #text "hoosat:", "Hoosat:");

      // Decode recipient address to get script
      Debug.print("HoosatVerification: Attempting to decode address: " # normalizedAddress);
      let recipientDecoded = switch (HoosatAddress.decode_address(normalizedAddress)) {
        case (?(addrType, payload)) {
          Debug.print("HoosatVerification: Successfully decoded address, type: " # debug_show(addrType));
          HoosatAddress.pubkey_to_script(payload, addrType)
        };
        case null {
          Debug.print("HoosatVerification: FAILED to decode recipient address: " # normalizedAddress);
          Debug.print("HoosatVerification: This may be due to invalid checksum, unsupported address type, or malformed address");
          return #err(#InternalError("Invalid Hoosat address - address decode failed. Please verify the address is correct and try again."));
        };
      };

      // Generate our change script from our public key
      let ourScript = HoosatAddress.pubkey_to_script(
        Blob.toArray(public_key),
        HoosatAddress.ECDSA
      );

      // Calculate fee (network minimum: 1635 hootas, use 2000 to be safe)
      let fee : Nat64 = 2000;

      // Build transaction
      let tx = HoosatTransaction.build_transaction(
        hoosatUtxo,
        recipientDecoded,
        Nat64.fromNat(amount),
        fee,
        ourScript
      );

      // Compute sighash for ECDSA
      // Need reused values for sighash calculation
      let reusedValues : HoosatSighash.SighashReusedValues = {
        var previousOutputsHash = null;
        var sequencesHash = null;
        var sigOpCountsHash = null;
        var outputsHash = null;
        var payloadHash = null;
      };

      let sighashOpt = HoosatSighash.calculate_sighash_ecdsa(
        tx,
        0, // input index
        hoosatUtxo,
        HoosatSighash.SigHashAll,
        reusedValues
      );

      let sighash = switch (sighashOpt) {
        case (?hash) { Blob.fromArray(hash) };
        case null { return #err(#InternalError("Failed to compute sighash")) };
      };

      // Sign with tECDSA (needs ~26B cycles)
      let { signature } = await (with cycles = 30_000_000_000) management.sign_with_ecdsa({
        message_hash = sighash;
        derivation_path = derivation_path;
        key_id = {
          curve = #secp256k1;
          name = config.ecdsa_key_name;
        };
      });

      // Format signature script with proper push format for Hoosat
      // Format: [length][signature][sighash_type]
      let signature_bytes = Blob.toArray(signature);
      let sighash_type: Nat8 = 0x01; // SigHashAll

      let script_bytes = Array.flatten<Nat8>([
        [Nat8.fromNat(signature_bytes.size() + 1)], // Length prefix (signature + sighash type)
        signature_bytes,                             // Raw signature (64 bytes)
        [sighash_type]                              // Sighash type
      ]);
      let signatureScript = HoosatAddress.hex_from_array(script_bytes);

      Debug.print("HoosatVerification: Signature script length: " # Nat.toText(script_bytes.size()));

      // Update transaction with signature in signatureScript
      let signedTx : HoosatTypes.HoosatTransaction = {
        version = tx.version;
        inputs = Array.map<HoosatTypes.TransactionInput, HoosatTypes.TransactionInput>(
          tx.inputs,
          func (input) {
            {
              previousOutpoint = input.previousOutpoint;
              signatureScript = signatureScript; // Add formatted signature script
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
      let errorMsg = Error.message(e);
      Debug.print("HoosatVerification: Build/sign failed: " # errorMsg);
      #err(#InternalError("Failed to build/sign transaction: " # errorMsg))
    }
  };

  /// Broadcast a signed transaction to the Hoosat network
  /// Returns the transaction hash
  public func broadcastTransaction(
    signedTx: Blob,
    config: HoosatConfig
  ) : async IntentResult<Text> {
    try {
      let management = getManagementCanister();

      // Use provided RPC URL or default to mainnet
      let baseUrl = if (Text.size(config.rpc_url) > 0) {
        config.rpc_url
      } else {
        "https://api.network.hoosat.fi"
      };

      let url = baseUrl # "/transactions";

      Debug.print("HoosatVerification: Broadcasting transaction to " # url);

      // Decode the signed transaction blob to text (already in JSON format)
      let requestBody = switch (Text.decodeUtf8(signedTx)) {
        case null { return #err(#InternalError("Invalid transaction encoding")) };
        case (?text) { text };
      };

      Debug.print("HoosatVerification: Request body length: " # Nat.toText(Text.size(requestBody)));

      let httpResponse = try {
        await (with cycles = 230_000_000_000) management.http_request({
          url = url;
          max_response_bytes = ?4096; // Enough for response with tx hash
          method = #post;
          headers = [
            {
              name = "Content-Type";
              value = "application/json";
            },
            {
              name = "Accept";
              value = "application/json";
            }
          ];
          body = ?Text.encodeUtf8(requestBody);
          transform = null;
          is_replicated = ?false;
        })
      } catch (err) {
        let errorMsg = Error.message(err);
        Debug.print("HoosatVerification: HTTP request error: " # errorMsg);
        return #err(#InternalError("HTTP request error: " # errorMsg));
      };

      Debug.print("HoosatVerification: HTTP response status: " # Nat.toText(httpResponse.status));

      if (httpResponse.status != 200) {
        let responseText = switch (Text.decodeUtf8(httpResponse.body)) {
          case null { "Invalid UTF-8 in error response" };
          case (?text) { text };
        };
        Debug.print("HoosatVerification: Error response: " # responseText);
        return #err(#InternalError("Hoosat API returned status " # Nat.toText(httpResponse.status) # ": " # responseText));
      };

      // Parse response to extract transaction ID
      let responseText = switch (Text.decodeUtf8(httpResponse.body)) {
        case null { return #err(#InternalError("Invalid UTF-8 in response")) };
        case (?text) { text };
      };

      Debug.print("HoosatVerification: Broadcast response: " # responseText);

      // Extract transaction ID from response
      // Response format: {"transactionId": "..."}
      let txId = switch (extractJsonField(responseText, "transactionId")) {
        case null { return #err(#InternalError("Could not extract transaction ID from response: " # responseText)) };
        case (?id) { id };
      };

      Debug.print("HoosatVerification: Transaction broadcast successful: " # txId);

      #ok(txId)
    } catch (e) {
      let errorMsg = Error.message(e);
      Debug.print("HoosatVerification: Broadcast failed: " # errorMsg);
      #err(#InternalError("Failed to broadcast transaction: " # errorMsg))
    }
  };
}
