/// System-wide constants
///
/// Centralized configuration values used across the SDK

module {
  /// Time constants

  /// One hour in nanoseconds (used for quote expiry)
  public let ONE_HOUR_NANOS : Int = 3_600_000_000_000;

  /// Fee constants

  /// Maximum reasonable protocol fee in basis points (10%)
  public let MAX_REASONABLE_PROTOCOL_FEE_BPS : Nat = 1000;

  /// Maximum reasonable total fee rate in basis points (10%)
  public let MAX_REASONABLE_TOTAL_FEE_BPS : Nat = 1000;

  /// Chain-specific constants

  /// Default Hoosat transaction fee in sompi
  public let HOOSAT_DEFAULT_FEE : Nat64 = 2000;

  /// Address validation constants

  /// Ethereum address length (0x + 40 hex chars)
  public let ETH_ADDRESS_LENGTH : Nat = 42;

  /// Minimum Hoosat address length
  public let HOOSAT_MIN_ADDRESS_LENGTH : Nat = 50;

  /// Minimum Bitcoin address length
  public let BITCOIN_MIN_ADDRESS_LENGTH : Nat = 26;

  /// Maximum Bitcoin address length
  public let BITCOIN_MAX_ADDRESS_LENGTH : Nat = 62;
}
