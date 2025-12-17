/// Cross-chain verification module for EVM chains.
/// Uses the official EVM RPC canister for multi-provider consensus.
///
/// Supports:
/// - Native ETH verification (eth_getBalance)
/// - ERC20 token verification (eth_getLogs for Transfer events)
/// - Extensible to custom chains via user-provided RPC URLs
///
/// Example usage:
/// ```motoko
/// import Verification "mo:icp-intents/Verification";
///
/// let result = await Verification.verifyDeposit(
///   config,
///   address,
///   expectedAmount,
///   tokenAddress,
///   chainId
/// );
/// ```

import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Error "mo:base/Error";
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

  /// EVM RPC canister interface (simplified)
  /// In production, use the official EVM RPC Candid interface
  type EVMRPCCanister = actor {
    eth_getBalance: (GetBalanceRequest) -> async GetBalanceResult;
    eth_getLogs: (GetLogsRequest) -> async GetLogsResult;
  };

  /// RPC request types (simplified - extend as needed)
  type GetBalanceRequest = {
    address: Text;
    block: Text;  // "latest", "earliest", or hex block number
    chainId: Nat64;
  };

  type GetBalanceResult = {
    #Ok: { balance: Text };  // Hex string
    #Err: Text;
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
    address: Text;
    topics: [Text];
    data: Text;
    blockNumber: Text;
    transactionHash: Text;
  };

  /// Get EVM RPC canister actor
  func getEVMRPC(canisterId: Principal) : EVMRPCCanister {
    actor(Principal.toText(canisterId))
  };

  /// Verify native ETH deposit to an address
  /// Returns the verified balance and whether it meets the expected amount
  public func verifyNativeDeposit(
    config: Config,
    address: Text,
    expectedAmount: Nat,
    chainId: Nat
  ) : async VerificationResult {
    if (not Utils.isValidEthAddress(address)) {
      return #Failed("Invalid Ethereum address");
    };

    try {
      let rpc = getEVMRPC(config.evm_rpc_canister_id);

      let request : GetBalanceRequest = {
        address = address;
        block = "latest";  // Could use "finalized" for more safety
        chainId = Nat64.fromNat(chainId);
      };

      let response = await rpc.eth_getBalance(request);

      switch (response) {
        case (#Ok(result)) {
          // Parse hex balance
          let balanceOpt = Utils.hexToNat(result.balance);
          switch (balanceOpt) {
            case (?balance) {
              if (balance >= expectedAmount) {
                #Success({
                  amount = balance;
                  tx_hash = "balance_check";  // Balance checks don't have tx hash
                })
              } else {
                #Pending  // Not enough deposited yet
              }
            };
            case null {
              #Failed("Failed to parse balance")
            };
          }
        };
        case (#Err(err)) {
          #Failed("RPC error: " # err)
        };
      }
    } catch (e) {
      #Failed("Verification failed: " # Error.message(e))
    }
  };

  /// Verify ERC20 token deposit via Transfer event logs
  /// Checks for Transfer(from, to, amount) event to the target address
  public func verifyERC20Deposit(
    config: Config,
    tokenAddress: Text,
    recipientAddress: Text,
    expectedAmount: Nat,
    chainId: Nat,
    fromBlock: ?Nat
  ) : async VerificationResult {
    if (not Utils.isValidEthAddress(tokenAddress)) {
      return #Failed("Invalid token address");
    };

    if (not Utils.isValidEthAddress(recipientAddress)) {
      return #Failed("Invalid recipient address");
    };

    try {
      let rpc = getEVMRPC(config.evm_rpc_canister_id);

      // ERC20 Transfer event signature
      // keccak256("Transfer(address,address,uint256)")
      let transferTopic = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef";

      // Filter for transfers TO the recipient address
      // Topic[2] = recipient (indexed parameter)
      let recipientTopic = addressToTopic(recipientAddress);

      let request : GetLogsRequest = {
        addresses = [tokenAddress];
        fromBlock = switch (fromBlock) {
          case (?block) natToHex(block);
          case null "earliest";
        };
        toBlock = "latest";
        topics = [
          [transferTopic],  // Transfer event
          [],               // Any sender
          [recipientTopic], // Specific recipient
        ];
        chainId = Nat64.fromNat(chainId);
      };

      let response = await rpc.eth_getLogs(request);

      switch (response) {
        case (#Ok(result)) {
          // Check if any transfer meets the expected amount
          var totalDeposited : Nat = 0;
          var latestTxHash : Text = "";

          for (log in result.logs.vals()) {
            // Parse amount from data field (uint256 = 32 bytes)
            let amountOpt = Utils.hexToNat(log.data);
            switch (amountOpt) {
              case (?amount) {
                totalDeposited += amount;
                latestTxHash := log.transactionHash;
              };
              case null {};
            };
          };

          if (totalDeposited >= expectedAmount) {
            #Success({
              amount = totalDeposited;
              tx_hash = latestTxHash;
            })
          } else {
            #Pending
          }
        };
        case (#Err(err)) {
          #Failed("RPC error: " # err)
        };
      }
    } catch (e) {
      #Failed("Verification failed: " # Error.message(e))
    }
  };

  /// Verify deposit (routes to native or ERC20 based on token address)
  public func verifyDeposit(
    config: Config,
    address: Text,
    expectedAmount: Nat,
    tokenAddress: Text,
    chainId: Nat,
    fromBlock: ?Nat
  ) : async VerificationResult {
    if (tokenAddress == "native") {
      await verifyNativeDeposit(config, address, expectedAmount, chainId)
    } else {
      await verifyERC20Deposit(
        config,
        tokenAddress,
        address,
        expectedAmount,
        chainId,
        fromBlock
      )
    }
  };

  /// Helper: Convert Ethereum address to EVM topic (padded to 32 bytes)
  func addressToTopic(address: Text) : Text {
    let cleanAddress = Text.trimStart(address, #text "0x");
    // Pad address (20 bytes = 40 hex chars) to 32 bytes (64 hex chars)
    let padding = "000000000000000000000000";  // 24 zeros
    "0x" # padding # cleanAddress
  };

  /// Helper: Convert Nat to hex string
  func natToHex(n: Nat) : Text {
    if (n == 0) return "0x0";

    var num = n;
    var hex = "";
    let hexChars = ["0", "1", "2", "3", "4", "5", "6", "7",
                    "8", "9", "a", "b", "c", "d", "e", "f"];

    while (num > 0) {
      hex := hexChars[num % 16] # hex;
      num := num / 16;
    };

    "0x" # hex
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
