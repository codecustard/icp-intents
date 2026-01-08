/// Comprehensive error types for the intent system
///
/// Provides granular error handling for all operations across the SDK

import Text "mo:base/Text";

module {
  /// Top-level result type for intent operations
  public type IntentResult<T> = {
    #ok : T;
    #err : IntentError;
  };

  /// Comprehensive error types covering all intent operations
  public type IntentError = {
    // Intent lifecycle errors
    #NotFound;
    #AlreadyExists;
    #InvalidStatus : Text; // e.g., "Cannot quote a fulfilled intent"
    #Expired;
    #Cancelled;

    // Authorization errors
    #Unauthorized : Text;
    #SolverNotAllowed;
    #NotIntentCreator;
    #NotSelectedSolver;

    // Validation errors
    #InvalidAmount : Text;
    #InvalidAddress : Text;
    #InvalidDeadline : Text;
    #InvalidChain : Text;
    #InvalidToken : Text;
    #InvalidQuote : Text;
    #InvalidFee : Text;
    #RateLimitExceeded : Text;

    // Escrow errors
    #InsufficientBalance;
    #EscrowLockFailed : Text;
    #EscrowReleaseFailed : Text;

    // Chain verification errors
    #ChainNotSupported : Text;
    #VerificationFailed : Text;
    #InvalidProof : Text;
    #RPCError : Text;
    #ConsensusFailure : Text;

    // Cryptographic errors
    #ECDSAError : Text;
    #SigningFailed : Text;
    #InvalidSignature : Text;
    #DerivationFailed : Text;

    // Network errors
    #NetworkError : Text;
    #HTTPOutcallFailed : Text;
    #BroadcastFailed : Text;

    // System errors
    #InternalError : Text;
    #InsufficientCycles;
    #UpgradeFailed : Text;
    #ConfigurationError : Text;
  };

  /// Convert error to human-readable message
  public func errorToText(error : IntentError) : Text {
    switch (error) {
      case (#NotFound) { "Intent not found" };
      case (#AlreadyExists) { "Intent already exists" };
      case (#InvalidStatus(msg)) { "Invalid status: " # msg };
      case (#Expired) { "Intent has expired" };
      case (#Cancelled) { "Intent was cancelled" };

      case (#Unauthorized(msg)) { "Unauthorized: " # msg };
      case (#SolverNotAllowed) { "Solver not in allowlist" };
      case (#NotIntentCreator) { "Only intent creator can perform this action" };
      case (#NotSelectedSolver) { "Only selected solver can perform this action" };

      case (#InvalidAmount(msg)) { "Invalid amount: " # msg };
      case (#InvalidAddress(msg)) { "Invalid address: " # msg };
      case (#InvalidDeadline(msg)) { "Invalid deadline: " # msg };
      case (#InvalidChain(msg)) { "Invalid chain: " # msg };
      case (#InvalidToken(msg)) { "Invalid token: " # msg };
      case (#InvalidQuote(msg)) { "Invalid quote: " # msg };
      case (#InvalidFee(msg)) { "Invalid fee: " # msg };
      case (#RateLimitExceeded(msg)) { "Rate limit exceeded: " # msg };

      case (#InsufficientBalance) { "Insufficient balance" };
      case (#EscrowLockFailed(msg)) { "Failed to lock escrow: " # msg };
      case (#EscrowReleaseFailed(msg)) { "Failed to release escrow: " # msg };

      case (#ChainNotSupported(chain)) { "Chain not supported: " # chain };
      case (#VerificationFailed(msg)) { "Verification failed: " # msg };
      case (#InvalidProof(msg)) { "Invalid proof: " # msg };
      case (#RPCError(msg)) { "RPC error: " # msg };
      case (#ConsensusFailure(msg)) { "RPC consensus failure: " # msg };

      case (#ECDSAError(msg)) { "ECDSA error: " # msg };
      case (#SigningFailed(msg)) { "Signing failed: " # msg };
      case (#InvalidSignature(msg)) { "Invalid signature: " # msg };
      case (#DerivationFailed(msg)) { "Address derivation failed: " # msg };

      case (#NetworkError(msg)) { "Network error: " # msg };
      case (#HTTPOutcallFailed(msg)) { "HTTP outcall failed: " # msg };
      case (#BroadcastFailed(msg)) { "Transaction broadcast failed: " # msg };

      case (#InternalError(msg)) { "Internal error: " # msg };
      case (#InsufficientCycles) { "Insufficient cycles" };
      case (#UpgradeFailed(msg)) { "Upgrade failed: " # msg };
      case (#ConfigurationError(msg)) { "Configuration error: " # msg };
    }
  };

  /// Check if error is retryable
  public func isRetryable(error : IntentError) : Bool {
    switch (error) {
      // Retryable network/temporary errors
      case (#NetworkError(_)) { true };
      case (#HTTPOutcallFailed(_)) { true };
      case (#RPCError(_)) { true };
      case (#InsufficientCycles) { true };

      // Non-retryable errors
      case (_) { false };
    }
  };

  /// Check if error is terminal (intent should be cancelled)
  public func isTerminal(error : IntentError) : Bool {
    switch (error) {
      case (#Expired) { true };
      case (#Cancelled) { true };
      case (#InvalidStatus(_)) { true };
      case (#InvalidChain(_)) { true };
      case (#ChainNotSupported(_)) { true };
      case (_) { false };
    }
  };
}
