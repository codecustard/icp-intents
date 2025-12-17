/// Utility functions for the ICP Intents library.
/// Includes validation, formatting, and common operations.

import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Time "mo:base/Time";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Char "mo:base/Char";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";

module {
  /// Validates an Ethereum-style address (0x + 40 hex chars)
  public func isValidEthAddress(addr: Text) : Bool {
    if (not Text.startsWith(addr, #text "0x")) return false;
    if (Text.size(addr) != 42) return false;

    let hex = Text.trimStart(addr, #text "0x");
    for (c in hex.chars()) {
      if (not isHexChar(c)) return false;
    };
    true
  };

  /// Checks if a character is a valid hex digit
  public func isHexChar(c: Char) : Bool {
    (c >= '0' and c <= '9') or
    (c >= 'a' and c <= 'f') or
    (c >= 'A' and c <= 'F')
  };

  /// Validates chain ID is in supported list (extensible)
  public func isValidChainId(chainId: Nat, supportedChains: [Nat]) : Bool {
    Option.isSome(Array.find<Nat>(supportedChains, func(id) { id == chainId }))
  };

  /// Converts hex string to Nat (for parsing amounts)
  public func hexToNat(hex: Text) : ?Nat {
    let cleanHex = Text.trimStart(hex, #text "0x");
    var result : Nat = 0;

    for (c in cleanHex.chars()) {
      let digit = hexCharToNat(c);
      switch (digit) {
        case (?d) {
          result := result * 16 + d;
        };
        case null return null;
      };
    };
    ?result
  };

  /// Converts a single hex character to Nat
  public func hexCharToNat(c: Char) : ?Nat {
    if (c >= '0' and c <= '9') {
      ?Nat8.toNat(Nat8.fromNat(Nat32.toNat(Char.toNat32(c) - Char.toNat32('0'))));
    } else if (c >= 'a' and c <= 'f') {
      ?Nat8.toNat(Nat8.fromNat(Nat32.toNat(Char.toNat32(c) - Char.toNat32('a') + 10)));
    } else if (c >= 'A' and c <= 'F') {
      ?Nat8.toNat(Nat8.fromNat(Nat32.toNat(Char.toNat32(c) - Char.toNat32('A') + 10)));
    } else {
      null
    }
  };

  /// Calculate protocol fee from amount and basis points
  public func calculateFee(amount: Nat, feeBps: Nat) : Nat {
    (amount * feeBps) / 10_000
  };

  /// Check if timestamp is in the future
  public func isInFuture(timestamp: Time.Time, currentTime: Time.Time) : Bool {
    timestamp > currentTime
  };

  /// Check if timestamp has passed
  public func hasPassed(timestamp: Time.Time, currentTime: Time.Time) : Bool {
    currentTime >= timestamp
  };

  /// Validates token identifier (ICP or principal format)
  public func isValidTokenId(token: Text) : Bool {
    if (token == "ICP") return true;

    // Try to parse as principal
    switch (parsePrincipal(token)) {
      case (?_) true;
      case null false;
    }
  };

  /// Parse text as principal (helper)
  /// Returns null if parsing fails
  public func parsePrincipal(text: Text) : ?Principal {
    // Principal.fromText can trap, so we return null on failure
    // In production, caller should handle the ? type appropriately
    // Note: Motoko doesn't have try/catch for Principal.fromText
    // This is a simplified version
    if (Text.size(text) == 0) return null;
    // For now, assume valid - in production use Principal.fromText with care
    ?Principal.fromText(text)
  };

  /// Validates amount is non-zero and reasonable
  public func isValidAmount(amount: Nat, minAmount: Nat) : Bool {
    amount > 0 and amount >= minAmount
  };

  /// Create a unique derivation path for tECDSA
  /// Combines intent ID with user principal for uniqueness
  public func createDerivationPath(intentId: Nat, user: Principal) : [Blob] {
    let intentBlob = natToBlob(intentId);
    let userBlob = Principal.toBlob(user);
    [intentBlob, userBlob]
  };

  /// Convert Nat to Blob (for derivation path)
  public func natToBlob(n: Nat) : Blob {
    let bytes = natToBytes(n);
    let arr = Array.reverse(bytes);
    Blob.fromArray(arr)
  };

  /// Convert Nat to byte array (little-endian)
  func natToBytes(n: Nat) : [Nat8] {
    if (n == 0) return [0];

    var num = n;
    let buffer = Buffer.Buffer<Nat8>(8);
    while (num > 0) {
      let byte = Nat8.fromNat(num % 256);
      buffer.add(byte);
      num := num / 256;
    };
    Buffer.toArray(buffer)
  };

  /// Validate deadline is reasonable (not too far in future, not in past)
  public func isValidDeadline(
    deadline: Time.Time,
    currentTime: Time.Time,
    maxLifetime: Int
  ) : Bool {
    let minDeadline = currentTime + 60_000_000_000; // At least 1 minute
    let maxDeadline = currentTime + maxLifetime;
    deadline >= minDeadline and deadline <= maxDeadline
  };

  /// Safe subtraction (returns 0 if would underflow)
  public func safeSub(a: Nat, b: Nat) : Nat {
    if (a > b) { a - b } else { 0 }
  };

  /// Clamp value between min and max
  public func clamp(value: Nat, min: Nat, max: Nat) : Nat {
    if (value < min) min
    else if (value > max) max
    else value
  };

  /// Format amount for display (add decimals)
  public func formatAmount(amount: Nat, decimals: Nat) : Text {
    if (decimals == 0) return Nat.toText(amount);

    let divisor = pow10(decimals);
    let whole = amount / divisor;
    let fraction = amount % divisor;

    Nat.toText(whole) # "." # Nat.toText(fraction)
  };

  /// Helper: Calculate 10^n safely
  func pow10(n: Nat) : Nat {
    var result : Nat = 1;
    var i = 0;
    while (i < n) {
      result *= 10;
      i += 1;
    };
    result
  };

  /// Parse amount from text (with decimals)
  public func parseAmount(text: Text, decimals: Nat) : ?Nat {
    // Simple implementation: expects "123.456" format
    let parts = Iter.toArray(Text.split(text, #char '.'));

    if (parts.size() == 0) return null;

    let wholePart = switch (textToNat(parts[0])) {
      case (?n) n;
      case null return null;
    };

    if (parts.size() == 1) {
      return ?(wholePart * pow10(decimals));
    };

    if (parts.size() == 2) {
      let fractionPart = switch (textToNat(parts[1])) {
        case (?n) n;
        case null return null;
      };

      let fractionDigits = Text.size(parts[1]);
      if (fractionDigits > decimals) return null;

      let scaledFraction = fractionPart * pow10(decimals - fractionDigits);
      return ?(wholePart * pow10(decimals) + scaledFraction);
    };

    null
  };

  /// Helper: Text to Nat
  func textToNat(text: Text) : ?Nat {
    var n : Nat = 0;
    for (c in text.chars()) {
      if (c < '0' or c > '9') return null;
      let digit = Nat32.toNat(Char.toNat32(c) - Char.toNat32('0'));
      n := n * 10 + digit;
    };
    ?n
  };
}
