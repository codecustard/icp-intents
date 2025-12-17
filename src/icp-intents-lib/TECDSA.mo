/// Threshold ECDSA utilities for generating EVM deposit addresses.
/// Uses ICP's Chain Fusion tECDSA to create unique addresses per intent.
/// Uses production Keccak256 implementation for Ethereum address generation.
///
/// Example usage:
/// ```motoko
/// import TECDSA "mo:icp-intents/TECDSA";
///
/// let config : TECDSA.Config = {
///   key_name = "test_key_1";  // or "key_1" for mainnet
/// };
///
/// let address = await TECDSA.deriveAddress(config, intentId, userPrincipal);
/// ```

import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Text "mo:base/Text";
import Error "mo:base/Error";
import SHA3 "mo:sha3";
import Types "../icp-intents-lib/Types";
import Utils "../icp-intents-lib/Utils";

module {
  type IntentResult<T> = Types.IntentResult<T>;
  type IntentError = Types.IntentError;

  /// TECDSA configuration
  public type Config = {
    key_name: Text;  // "test_key_1" or "key_1"
  };

  /// ECDSA public key response (from IC management canister)
  type ECDSAPublicKeyResponse = {
    public_key: Blob;
    chain_code: Blob;
  };

  /// ECDSA public key request
  type ECDSAPublicKeyRequest = {
    canister_id: ?Principal;
    derivation_path: [Blob];
    key_id: { curve: { #secp256k1 }; name: Text };
  };

  /// IC Management canister interface (partial)
  type ManagementCanister = actor {
    ecdsa_public_key: (ECDSAPublicKeyRequest) -> async ECDSAPublicKeyResponse;
  };

  /// Get the management canister actor
  func managementCanister() : ManagementCanister {
    actor("aaaaa-aa")
  };

  /// Derive an Ethereum address for a specific intent
  /// Uses intentId + user principal to create a unique derivation path
  /// Returns the address in 0x... format
  public func deriveAddress(
    config: Config,
    intentId: Nat,
    user: Principal
  ) : async IntentResult<Text> {
    try {
      let derivationPath = Utils.createDerivationPath(intentId, user);

      let request : ECDSAPublicKeyRequest = {
        canister_id = null;  // Use current canister
        derivation_path = derivationPath;
        key_id = {
          curve = #secp256k1;
          name = config.key_name;
        };
      };

      let response = await managementCanister().ecdsa_public_key(request);
      let publicKey = Blob.toArray(response.public_key);

      // Convert public key to Ethereum address
      let address = publicKeyToAddress(publicKey);
      #ok(address)
    } catch (e) {
      #err(#ECDSAError("Failed to derive address: " # Error.message(e)))
    }
  };

  /// Convert an ECDSA public key to an Ethereum address
  /// Ethereum address = last 20 bytes of keccak256(public_key)
  /// Uses the production SHA3/Keccak256 implementation
  func publicKeyToAddress(publicKey: [Nat8]) : Text {
    // The public key from secp256k1 is 65 bytes (uncompressed):
    // [0x04, x (32 bytes), y (32 bytes)]

    // Remove the 0x04 prefix if present
    let keyWithoutPrefix = if (publicKey.size() == 65 and publicKey[0] == 0x04) {
      Array.tabulate<Nat8>(64, func(i) { publicKey[i + 1] })
    } else {
      publicKey
    };

    // Compute keccak256 hash using production implementation
    // Ethereum uses Keccak256 (not SHA3-256)
    let keccak = SHA3.Keccak(256);
    keccak.update(keyWithoutPrefix);
    let hash = keccak.finalize();

    // Take last 20 bytes of hash for Ethereum address
    let addressBytes = Array.tabulate<Nat8>(
      20,
      func(i) { hash[i + 12] }
    );

    // Convert to hex string with 0x prefix
    "0x" # bytesToHex(addressBytes)
  };

  /// Convert bytes to hex string
  func bytesToHex(bytes: [Nat8]) : Text {
    let hexChars = ["0", "1", "2", "3", "4", "5", "6", "7",
                    "8", "9", "a", "b", "c", "d", "e", "f"];
    var result = "";
    for (byte in bytes.vals()) {
      let high = Nat8.toNat(byte / 16);
      let low = Nat8.toNat(byte % 16);
      result #= hexChars[high] # hexChars[low];
    };
    result
  };

  /// Verify that an address was derived from this canister
  /// Useful for security checks
  public func verifyAddressOwnership(
    config: Config,
    address: Text,
    intentId: Nat,
    user: Principal
  ) : async Bool {
    switch (await deriveAddress(config, intentId, user)) {
      case (#ok(derivedAddress)) {
        Text.equal(address, derivedAddress)
      };
      case (#err(_)) false;
    }
  };

  /// Get the derivation path for debugging
  public func getDerivationPath(intentId: Nat, user: Principal) : [Blob] {
    Utils.createDerivationPath(intentId, user)
  };
}
