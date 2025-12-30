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
import Nat16 "mo:base/Nat16";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";

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

  /// IC Management canister interface for tECDSA
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
  };

  /// Get management canister actor
  public func getManagementCanister() : ManagementCanister {
    actor("aaaaa-aa")
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
  /// This is a placeholder - needs actual RPC integration
  public func verifyUTXO(
    request: HoosatVerificationRequest,
    _config: HoosatConfig
  ) : async VerificationResult {
    // TODO: Implement actual Hoosat RPC calls
    // For now, return a placeholder

    Debug.print("HoosatVerification: Verifying UTXO");
    Debug.print("  TX ID: " # request.tx_id);
    Debug.print("  Expected address: " # request.expected_address);
    Debug.print("  Expected amount: " # Nat.toText(request.expected_amount));

    // Placeholder UTXO (would come from RPC)
    let utxo : UTXO = {
      tx_id = request.tx_id;
      output_index = request.output_index;
      amount = request.expected_amount;
      script_pubkey = Blob.fromArray([]);
      address = request.expected_address;
    };

    #Success(utxo)
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
      let { public_key } = await management.ecdsa_public_key({
        canister_id = null;
        derivation_path = derivation_path;
        key_id = {
          curve = #secp256k1;
          name = config.ecdsa_key_name;
        };
      });

      // Convert Types.UTXO to HoosatTypes.UTXO
      let hoosatUtxo : HoosatTypes.UTXO = {
        transactionId = utxo.tx_id;
        index = Nat32.fromNat(utxo.output_index);
        amount = Nat64.fromNat(utxo.amount);
        scriptPublicKey = Blob.toArray(utxo.script_pubkey) |> HoosatAddress.hex_from_array(_);
        scriptVersion = 0;
        address = utxo.address;
      };

      // Decode recipient address to get script
      let recipientDecoded = switch (HoosatAddress.decode_address(recipientAddress)) {
        case (?(addrType, payload)) {
          HoosatAddress.pubkey_to_script(payload, addrType)
        };
        case null {
          return #err(#InvalidAddress);
        };
      };

      // Generate our change script from our public key
      let ourScript = HoosatAddress.pubkey_to_script(
        Blob.toArray(public_key),
        HoosatAddress.ECDSA
      );

      // Calculate fee (simple: 1000 hootas)
      let fee : Nat64 = 1000;

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

      // Sign with tECDSA
      let { signature } = await management.sign_with_ecdsa({
        message_hash = sighash;
        derivation_path = derivation_path;
        key_id = {
          curve = #secp256k1;
          name = config.ecdsa_key_name;
        };
      });

      // Encode signature to hex
      let sigHex = HoosatAddress.hex_from_array(Blob.toArray(signature));

      // Update transaction with signature in signatureScript
      let signedTx : HoosatTypes.HoosatTransaction = {
        version = tx.version;
        inputs = Array.map<HoosatTypes.TransactionInput, HoosatTypes.TransactionInput>(
          tx.inputs,
          func (input) {
            {
              previousOutpoint = input.previousOutpoint;
              signatureScript = sigHex; // Add signature here
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
    } catch (_) {
      #err(#InternalError("Failed to build/sign transaction"))
    }
  };

  /// Broadcast a signed transaction to the Hoosat network
  /// Returns the transaction hash
  public func broadcastTransaction(
    _signedTx: Blob,
    _config: HoosatConfig
  ) : async IntentResult<Text> {
    // TODO: Implement actual RPC broadcast
    Debug.print("HoosatVerification: Broadcasting transaction");

    // Placeholder transaction hash
    #ok("0x" # "placeholder_hoosat_txhash")
  };
}
