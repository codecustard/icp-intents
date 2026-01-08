/// Rate limiting and capacity management constants
///
/// DoS prevention configuration for intent creation and lifecycle management

module {
  /// Rate limit constants

  /// Maximum total intents a single user can create (lifetime)
  public let MAX_INTENTS_PER_USER : Nat = 100;

  /// Maximum active (non-terminal) intents per user at any time
  public let MAX_ACTIVE_INTENTS_PER_USER : Nat = 20;

  /// Maximum total intents globally (all users)
  public let MAX_TOTAL_INTENTS_GLOBAL : Nat = 10_000;

  /// Maximum active intents globally
  public let MAX_ACTIVE_INTENTS_GLOBAL : Nat = 5_000;

  /// Cleanup configuration

  /// How long to retain terminal intents before cleanup (7 days in nanoseconds)
  public let TERMINAL_INTENT_RETENTION : Int = 604_800_000_000_000;

  /// Maximum number of intents to clean up per call (prevent cycle exhaustion)
  public let MAX_CLEANUPS_PER_CALL : Nat = 100;
}
