/// Input validation utilities
///
/// Validates amounts, addresses, deadlines, and other user inputs

import Types "../core/Types";
import Errors "../core/Errors";
import Math "./Math";
import Time "mo:base/Time";
import Text "mo:base/Text";
import Char "mo:base/Char";
import Principal "mo:base/Principal";

module {
  type IntentError = Errors.IntentError;
  type SystemConfig = Types.SystemConfig;

  /// Validate intent amount
  public func validateAmount(amount : Nat, config : SystemConfig) : ?IntentError {
    if (amount == 0) {
      return ?#InvalidAmount("Amount must be greater than zero");
    };
    if (amount < config.min_intent_amount) {
      return ?#InvalidAmount("Amount below minimum");
    };
    if (amount > config.max_intent_amount) {
      return ?#InvalidAmount("Amount exceeds maximum");
    };
    null
  };

  /// Validate minimum output
  public func validateMinOutput(min_output : Nat, _source_amount : Nat) : ?IntentError {
    if (min_output == 0) {
      return ?#InvalidAmount("Minimum output must be greater than zero");
    };
    // Note: Cannot compare min_output to source_amount for cross-chain swaps
    // (different tokens, different decimals, different values)
    null
  };

  /// Validate deadline
  public func validateDeadline(deadline : Time.Time, currentTime : Time.Time, config : SystemConfig) : ?IntentError {
    if (deadline <= currentTime) {
      return ?#InvalidDeadline("Deadline must be in the future");
    };

    let maxDeadline = currentTime + (config.default_deadline_duration * 30); // 30x default
    if (deadline > maxDeadline) {
      return ?#InvalidDeadline("Deadline too far in the future");
    };
    null
  };

  /// Validate quote amount
  public func validateQuoteAmount(output_amount : Nat, min_output : Nat, _source_amount : Nat) : ?IntentError {
    if (output_amount == 0) {
      return ?#InvalidQuote("Output amount must be greater than zero");
    };
    if (output_amount < min_output) {
      return ?#InvalidQuote("Output amount below minimum");
    };
    // Note: Cannot sanity-check output vs source for cross-chain swaps
    // (different tokens with different values and decimals)
    null
  };

  /// Validate quote fee
  public func validateFee(fee : Nat, output_amount : Nat) : ?IntentError {
    // Fee should be reasonable (< 50% of output)
    if (fee >= output_amount / 2) {
      return ?#InvalidFee("Fee too high (>50% of output)");
    };
    null
  };

  /// Validate quote expiry
  public func validateQuoteExpiry(expiry : Time.Time, currentTime : Time.Time, intentDeadline : Time.Time) : ?IntentError {
    if (expiry <= currentTime) {
      return ?#InvalidQuote("Quote expiry must be in the future");
    };
    if (expiry > intentDeadline) {
      return ?#InvalidQuote("Quote expiry cannot exceed intent deadline");
    };
    null
  };

  /// Validate Ethereum address format (0x + 40 hex chars)
  public func validateEthAddress(address : Text) : ?IntentError {
    if (not Text.startsWith(address, #text "0x")) {
      return ?#InvalidAddress("Ethereum address must start with 0x");
    };
    if (Text.size(address) != 42) {
      return ?#InvalidAddress("Ethereum address must be 42 characters");
    };
    // Check hex characters
    let chars = Text.toIter(address);
    ignore chars.next(); // skip '0'
    ignore chars.next(); // skip 'x'
    for (c in chars) {
      if (not isHexChar(c)) {
        return ?#InvalidAddress("Invalid hex character in address");
      };
    };
    null
  };

  /// Validate Hoosat address format
  public func validateHoosatAddress(address : Text) : ?IntentError {
    // Normalize case
    let normalized = Text.replace(address, #text "hoosat:", "Hoosat:");

    if (not (Text.startsWith(normalized, #text "Hoosat:") or Text.startsWith(normalized, #text "hoosat:"))) {
      return ?#InvalidAddress("Hoosat address must start with 'Hoosat:' or 'hoosat:'");
    };
    if (Text.size(normalized) < 50) {
      return ?#InvalidAddress("Hoosat address too short");
    };
    null
  };

  /// Validate Bitcoin address format (basic check)
  public func validateBitcoinAddress(address : Text) : ?IntentError {
    let size = Text.size(address);
    if (size < 26 or size > 62) {
      return ?#InvalidAddress("Bitcoin address length invalid");
    };
    // More specific validation would check prefix (1, 3, bc1, etc.)
    null
  };

  /// Validate chain specification
  public func validateChainSpec(spec : Types.ChainSpec, _config : SystemConfig) : ?IntentError {
    if (Text.size(spec.chain) == 0) {
      return ?#InvalidChain("Chain name cannot be empty");
    };
    if (Text.size(spec.token) == 0) {
      return ?#InvalidToken("Token cannot be empty");
    };

    // Note: Chain support validation is done by ChainRegistry.validateSpec()
    // to avoid redundant checks and keep config.supported_chains optional

    null
  };

  /// Validate solver authorization
  public func validateSolver(solver : Principal, config : SystemConfig) : ?IntentError {
    switch (config.solver_allowlist) {
      case null { null }; // Permissionless
      case (?allowlist) {
        let isAllowed = checkAllowlist(solver, allowlist);
        if (not isAllowed) {
          ?#SolverNotAllowed
        } else {
          null
        }
      };
    }
  };

  /// Validate protocol fee basis points
  public func validateProtocolFeeBps(bps : Nat) : ?IntentError {
    if (bps > Math.MAX_BPS) {
      return ?#InvalidFee("Protocol fee exceeds 100%");
    };
    if (bps > 1000) { // 10%
      return ?#InvalidFee("Protocol fee too high (>10%)");
    };
    null
  };

  // Helper functions

  func isHexChar(c : Char) : Bool {
    (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')
  };

  func checkAllowlist(principal : Principal, allowlist : [Principal]) : Bool {
    for (allowed in allowlist.vals()) {
      if (Principal.equal(principal, allowed)) {
        return true;
      };
    };
    false
  };
}
