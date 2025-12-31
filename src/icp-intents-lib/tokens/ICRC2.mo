/// ICRC-2 Token Transfer Integration
///
/// Handles token transfers for the intent system using ICRC-1 and ICRC-2 standards

import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import ICRC2Types "mo:icrc2-types";
import Types "../core/Types";
import Cycles "../utils/Cycles";

module {
  type IntentResult<T> = Types.IntentResult<T>;
  type IntentError = Types.IntentError;
  type Account = ICRC2Types.Account;

  /// ICRC-1 Ledger actor interface
  public type ICRC1Ledger = actor {
    icrc1_transfer : (ICRC2Types.TransferArgs) -> async ICRC2Types.TransferResult;
    icrc1_balance_of : (Account) -> async Nat;
    icrc1_fee : () -> async Nat;
  };

  /// ICRC-2 Ledger actor interface (extends ICRC-1)
  public type ICRC2Ledger = actor {
    icrc1_transfer : (ICRC2Types.TransferArgs) -> async ICRC2Types.TransferResult;
    icrc1_balance_of : (Account) -> async Nat;
    icrc1_fee : () -> async Nat;
    icrc2_transfer_from : (ICRC2Types.TransferFromArgs) -> async ICRC2Types.TransferFromResult;
    icrc2_allowance : (ICRC2Types.AllowanceArgs) -> async ICRC2Types.Allowance;
  };

  /// Transfer tokens from user to canister (deposit)
  /// Assumes user has already called approve() on the ledger
  public func depositFrom(
    ledger_principal : Principal,
    from : Principal,
    to : Principal,
    amount : Nat,
    memo : ?Blob
  ) : async IntentResult<Nat> {
    // Check cycles for inter-canister call
    if (not Cycles.hasSufficientCycles(Cycles.INTERCANISTER_CALL_COST)) {
      return #err(#InsufficientCycles);
    };

    try {
      let ledger : ICRC2Ledger = actor(Principal.toText(ledger_principal));

      let args : ICRC2Types.TransferFromArgs = {
        from = { owner = from; subaccount = null };
        to = { owner = to; subaccount = null };
        amount = amount;
        fee = null; // Use default fee
        memo = memo;
        created_at_time = null;
        spender_subaccount = null;
      };

      Debug.print("ICRC2: Depositing " # Nat.toText(amount) # " from " # Principal.toText(from) # " to " # Principal.toText(to));

      switch (await (with cycles = Cycles.INTERCANISTER_CALL_COST) ledger.icrc2_transfer_from(args)) {
        case (#Ok(block_index)) {
          Debug.print("ICRC2: Deposit successful, block: " # Nat.toText(block_index));
          #ok(block_index)
        };
        case (#Err(#InsufficientFunds { balance })) {
          Debug.print("Insufficient funds. User balance: " # Nat.toText(balance));
          #err(#InsufficientBalance)
        };
        case (#Err(#InsufficientAllowance { allowance })) {
          #err(#InvalidAmount("Insufficient allowance: " # Nat.toText(allowance) # " < " # Nat.toText(amount)))
        };
        case (#Err(#BadFee { expected_fee })) {
          #err(#InvalidAmount("Bad fee, expected: " # Nat.toText(expected_fee)))
        };
        case (#Err(#TooOld)) {
          #err(#InternalError("Transaction too old"))
        };
        case (#Err(#CreatedInFuture { ledger_time })) {
          #err(#InternalError("Transaction created in future: " # Nat.toText(Nat64.toNat(ledger_time))))
        };
        case (#Err(#Duplicate { duplicate_of })) {
          #err(#InternalError("Duplicate transaction: " # Nat.toText(duplicate_of)))
        };
        case (#Err(#TemporarilyUnavailable)) {
          #err(#NetworkError("Ledger temporarily unavailable"))
        };
        case (#Err(#GenericError { error_code; message })) {
          #err(#InternalError("Ledger error " # Nat.toText(error_code) # ": " # message))
        };
        case (#Err(#BadBurn { min_burn_amount })) {
          #err(#InvalidAmount("Bad burn amount, min: " # Nat.toText(min_burn_amount)))
        };
      }
    } catch (e) {
      #err(#NetworkError("Failed to call ledger: " # Error.message(e)))
    }
  };

  /// Transfer tokens from canister to recipient (release/refund)
  public func transferTo(
    ledger_principal : Principal,
    to : Principal,
    amount : Nat,
    memo : ?Blob
  ) : async IntentResult<Nat> {
    // Check cycles
    if (not Cycles.hasSufficientCycles(Cycles.INTERCANISTER_CALL_COST)) {
      return #err(#InsufficientCycles);
    };

    try {
      let ledger : ICRC1Ledger = actor(Principal.toText(ledger_principal));

      let args : ICRC2Types.TransferArgs = {
        to = { owner = to; subaccount = null };
        amount = amount;
        fee = null; // Use default fee
        memo = memo;
        created_at_time = null;
        from_subaccount = null;
      };

      Debug.print("ICRC2: Transferring " # Nat.toText(amount) # " to " # Principal.toText(to));

      switch (await (with cycles = Cycles.INTERCANISTER_CALL_COST) ledger.icrc1_transfer(args)) {
        case (#Ok(block_index)) {
          Debug.print("ICRC2: Transfer successful, block: " # Nat.toText(block_index));
          #ok(block_index)
        };
        case (#Err(#InsufficientFunds { balance })) {
          Debug.print("Insufficient funds. Canister balance: " # Nat.toText(balance));
          #err(#InsufficientBalance)
        };
        case (#Err(#BadFee { expected_fee })) {
          #err(#InvalidAmount("Bad fee, expected: " # Nat.toText(expected_fee)))
        };
        case (#Err(#TooOld)) {
          #err(#InternalError("Transaction too old"))
        };
        case (#Err(#CreatedInFuture { ledger_time })) {
          #err(#InternalError("Transaction created in future: " # Nat.toText(Nat64.toNat(ledger_time))))
        };
        case (#Err(#Duplicate { duplicate_of })) {
          #err(#InternalError("Duplicate transaction: " # Nat.toText(duplicate_of)))
        };
        case (#Err(#TemporarilyUnavailable)) {
          #err(#NetworkError("Ledger temporarily unavailable"))
        };
        case (#Err(#GenericError { error_code; message })) {
          #err(#InternalError("Ledger error " # Nat.toText(error_code) # ": " # message))
        };
        case (#Err(#BadBurn { min_burn_amount })) {
          #err(#InvalidAmount("Bad burn amount, min: " # Nat.toText(min_burn_amount)))
        };
      }
    } catch (e) {
      #err(#NetworkError("Failed to call ledger: " # Error.message(e)))
    }
  };

  /// Query balance of an account
  public func getBalance(
    ledger_principal : Principal,
    account : Principal
  ) : async IntentResult<Nat> {
    // Check cycles
    if (not Cycles.hasSufficientCycles(Cycles.INTERCANISTER_CALL_COST)) {
      return #err(#InsufficientCycles);
    };

    try {
      let ledger : ICRC1Ledger = actor(Principal.toText(ledger_principal));

      let balance = await (with cycles = Cycles.INTERCANISTER_CALL_COST) ledger.icrc1_balance_of({
        owner = account;
        subaccount = null;
      });

      #ok(balance)
    } catch (e) {
      #err(#NetworkError("Failed to query balance: " # Error.message(e)))
    }
  };

  /// Query ledger fee
  public func getFee(ledger_principal : Principal) : async IntentResult<Nat> {
    // Check cycles
    if (not Cycles.hasSufficientCycles(Cycles.INTERCANISTER_CALL_COST)) {
      return #err(#InsufficientCycles);
    };

    try {
      let ledger : ICRC1Ledger = actor(Principal.toText(ledger_principal));

      let fee = await (with cycles = Cycles.INTERCANISTER_CALL_COST) ledger.icrc1_fee();

      #ok(fee)
    } catch (e) {
      #err(#NetworkError("Failed to query fee: " # Error.message(e)))
    }
  };
}
