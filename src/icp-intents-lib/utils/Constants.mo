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

  /// JSON parsing security limits

  /// Maximum transaction hash length (hex strings)
  public let MAX_TX_HASH_LENGTH : Nat = 100;

  /// Maximum block hash length (hex strings)
  public let MAX_BLOCK_HASH_LENGTH : Nat = 100;

  /// Maximum address length (covers all chain formats)
  public let MAX_ADDRESS_LENGTH : Nat = 120;

  /// Maximum generic JSON field length
  public let MAX_JSON_FIELD_LENGTH : Nat = 256;

  /// Maximum block height/number (2^53 - 1, JavaScript safe integer limit)
  public let MAX_BLOCK_HEIGHT : Nat = 9_007_199_254_740_991;

  /// Maximum token amount value (2^80, supports very large amounts)
  public let MAX_AMOUNT_VALUE : Nat = 1_208_925_819_614_629_174_706_176;

  /// Maximum confirmations count
  public let MAX_CONFIRMATIONS : Nat = 100_000;
}
