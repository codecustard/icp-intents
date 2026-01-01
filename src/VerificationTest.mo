/// Verification test canister for real transaction testing
/// Deploy with: dfx deploy VerificationTest
/// Run with: dfx canister call VerificationTest runTests

import Hoosat "../src/icp-intents-lib/chains/Hoosat";
import EVM "../src/icp-intents-lib/chains/EVM";
import ChainTypes "../src/icp-intents-lib/chains/ChainTypes";
import Debug "mo:base/Debug";
import Blob "mo:base/Blob";
import Principal "mo:base/Principal";

persistent actor VerificationTest {
  // Hoosat transaction data (replace with your own)
  let HOOSAT_RPC = "https://api.network.hoosat.fi";
  let HOOSAT_TX_ID = "YOUR_HOOSAT_TX_ID_HERE";
  let HOOSAT_ADDRESS = "hoosat:YOUR_HOOSAT_ADDRESS_HERE";
  let HOOSAT_AMOUNT = 10000000000; // Amount in sompi

  // EVM transaction data (Sepolia testnet - replace with your own)
  let EVM_CHAIN_ID = 11155111;
  let EVM_TX_HASH = "0xYOUR_EVM_TX_HASH_HERE";
  let EVM_TO_ADDRESS = "0xYOUR_EVM_ADDRESS_HERE";
  let EVM_VALUE = 1000000000000000; // Amount in wei

  public func testHoosatVerification() : async Text {
    Debug.print("Testing Hoosat verification...");

    let config : Hoosat.Config = {
      rpc_url = HOOSAT_RPC;
      min_confirmations = 1;
      ecdsa_key_name = "test_key_1";
    };

    let request : ChainTypes.VerificationRequest = {
      chain = #Hoosat({
        network = "mainnet";
        rpc_url = HOOSAT_RPC;
        min_confirmations = 1;
      });
      proof = #UTXO({
        tx_id = HOOSAT_TX_ID;
        output_index = 0;
        amount = 0;
        script_pubkey = Blob.fromArray([]);
        address = "";
        confirmations = 0;
      });
      expected_address = HOOSAT_ADDRESS;
      expected_amount = HOOSAT_AMOUNT;
      custom_rpc_urls = null;
    };

    let result = await Hoosat.verify(config, request);

    switch (result) {
      case (#Success(data)) {
        let msg = "✓ Hoosat verified with " # debug_show(data.confirmations) # " confirmations";
        Debug.print(msg);
        return msg;
      };
      case (#Pending(data)) {
        let msg = "⚠ Hoosat pending: " # debug_show(data.current_confirmations) # "/" # debug_show(data.required_confirmations);
        Debug.print(msg);
        return msg;
      };
      case (#Failed(msg)) {
        Debug.print("✗ Hoosat failed: " # msg);
        return "✗ Failed: " # msg;
      };
    };
  };

  public func testEVMVerification(evmRpcCanister : Principal) : async Text {
    Debug.print("Testing EVM verification...");

    let config : EVM.Config = {
      evm_rpc_canister = evmRpcCanister;
      min_confirmations = 1;
      ecdsa_key_name = "test_key_1";
    };

    let request : ChainTypes.VerificationRequest = {
      chain = #EVM({
        chain_id = EVM_CHAIN_ID;
        name = "sepolia";
        network = "testnet";
        rpc_urls = null;
      });
      proof = #EVM({
        tx_hash = EVM_TX_HASH;
        block_number = 0;
        from_address = "";
        to_address = "";
        value = 0;
        confirmations = 0;
      });
      expected_address = EVM_TO_ADDRESS;
      expected_amount = EVM_VALUE;
      custom_rpc_urls = null;
    };

    let result = await EVM.verify(config, request);

    switch (result) {
      case (#Success(data)) {
        let msg = "✓ EVM verified with " # debug_show(data.confirmations) # " confirmations";
        Debug.print(msg);
        return msg;
      };
      case (#Pending(data)) {
        let msg = "⚠ EVM pending: " # debug_show(data.current_confirmations) # "/" # debug_show(data.required_confirmations);
        Debug.print(msg);
        return msg;
      };
      case (#Failed(msg)) {
        Debug.print("✗ EVM failed: " # msg);
        return "✗ Failed: " # msg;
      };
    };
  };

  public func runTests() : async Text {
    var results = "=== Verification Tests ===\n\n";

    // Test Hoosat
    let hoosatResult = await testHoosatVerification();
    results #= "Hoosat: " # hoosatResult # "\n";

    results #= "\nNote: Run testEVMVerification separately with EVM RPC canister principal\n";

    return results;
  };
};
