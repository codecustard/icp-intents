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
import Constants "../utils/Constants";

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

  /// JSON field type for extraction
  type JsonFieldType = {
    #String;
    #Number;
    #ArrayFirst;
  };

  /// Unified JSON field extractor
  /// Extracts a field value from JSON text based on field type
  func extractJsonValue(json : Text, field : Text, fieldType : JsonFieldType) : ?Text {
    // Build pattern based on field type
    let pattern = switch (fieldType) {
      case (#String) { "\"" # field # "\":\"" };
      case (#Number) { "\"" # field # "\":" };
      case (#ArrayFirst) { "\"" # field # "\":[\"" };
    };

    let parts = Text.split(json, #text pattern);
    let iter = parts;
    ignore iter.next();

    switch (iter.next()) {
      case null { null };
      case (?afterField) {
        switch (fieldType) {
          case (#String or #ArrayFirst) {
            // Extract value until closing quote
            let valueParts = Text.split(afterField, #text "\"");
            valueParts.next()
          };
          case (#Number) {
            // Extract number until delimiter
            var numStr = "";
            for (c in afterField.chars()) {
              if (c == ',' or c == '}' or c == ' ' or c == '\n' or c == '\r') {
                if (numStr.size() > 0) {
                  return ?numStr;
                };
              };
              numStr #= Text.fromChar(c);
            };
            if (numStr.size() > 0) { ?numStr } else { null }
          };
        }
      };
    }
  };

  /// Extract JSON string field
  func extractJsonField(json : Text, field : Text) : ?Text {
    extractJsonValue(json, field, #String)
  };

  /// Extract first element from JSON array field
  func extractJsonArrayFirst(json : Text, field : Text) : ?Text {
    extractJsonValue(json, field, #ArrayFirst)
  };

  /// Extract numeric field from JSON and parse as Nat
  func extractNumericField(json : Text, field : Text) : ?Nat {
    switch (extractJsonValue(json, field, #Number)) {
      case null { null };
      case (?numText) { parseNatSafe(numText, Constants.MAX_BLOCK_HEIGHT) };
    }
  };

  /// Extract daaScore from JSON (convenience wrapper)
  func extractDaaScore(json : Text) : ?Nat {
    extractNumericField(json, "daaScore")
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

  /// Validate field length against maximum
  func validateFieldLength(fieldName : Text, value : Text, maxLength : Nat) : Bool {
    let len = Text.size(value);
    if (len > maxLength) {
      Debug.print("Security: " # fieldName # " exceeds max length " # Nat.toText(maxLength) # " (got " # Nat.toText(len) # ")");
      return false;
    };
    true
  };

  /// Validate numeric value against maximum bound
  func validateNumericBounds(fieldName : Text, value : Nat, maxValue : Nat) : Bool {
    if (value > maxValue) {
      Debug.print("Security: " # fieldName # " exceeds max value " # Nat.toText(maxValue) # " (got " # Nat.toText(value) # ")");
      return false;
    };
    true
  };

  /// Safe Nat parsing with overflow protection
  func parseNatSafe(text : Text, maxValue : Nat) : ?Nat {
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
      // Check for overflow before multiplication
      if (num > maxValue / 10) {
        Debug.print("Security: parseNatSafe detected overflow");
        return null;
      };
      num := num * 10 + digit;
      // Check bounds after addition
      if (num > maxValue) {
        Debug.print("Security: parseNatSafe value exceeds max " # Nat.toText(maxValue));
        return null;
      };
    };
    ?num
  };

  /// Check if text contains substring
  func textContains(haystack : Text, needle : Text) : Bool {
    let parts = Iter.toArray(Text.split(haystack, #text needle));
    parts.size() > 1
  };

  /// Calculate confirmations from block heights (public for testing)
  public func calculateConfirmations(currentHeight : Nat, txHeight : Nat) : Nat {
    if (currentHeight >= txHeight) {
      (currentHeight - txHeight) + 1
    } else {
      0
    }
  };

  /// Verify Hoosat UTXO deposit
  ///
  /// Verifies a Hoosat UTXO transaction using HTTP outcalls to Hoosat RPC.
  ///
  /// **Error Handling**: Implements graceful degradation for transient errors.
  /// Returns #Pending instead of #Failed when data is temporarily unavailable,
  /// allowing the caller to retry later.
  ///
  /// Transient errors handled:
  /// 1. HTTP 5xx errors (server errors) - return Pending
  /// 2. HTTP 429 (rate limit) - return Pending
  /// 3. Timeout exceptions - return Pending
  /// 4. Missing data in valid responses - return Pending
  ///
  /// Parameters:
  /// - `config`: Hoosat verification configuration with RPC URL
  /// - `request`: Verification request with proof and expected values
  ///
  /// Returns:
  /// - `#Success` if UTXO is verified with enough confirmations
  /// - `#Pending` if transaction exists but lacks confirmations or data unavailable
  /// - `#Failed` if transaction validation fails or unrecoverable errors occur
  public func verify(config : Config, request : VerificationRequest) : async VerificationResult {
    // Note: Cycles are provided with each HTTP outcall using 'with cycles = X'

    let proof = switch (request.proof) {
      case (#UTXO(utxo_proof)) { utxo_proof };
      case _ {
        return #Failed("Invalid proof type for Hoosat verification");
      };
    };

    // Validate proof.tx_id length
    if (not validateFieldLength("tx_id", proof.tx_id, Constants.MAX_TX_HASH_LENGTH)) {
      return #Failed("Transaction ID exceeds maximum length");
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

      // Check for transient HTTP errors that should return Pending
      if (httpResponse.status == 429) {
        Debug.print("Hoosat: Rate limited (429) - returning Pending");
        return #Pending({
          current_confirmations = 0;
          required_confirmations = config.min_confirmations;
        });
      };

      if (httpResponse.status >= 500 and httpResponse.status < 600) {
        Debug.print("Hoosat: Server error " # Nat.toText(httpResponse.status) # " - returning Pending");
        return #Pending({
          current_confirmations = 0;
          required_confirmations = config.min_confirmations;
        });
      };

      if (httpResponse.status != 200) {
        // Non-transient client error (4xx except 429)
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
          switch (parseNatSafe(amountStr, Constants.MAX_AMOUNT_VALUE)) {
            case null { return #Failed("Invalid or out-of-bounds amount") };
            case (?amt) { amt };
          }
        };
      };

      // Verify amount
      if (amount < request.expected_amount) {
        return #Failed("Insufficient amount: " # Nat.toText(amount) # " < " # Nat.toText(request.expected_amount));
      };

      // Get transaction details to check confirmations
      let txUrl = config.rpc_url # "/transactions/" # proof.tx_id;
      Debug.print("Hoosat: Fetching transaction details from " # txUrl);

      let txResponse = await (with cycles = Cycles.HTTP_OUTCALL_COST) management.http_request({
        url = txUrl;
        max_response_bytes = ?65536; // 64KB for large transactions
        method = #get;
        headers = [{
          name = "Accept";
          value = "application/json";
        }];
        body = null;
        transform = null;
        is_replicated = ?false;
      });

      // Handle transient errors for transaction details request
      if (txResponse.status == 429 or (txResponse.status >= 500 and txResponse.status < 600)) {
        Debug.print("Hoosat: Transient error fetching tx details (" # Nat.toText(txResponse.status) # ") - returning Pending");
        return #Pending({
          current_confirmations = 0;
          required_confirmations = config.min_confirmations;
        });
      };

      if (txResponse.status != 200) {
        return #Failed("Failed to fetch transaction details: " # Nat.toText(txResponse.status));
      };

      let txResponseText = switch (Text.decodeUtf8(txResponse.body)) {
        case null { return #Failed("Invalid UTF-8 in transaction response") };
        case (?text) { text };
      };

      // Debug: show first 500 chars of response
      let preview = if (txResponseText.size() > 500) {
        let chars = txResponseText.chars();
        var result = "";
        var count = 0;
        label l for (c in chars) {
          if (count >= 500) break l;
          result #= Text.fromChar(c);
          count += 1;
        };
        result # "..."
      } else {
        txResponseText
      };
      Debug.print("Hoosat: TX response: " # preview);

      // Extract block hash from transaction (Hoosat returns array of hashes due to DAG structure)
      let blockHash = switch (extractJsonArrayFirst(txResponseText, "block_hash")) {
        case null {
          Debug.print("Hoosat: No block_hash found in transaction response");
          // Transaction exists but not yet in a block
          return #Pending({
            current_confirmations = 0;
            required_confirmations = config.min_confirmations;
          });
        };
        case (?hash) {
          Debug.print("Hoosat: Found block_hash: " # hash);
          hash
        };
      };

      // Validate block_hash length
      if (not validateFieldLength("block_hash", blockHash, Constants.MAX_BLOCK_HASH_LENGTH)) {
        return #Failed("Block hash exceeds maximum length");
      };

      // Get block details to find block height
      let blockUrl = config.rpc_url # "/blocks/" # blockHash;
      Debug.print("Hoosat: Fetching block details from " # blockUrl);

      let blockResponse = await (with cycles = Cycles.HTTP_OUTCALL_COST) management.http_request({
        url = blockUrl;
        max_response_bytes = ?65536; // 64KB for large blocks
        method = #get;
        headers = [{
          name = "Accept";
          value = "application/json";
        }];
        body = null;
        transform = null;
        is_replicated = ?false;
      });

      // Handle transient errors for block details request
      if (blockResponse.status == 429 or (blockResponse.status >= 500 and blockResponse.status < 600)) {
        Debug.print("Hoosat: Transient error fetching block details (" # Nat.toText(blockResponse.status) # ") - returning Pending");
        return #Pending({
          current_confirmations = 0;
          required_confirmations = config.min_confirmations;
        });
      };

      if (blockResponse.status != 200) {
        return #Failed("Failed to fetch block details: " # Nat.toText(blockResponse.status));
      };

      let blockResponseText = switch (Text.decodeUtf8(blockResponse.body)) {
        case null { return #Failed("Invalid UTF-8 in block response") };
        case (?text) { text };
      };

      // Debug: show first 500 chars of block response
      let blockPreview = if (blockResponseText.size() > 500) {
        let chars = blockResponseText.chars();
        var result = "";
        var count = 0;
        label l2 for (c in chars) {
          if (count >= 500) break l2;
          result #= Text.fromChar(c);
          count += 1;
        };
        result # "..."
      } else {
        blockResponseText
      };
      Debug.print("Hoosat: Block response: " # blockPreview);

      // Extract block height (daaScore in Hoosat - it's a number not a string in JSON)
      // Try to parse it from the response directly
      let txBlockHeight = switch (extractDaaScore(blockResponseText)) {
        case null {
          Debug.print("Hoosat: Could not find 'daaScore' field");
          return #Failed("Could not extract block height");
        };
        case (?height) {
          Debug.print("Hoosat: Found daaScore: " # Nat.toText(height));
          height
        };
      };

      // Get current chain tip
      let infoUrl = config.rpc_url # "/info/network";
      Debug.print("Hoosat: Fetching chain info from " # infoUrl);

      let infoResponse = await (with cycles = Cycles.HTTP_OUTCALL_COST) management.http_request({
        url = infoUrl;
        max_response_bytes = ?4096;
        method = #get;
        headers = [{
          name = "Accept";
          value = "application/json";
        }];
        body = null;
        transform = null;
        is_replicated = ?false;
      });

      // Handle transient errors for chain info request
      if (infoResponse.status == 429 or (infoResponse.status >= 500 and infoResponse.status < 600)) {
        Debug.print("Hoosat: Transient error fetching chain info (" # Nat.toText(infoResponse.status) # ") - returning Pending");
        return #Pending({
          current_confirmations = 0;
          required_confirmations = config.min_confirmations;
        });
      };

      if (infoResponse.status != 200) {
        return #Failed("Failed to fetch chain info: " # Nat.toText(infoResponse.status));
      };

      let infoResponseText = switch (Text.decodeUtf8(infoResponse.body)) {
        case null { return #Failed("Invalid UTF-8 in info response") };
        case (?text) { text };
      };

      // Debug: show first 500 chars of info response
      let infoPreview = if (infoResponseText.size() > 500) {
        let chars = infoResponseText.chars();
        var result = "";
        var count = 0;
        label l3 for (c in chars) {
          if (count >= 500) break l3;
          result #= Text.fromChar(c);
          count += 1;
        };
        result # "..."
      } else {
        infoResponseText
      };
      Debug.print("Hoosat: Info response: " # infoPreview);

      // Extract current block height (virtualDaaScore is a string field in the response)
      let currentHeight = switch (extractJsonField(infoResponseText, "virtualDaaScore")) {
        case (?heightStr) {
          switch (parseNatSafe(heightStr, Constants.MAX_BLOCK_HEIGHT)) {
            case null { return #Failed("Invalid or out-of-bounds virtualDaaScore") };
            case (?height) {
              Debug.print("Hoosat: Current virtualDaaScore: " # Nat.toText(height));
              height
            };
          }
        };
        case null { return #Failed("Could not extract virtualDaaScore") };
      };

      // Calculate confirmations (blocks since tx was mined + 1)
      let confirmations = calculateConfirmations(currentHeight, txBlockHeight);

      Debug.print("Hoosat: Confirmations: " # Nat.toText(confirmations) # " / " # Nat.toText(config.min_confirmations));

      // Check if we have enough confirmations
      if (confirmations < config.min_confirmations) {
        return #Pending({
          current_confirmations = confirmations;
          required_confirmations = config.min_confirmations;
        });
      };

      // Success with actual confirmations!
      #Success({
        verified_amount = amount;
        tx_hash = proof.tx_id;
        confirmations = confirmations;
        timestamp = 0; // Should be set by caller
      })
    } catch (e) {
      // Catch block for catastrophic failures (canister unreachable, etc.)
      // Log detailed error and determine if it's transient
      let errorMsg = Error.message(e);
      Debug.print("Hoosat: HTTP request exception: " # errorMsg);

      // Check if this is a transient error that should return Pending
      if (Text.contains(errorMsg, #text "timeout") or
          Text.contains(errorMsg, #text "unavailable") or
          Text.contains(errorMsg, #text "overloaded") or
          Text.contains(errorMsg, #text "rejected") or
          Text.contains(errorMsg, #text "temporary")) {
        Debug.print("Hoosat: Transient error detected - returning Pending");
        return #Pending({
          current_confirmations = 0;
          required_confirmations = config.min_confirmations;
        });
      };

      // For other errors, fail with detailed message
      #Failed("HTTP request failed: " # errorMsg)
    }
  };

  /// Generate Hoosat deposit address
  public func generateAddress(
    config : Config,
    context : AddressContext
  ) : async IntentResult<Text> {
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
    _config : Config,
    utxo : UTXO,
    recipient : Text,
    amount : Nat,
    intent_id : Nat,
    user : Principal,
    key_name : Text
  ) : async IntentResult<Blob> {
    try {
      // Derive key path
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

      // Build transaction
      let fee : Nat64 = Constants.HOOSAT_DEFAULT_FEE;
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

      // Validate tx_id length
      if (not validateFieldLength("tx_id", tx_id, Constants.MAX_TX_HASH_LENGTH)) {
        return #err(#InternalError("Transaction ID exceeds maximum length"));
      };

      Debug.print("Hoosat: Broadcast successful, tx_id: " # tx_id);
      #ok(tx_id)
    } catch (e) {
      #err(#NetworkError("Broadcast failed: " # Error.message(e)))
    }
  };
}
