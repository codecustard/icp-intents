/// Safe mathematical operations with overflow protection
///
/// Provides checked arithmetic and basis point calculations

import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";

module {
  public let MAX_BPS : Nat = 10_000; // 100% in basis points

  /// Safe addition with overflow check
  public func safeAdd(a : Nat, b : Nat) : ?Nat {
    // Motoko Nat addition doesn't overflow, just returns result
    ?(a + b)
  };

  /// Safe subtraction with underflow check
  public func safeSub(a : Nat, b : Nat) : ?Nat {
    if (a < b) {
      null
    } else {
      ?(a - b)
    }
  };

  /// Safe multiplication with overflow check
  public func safeMul(a : Nat, b : Nat) : ?Nat {
    // Motoko Nat multiplication doesn't overflow
    ?(a * b)
  };

  /// Safe division with zero check
  public func safeDiv(a : Nat, b : Nat) : ?Nat {
    if (b == 0) {
      null
    } else {
      ?(a / b)
    }
  };

  /// Calculate percentage (returns amount * bps / 10000)
  /// Example: calculateBps(1000, 30) = 3 (0.3% of 1000)
  public func calculateBps(amount : Nat, bps : Nat) : Nat {
    if (bps > MAX_BPS) {
      return 0; // Invalid basis points
    };
    (amount * bps) / MAX_BPS
  };

  /// Calculate fee and net amount
  /// Returns (fee, net_amount)
  public func calculateFee(gross : Nat, fee_bps : Nat) : (Nat, Nat) {
    let fee = calculateBps(gross, fee_bps);
    let net = if (gross >= fee) { gross - fee } else { 0 };
    (fee, net)
  };

  /// Calculate minimum with zero floor
  public func min(a : Nat, b : Nat) : Nat {
    if (a < b) { a } else { b }
  };

  /// Calculate maximum
  public func max(a : Nat, b : Nat) : Nat {
    if (a > b) { a } else { b }
  };

  /// Check if amount is within bounds
  public func isInBounds(amount : Nat, min_amount : Nat, max_amount : Nat) : Bool {
    amount >= min_amount and amount <= max_amount
  };

  /// Calculate slippage tolerance
  /// Returns minimum acceptable amount given max slippage in bps
  public func applySlippage(amount : Nat, slippage_bps : Nat) : Nat {
    let slippage = calculateBps(amount, slippage_bps);
    if (amount > slippage) {
      amount - slippage
    } else {
      0
    }
  };

  /// Convert basis points to percentage string
  public func bpsToPercent(bps : Nat) : Text {
    let whole = bps / 100;
    let decimal = bps % 100;
    Nat.toText(whole) # "." # (if (decimal < 10) { "0" } else { "" }) # Nat.toText(decimal) # "%"
  };

  /// Safe Nat to Nat64 conversion
  public func natToNat64(n : Nat) : ?Nat64 {
    if (n > 18446744073709551615) { // Nat64 max
      null
    } else {
      ?Nat64.fromNat(n)
    }
  };

  /// Safe Nat64 to Nat conversion
  public func nat64ToNat(n : Nat64) : Nat {
    Nat64.toNat(n)
  };

  /// Calculate proportional share
  /// Returns (amount * numerator / denominator)
  public func proportional(amount : Nat, numerator : Nat, denominator : Nat) : ?Nat {
    if (denominator == 0) {
      return null;
    };
    switch (safeMul(amount, numerator)) {
      case null { null };
      case (?product) { safeDiv(product, denominator) };
    }
  };

  /// Sum array of Nats with overflow check
  public func sum(amounts : [Nat]) : ?Nat {
    var total : Nat = 0;
    for (amount in amounts.vals()) {
      switch (safeAdd(total, amount)) {
        case null { return null };
        case (?newTotal) { total := newTotal };
      };
    };
    ?total
  };

  /// Calculate average (floor division)
  public func average(amounts : [Nat]) : ?Nat {
    if (amounts.size() == 0) {
      return null;
    };
    switch (sum(amounts)) {
      case null { null };
      case (?total) { safeDiv(total, amounts.size()) };
    }
  };
}
