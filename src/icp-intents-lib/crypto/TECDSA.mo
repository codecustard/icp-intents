/// Threshold ECDSA operations for multi-chain support
///
/// Provides address generation and transaction signing for EVM, Bitcoin, and UTXO chains

import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Text "mo:base/Text";
import Error "mo:base/Error";
import Buffer "mo:base/Buffer";
import SHA3 "mo:sha3";
import Types "../core/Types";
import ChainTypes "../chains/ChainTypes";
import Cycles "../utils/Cycles";

module {
  type IntentResult<T> = Types.IntentResult<T>;
  type IntentError = Types.IntentError;
  type Chain = ChainTypes.Chain;
  type AddressContext = ChainTypes.AddressContext;

  /// ECDSA key configuration
  public type ECDSAConfig = {
    key_name : Text; // "test_key_1" or "key_1"
  };

  /// ECDSA signing request
  public type SignRequest = {
    message_hash : Blob;
    derivation_path : [Blob];
    key_name : Text;
  };

  /// ECDSA signing result
  public type SignResult = {
    signature : Blob;
    public_key : Blob;
  };

  // IC Management Canister Types
  type ECDSAPublicKeyRequest = {
    canister_id : ?Principal;
    derivation_path : [Blob];
    key_id : { curve : { #secp256k1 }; name : Text };
  };

  type ECDSAPublicKeyResponse = {
    public_key : Blob;
    chain_code : Blob;
  };

  type ECDSASignRequest = {
    message_hash : Blob;
    derivation_path : [Blob];
    key_id : { curve : { #secp256k1 }; name : Text };
  };

  type ECDSASignResponse = {
    signature : Blob;
  };

  type ManagementCanister = actor {
    ecdsa_public_key : (ECDSAPublicKeyRequest) -> async ECDSAPublicKeyResponse;
    sign_with_ecdsa : (ECDSASignRequest) -> async ECDSASignResponse;
  };

  func managementCanister() : ManagementCanister {
    actor ("aaaaa-aa")
  };

  /// Create derivation path from context
  public func createDerivationPath(context : AddressContext) : [Blob] {
    let intentBlob = natToBlob(context.intent_id);
    let userBlob = Principal.toBlob(context.user);
    [intentBlob, userBlob]
  };

  /// Get public key for derivation path
  public func getPublicKey(
    key_name : Text,
    derivation_path : [Blob]
  ) : async IntentResult<Blob> {
    // Check cycles
    if (not Cycles.hasSufficientCycles(Cycles.ECDSA_PUBKEY_COST)) {
      return #err(#InsufficientCycles);
    };

    try {
      let request : ECDSAPublicKeyRequest = {
        canister_id = null;
        derivation_path = derivation_path;
        key_id = {
          curve = #secp256k1;
          name = key_name;
        };
      };

      let response = await managementCanister().ecdsa_public_key(request);
      #ok(response.public_key)
    } catch (e) {
      #err(#ECDSAError("Failed to get public key: " # Error.message(e)))
    }
  };

  /// Generate address for any supported chain
  public func generateAddress(
    chain : Chain,
    context : AddressContext,
    key_name : Text
  ) : async IntentResult<Text> {
    let derivation_path = createDerivationPath(context);

    switch (await getPublicKey(key_name, derivation_path)) {
      case (#err(e)) { #err(e) };
      case (#ok(pubkey)) {
        let pubkey_bytes = Blob.toArray(pubkey);

        switch (chain) {
          case (#EVM(_)) {
            #ok(publicKeyToEthAddress(pubkey_bytes))
          };
          case (#Bitcoin(btc)) {
            publicKeyToBitcoinAddress(pubkey_bytes, btc.network)
          };
          case (#Hoosat(_)) {
            // Hoosat uses similar addressing to Bitcoin
            publicKeyToHoosatAddress(pubkey_bytes)
          };
          case (#Custom(_)) {
            #err(#InvalidChain("Custom chains must implement their own address generation"))
          };
        }
      };
    }
  };

  /// Sign message with tECDSA
  public func sign(request : SignRequest) : async IntentResult<Blob> {
    // Check cycles
    if (not Cycles.hasSufficientCycles(Cycles.ECDSA_SIGNING_COST)) {
      return #err(#InsufficientCycles);
    };

    try {
      let sign_request : ECDSASignRequest = {
        message_hash = request.message_hash;
        derivation_path = request.derivation_path;
        key_id = {
          curve = #secp256k1;
          name = request.key_name;
        };
      };

      let response = await managementCanister().sign_with_ecdsa(sign_request);
      #ok(response.signature)
    } catch (e) {
      #err(#SigningFailed("tECDSA signing failed: " # Error.message(e)))
    }
  };

  /// Convert ECDSA public key to Ethereum address
  /// Address = last 20 bytes of keccak256(uncompressed_pubkey)
  func publicKeyToEthAddress(pubkey : [Nat8]) : Text {
    // Remove 0x04 prefix if present (uncompressed key format)
    let key_without_prefix = if (pubkey.size() == 65 and pubkey[0] == 0x04) {
      Array.tabulate<Nat8>(64, func(i) { pubkey[i + 1] })
    } else {
      pubkey
    };

    // Compute Keccak256 hash
    let keccak = SHA3.Keccak(256);
    keccak.update(key_without_prefix);
    let hash = keccak.finalize();

    // Take last 20 bytes
    let address_bytes = Array.tabulate<Nat8>(20, func(i) { hash[i + 12] });

    // Convert to 0x... format
    "0x" # bytesToHex(address_bytes)
  };

  /// Convert public key to Bitcoin address (P2PKH format)
  func publicKeyToBitcoinAddress(_pubkey : [Nat8], _network : Text) : IntentResult<Text> {
    // This is a simplified version - production would use proper Bitcoin encoding
    // Including RIPEMD-160, Base58Check, etc.

    // For now, return a placeholder indicating Bitcoin support is partial
    #err(#InvalidChain("Bitcoin address generation requires full Base58Check implementation"))
  };

  /// Convert public key to Hoosat address
  func publicKeyToHoosatAddress(_pubkey : [Nat8]) : IntentResult<Text> {
    // Hoosat address format - similar to Bitcoin but with different prefix
    // This would need proper implementation based on Hoosat specs

    #err(#InvalidChain("Hoosat address generation requires Hoosat-specific encoding"))
  };

  /// Convert bytes to hex string
  func bytesToHex(bytes : [Nat8]) : Text {
    let hex_chars = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"];
    var result = "";
    for (byte in bytes.vals()) {
      let high = Nat8.toNat(byte / 16);
      let low = Nat8.toNat(byte % 16);
      result #= hex_chars[high] # hex_chars[low];
    };
    result
  };

  /// Convert Nat to Blob (for derivation paths)
  func natToBlob(n : Nat) : Blob {
    let bytes = natToBytes(n);
    let arr = Array.reverse(bytes);
    Blob.fromArray(arr)
  };

  /// Convert Nat to byte array (little-endian)
  func natToBytes(n : Nat) : [Nat8] {
    if (n == 0) return [0];

    var num = n;
    let buffer = Buffer.Buffer<Nat8>(8);
    while (num > 0) {
      let byte = Nat8.fromNat(num % 256);
      buffer.add(byte);
      num := num / 256;
    };
    Buffer.toArray(buffer)
  };

  /// Verify address ownership (for security checks)
  public func verifyAddressOwnership(
    chain : Chain,
    address : Text,
    context : AddressContext,
    key_name : Text
  ) : async Bool {
    switch (await generateAddress(chain, context, key_name)) {
      case (#ok(derived_address)) {
        Text.equal(address, derived_address)
      };
      case (#err(_)) { false };
    }
  };

  /// Get derivation path for debugging
  public func getDerivationPath(intent_id : Nat, user : Principal) : [Blob] {
    let intentBlob = natToBlob(intent_id);
    let userBlob = Principal.toBlob(user);
    [intentBlob, userBlob]
  };

  /// Parse DER signature to get r and s values (for Bitcoin/UTXO chains)
  public func parseDERSignature(der_sig : Blob) : ?{ r : Blob; s : Blob } {
    let bytes = Blob.toArray(der_sig);

    // DER format: 0x30 [total-length] 0x02 [r-length] [r] 0x02 [s-length] [s]
    if (bytes.size() < 8) return null;
    if (bytes[0] != 0x30) return null;
    if (bytes[2] != 0x02) return null;

    let r_len = Nat8.toNat(bytes[3]);
    if (bytes.size() < 4 + r_len + 2) return null;

    let r_start = 4;
    let r_end = r_start + r_len;
    let r = Blob.fromArray(Array.tabulate<Nat8>(r_len, func(i) { bytes[r_start + i] }));

    if (bytes[r_end] != 0x02) return null;
    let s_len = Nat8.toNat(bytes[r_end + 1]);
    if (bytes.size() < r_end + 2 + s_len) return null;

    let s_start = r_end + 2;
    let s = Blob.fromArray(Array.tabulate<Nat8>(s_len, func(i) { bytes[s_start + i] }));

    ?{ r = r; s = s }
  };

  /// Validate public key format
  public func isValidPublicKey(pubkey : Blob) : Bool {
    let bytes = Blob.toArray(pubkey);
    let size = bytes.size();

    // Uncompressed: 65 bytes starting with 0x04
    // Compressed: 33 bytes starting with 0x02 or 0x03
    if (size == 65) {
      bytes[0] == 0x04
    } else if (size == 33) {
      bytes[0] == 0x02 or bytes[0] == 0x03
    } else {
      false
    }
  };
}
