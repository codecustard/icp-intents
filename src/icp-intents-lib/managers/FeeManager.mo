/// Fee calculation and collection management
///
/// Handles protocol fees, solver fees, and tips

import Types "../core/Types";
import Math "../utils/Math";
import Constants "../utils/Constants";
import HashMap "mo:base/HashMap";
import Text "mo:base/Text";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";

module {
  type FeeBreakdown = Types.FeeBreakdown;
  type Quote = Types.Quote;

  /// Fee state for tracking collected fees
  public type FeeState = {
    var protocol_fees : HashMap.HashMap<Text, Nat>; // token -> collected_amount
    var total_fees_usd : Nat; // Approximate total in USD cents
  };

  /// Initialize fee state
  public func init() : FeeState {
    {
      var protocol_fees = HashMap.HashMap<Text, Nat>(10, Text.equal, Text.hash);
      var total_fees_usd = 0;
    }
  };

  /// Calculate complete fee breakdown
  ///
  /// Computes protocol fee, solver fee, solver tip, and net output for an intent fulfillment.
  ///
  /// **Security**: Validates total fees don't exceed output amount to prevent underflow.
  /// Returns null if fees are invalid, preventing transaction from completing.
  ///
  /// Parameters:
  /// - `output_amount`: Total amount the solver will provide
  /// - `protocol_fee_bps`: Protocol fee in basis points (e.g., 30 = 0.3%)
  /// - `quote`: The selected quote containing solver fee and tip
  ///
  /// Returns:
  /// - `?FeeBreakdown` with all fees calculated if valid
  /// - `null` if total fees exceed output amount
  public func calculateFees(
    output_amount : Nat,
    protocol_fee_bps : Nat,
    quote : Quote
  ) : ?FeeBreakdown {
    // Calculate protocol fee
    let protocol_fee = Math.calculateBps(output_amount, protocol_fee_bps);

    // Get solver fee and tip from quote
    let solver_fee = quote.fee;
    let solver_tip = quote.solver_tip;

    // Calculate total fees
    let total_fees = protocol_fee + solver_fee + solver_tip;

    // Validate total fees don't exceed output
    if (total_fees > output_amount) {
      return null;
    };

    // Calculate net output to user (safe because of check above)
    let net_output = switch (Math.safeSub(output_amount, total_fees)) {
      case null { return null }; // Should never happen due to check above
      case (?net) { net };
    };

    ?{
      protocol_fee = protocol_fee;
      solver_fee = solver_fee;
      solver_tip = solver_tip;
      total_fees = total_fees;
      net_output = net_output;
    }
  };

  /// Record collected protocol fee
  public func recordProtocolFee(
    state : FeeState,
    token : Text,
    amount : Nat
  ) {
    let current = switch (state.protocol_fees.get(token)) {
      case null { 0 };
      case (?amt) { amt };
    };
    state.protocol_fees.put(token, current + amount);
  };

  /// Get collected fees for a token
  public func getCollectedFees(state : FeeState, token : Text) : Nat {
    switch (state.protocol_fees.get(token)) {
      case null { 0 };
      case (?amt) { amt };
    }
  };

  /// Get all collected fees
  public func getAllCollectedFees(state : FeeState) : [(Text, Nat)] {
    Iter.toArray(state.protocol_fees.entries())
  };

  /// Reset fees for a token (after withdrawal)
  public func resetFees(state : FeeState, token : Text) {
    state.protocol_fees.delete(token);
  };

  /// Calculate total value (for statistics)
  public func calculateTotalValue(
    fees : [(Text, Nat)],
    prices : HashMap.HashMap<Text, Nat> // token -> price in USD cents
  ) : Nat {
    var total : Nat = 0;
    for ((token, amount) in fees.vals()) {
      switch (prices.get(token)) {
        case null {}; // Skip if no price
        case (?price) {
          let value = (amount * price) / 1_000_000_000_000_000_000; // Assume 18 decimals
          total += value;
        };
      };
    };
    total
  };

  /// Validate fee parameters
  public func validateFeeParams(
    output_amount : Nat,
    protocol_fee_bps : Nat,
    solver_fee : Nat,
    solver_tip : Nat
  ) : Bool {
    // Total fees shouldn't exceed output
    let total_fees = Math.calculateBps(output_amount, protocol_fee_bps) + solver_fee + solver_tip;
    total_fees <= output_amount
  };

  /// Calculate effective fee rate (total fees as percentage of output)
  public func effectiveFeeRate(fees : FeeBreakdown, output_amount : Nat) : Nat {
    if (output_amount == 0) {
      return 0;
    };
    // Return in basis points
    (fees.total_fees * Math.MAX_BPS) / output_amount
  };

  /// Check if fees are reasonable (< 10%)
  public func areFeesReasonable(fees : FeeBreakdown, output_amount : Nat) : Bool {
    let rate = effectiveFeeRate(fees, output_amount);
    rate < Constants.MAX_REASONABLE_TOTAL_FEE_BPS
  };
}
