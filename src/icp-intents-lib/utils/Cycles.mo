/// Cycle monitoring and management utilities
///
/// Helps canisters monitor and manage their cycle balance

import ExperimentalCycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";

module {
  public type CycleInfo = {
    balance : Nat;
    reserved : Nat;
    available : Nat;
  };

  public type CycleAlert = {
    #Low : Nat; // Balance below threshold
    #Critical : Nat; // Balance critically low
    #Healthy;
  };

  // Cycle thresholds
  public let MIN_CYCLES : Nat = 100_000_000_000; // 100B cycles
  public let CRITICAL_CYCLES : Nat = 50_000_000_000; // 50B cycles
  public let LOW_CYCLES : Nat = 500_000_000_000; // 500B cycles

  // Operation costs (approximate)
  public let ECDSA_SIGNING_COST : Nat = 30_000_000_000; // 30B cycles
  public let ECDSA_PUBKEY_COST : Nat = 10_000_000_000; // 10B cycles
  public let HTTP_OUTCALL_COST : Nat = 230_000_000_000; // 230B cycles
  public let COMPUTE_COST : Nat = 1_000_000; // 1M cycles per operation

  /// Get current cycle balance
  public func balance() : Nat {
    ExperimentalCycles.balance()
  };

  /// Get available cycles (balance - reserved)
  public func available() : Nat {
    ExperimentalCycles.available()
  };

  /// Get cycle info
  public func getInfo() : CycleInfo {
    let bal = balance();
    let avail = available();
    {
      balance = bal;
      reserved = if (bal > avail) { bal - avail } else { 0 };
      available = avail;
    }
  };

  /// Check cycle health status
  public func checkHealth() : CycleAlert {
    let bal = balance();
    if (bal < CRITICAL_CYCLES) {
      #Critical(bal)
    } else if (bal < LOW_CYCLES) {
      #Low(bal)
    } else {
      #Healthy
    }
  };

  /// Check if sufficient cycles for operation
  public func hasSufficientCycles(required : Nat) : Bool {
    available() >= required
  };

  /// Estimate cycles needed for ECDSA operations
  public func estimateECDSAOps(num_signatures : Nat, num_pubkeys : Nat) : Nat {
    (num_signatures * ECDSA_SIGNING_COST) + (num_pubkeys * ECDSA_PUBKEY_COST)
  };

  /// Estimate cycles for HTTP outcalls
  public func estimateHTTPOutcalls(num_calls : Nat) : Nat {
    num_calls * HTTP_OUTCALL_COST
  };

  /// Log cycle info
  public func logCycleInfo() {
    let info = getInfo();
    Debug.print("Cycles - Balance: " # debug_show(info.balance) #
                ", Reserved: " # debug_show(info.reserved) #
                ", Available: " # debug_show(info.available));
  };

  /// Log cycle alert if needed
  public func logIfLow() {
    switch (checkHealth()) {
      case (#Critical(bal)) {
        Debug.print("⚠️ CRITICAL: Cycle balance critically low: " # debug_show(bal));
      };
      case (#Low(bal)) {
        Debug.print("⚠️ WARNING: Cycle balance low: " # debug_show(bal));
      };
      case (#Healthy) {};
    }
  };

  /// Note: Cycle acceptance and adding should be done directly via ExperimentalCycles
  /// in actor context where system capability is available
}
