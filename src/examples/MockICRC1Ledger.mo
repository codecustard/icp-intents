/// Mock ICRC-1 Ledger for Local Testing
///
/// A simplified ICRC-1 token ledger for testing the intent system locally.
/// This mock ledger supports basic transfers and balance queries.
///
/// Features:
/// - Transfer tokens between accounts
/// - Query balances
/// - Mint tokens for testing (no restrictions)
///
/// Deploy with:
/// ```
/// dfx deploy MockICRC1Ledger
/// ```

import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Result "mo:base/Result";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";

import ICRC2 "mo:icrc2-types";

persistent actor MockICRC1Ledger {
  type Account = ICRC2.Account;
  type TransferArgs = ICRC2.TransferArgs;
  type TransferResult = ICRC2.TransferResult;

  // Simple balance tracking (Principal -> Nat)
  // In a real ledger, this would use Account (owner + subaccount)
  // Using transient because HashMap is not stable-compatible
  transient var balances = HashMap.HashMap<Principal, Nat>(100, Principal.equal, Principal.hash);
  transient var allowances = HashMap.HashMap<(Principal, Principal), Nat>(100,
    func(a: (Principal, Principal), b: (Principal, Principal)) : Bool {
      Principal.equal(a.0, b.0) and Principal.equal(a.1, b.1)
    },
    func(a: (Principal, Principal)) : Nat32 {
      Principal.hash(a.0) ^ Principal.hash(a.1)
    }
  );
  var nextBlockIndex : Nat = 0;

  // Token metadata
  let tokenName = "Test Token";
  let tokenSymbol = "TST";
  let decimals : Nat8 = 8;
  let fee : Nat = 10_000; // 0.0001 tokens

  /// Transfer tokens from caller to recipient
  public shared(msg) func icrc1_transfer(args: TransferArgs) : async TransferResult {
    let sender = msg.caller;
    let recipient = args.to.owner;

    Debug.print("Transfer: " # Principal.toText(sender) # " -> " # Principal.toText(recipient) # " amount: " # Nat.toText(args.amount));

    // Get sender balance
    let senderBalance = switch (balances.get(sender)) {
      case null { 0 };
      case (?balance) { balance };
    };

    // Check sufficient balance (amount + fee)
    let totalRequired = args.amount + fee;
    if (senderBalance < totalRequired) {
      return #Err(#InsufficientFunds { balance = senderBalance });
    };

    // Deduct from sender (amount + fee)
    balances.put(sender, senderBalance - totalRequired);

    // Add to recipient
    let recipientBalance = switch (balances.get(recipient)) {
      case null { 0 };
      case (?balance) { balance };
    };
    balances.put(recipient, recipientBalance + args.amount);

    // Fee is burned (not added to anyone)
    Debug.print("Transfer succeeded. Block: " # Nat.toText(nextBlockIndex));

    let blockIndex = nextBlockIndex;
    nextBlockIndex += 1;

    #Ok(blockIndex)
  };

  /// Get balance for an account
  public query func icrc1_balance_of(account: Account) : async Nat {
    switch (balances.get(account.owner)) {
      case null { 0 };
      case (?balance) { balance };
    }
  };

  /// Mint tokens for testing (no restrictions - for testing only!)
  public func mint(to: Principal, amount: Nat) : async Nat {
    Debug.print("Minting " # Nat.toText(amount) # " tokens to " # Principal.toText(to));

    let currentBalance = switch (balances.get(to)) {
      case null { 0 };
      case (?balance) { balance };
    };

    let newBalance = currentBalance + amount;
    balances.put(to, newBalance);

    Debug.print("New balance: " # Nat.toText(newBalance));
    newBalance
  };

  /// Burn tokens for testing
  public shared(msg) func burn(amount: Nat) : async Result.Result<(), Text> {
    let sender = msg.caller;

    let senderBalance = switch (balances.get(sender)) {
      case null { 0 };
      case (?balance) { balance };
    };

    if (senderBalance < amount) {
      return #err("Insufficient balance");
    };

    balances.put(sender, senderBalance - amount);
    Debug.print("Burned " # Nat.toText(amount) # " tokens from " # Principal.toText(sender));
    #ok(())
  };

  /// Get all balances (for testing/debugging)
  public query func getAllBalances() : async [(Principal, Nat)] {
    Iter.toArray(balances.entries())
  };

  // ICRC-1 Metadata queries

  public query func icrc1_name() : async Text {
    tokenName
  };

  public query func icrc1_symbol() : async Text {
    tokenSymbol
  };

  public query func icrc1_decimals() : async Nat8 {
    decimals
  };

  public query func icrc1_fee() : async Nat {
    fee
  };

  public query func icrc1_metadata() : async ICRC2.Metadata {
    [
      ("icrc1:name", #Text(tokenName)),
      ("icrc1:symbol", #Text(tokenSymbol)),
      ("icrc1:decimals", #Nat(Nat8.toNat(decimals))),
      ("icrc1:fee", #Nat(fee)),
    ]
  };

  public query func icrc1_total_supply() : async Nat {
    var total = 0;
    for ((_, balance) in balances.entries()) {
      total += balance;
    };
    total
  };

  public query func icrc1_minting_account() : async ?Account {
    null // No specific minting account in this mock
  };

  public query func icrc1_supported_standards() : async ICRC2.SupportedStandards {
    [
      { name = "ICRC-1"; url = "https://github.com/dfinity/ICRC-1" },
      { name = "ICRC-2"; url = "https://github.com/dfinity/ICRC-1/tree/main/standards/ICRC-2" }
    ]
  };

  // ICRC-2 Functions

  /// Approve a spender to transfer tokens on behalf of the caller
  public shared(msg) func icrc2_approve(args: ICRC2.ApproveArgs) : async ICRC2.ApproveResult {
    let owner = msg.caller;
    let spender = args.spender.owner;

    Debug.print("Approve: " # Principal.toText(owner) # " -> " # Principal.toText(spender) # " amount: " # Nat.toText(args.amount));

    // Set allowance
    allowances.put((owner, spender), args.amount);

    let blockIndex = nextBlockIndex;
    nextBlockIndex += 1;

    #Ok(blockIndex)
  };

  /// Query allowance
  public query func icrc2_allowance(args: ICRC2.AllowanceArgs) : async ICRC2.Allowance {
    let owner = args.account.owner;
    let spender = args.spender.owner;

    let allowance = switch (allowances.get((owner, spender))) {
      case null { 0 };
      case (?amount) { amount };
    };

    {
      allowance = allowance;
      expires_at = null;
    }
  };

  /// Transfer tokens from one account to another (requires approval)
  public shared(msg) func icrc2_transfer_from(args: ICRC2.TransferFromArgs) : async ICRC2.TransferFromResult {
    let spender = msg.caller;
    let from = args.from.owner;
    let to = args.to.owner;

    Debug.print("TransferFrom: " # Principal.toText(from) # " -> " # Principal.toText(to) # " via " # Principal.toText(spender) # " amount: " # Nat.toText(args.amount));

    // Check allowance
    let allowance = switch (allowances.get((from, spender))) {
      case null { 0 };
      case (?amount) { amount };
    };

    if (allowance < args.amount) {
      return #Err(#InsufficientAllowance { allowance = allowance });
    };

    // Check from balance
    let fromBalance = switch (balances.get(from)) {
      case null { 0 };
      case (?balance) { balance };
    };

    let totalRequired = args.amount + fee;
    if (fromBalance < totalRequired) {
      return #Err(#InsufficientFunds { balance = fromBalance });
    };

    // Deduct from sender (amount + fee)
    balances.put(from, fromBalance - totalRequired);

    // Add to recipient
    let toBalance = switch (balances.get(to)) {
      case null { 0 };
      case (?balance) { balance };
    };
    balances.put(to, toBalance + args.amount);

    // Reduce allowance
    allowances.put((from, spender), allowance - args.amount);

    Debug.print("TransferFrom succeeded. Block: " # Nat.toText(nextBlockIndex));

    let blockIndex = nextBlockIndex;
    nextBlockIndex += 1;

    #Ok(blockIndex)
  };
}
