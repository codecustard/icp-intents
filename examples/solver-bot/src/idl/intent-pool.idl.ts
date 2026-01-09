// IDL factory for SimpleIntentPool
// Auto-generated from candid/SimpleIntentPool.did

export const idlFactory = ({ IDL }: any) => {
  const IntentStatus = IDL.Variant({
    'PendingQuote' : IDL.Null,
    'Quoted' : IDL.Null,
    'Confirmed' : IDL.Null,
    'Deposited' : IDL.Null,
    'Fulfilled' : IDL.Null,
    'Cancelled' : IDL.Null,
    'Expired' : IDL.Null,
  });

  const ChainSpec = IDL.Record({
    'chain' : IDL.Text,
    'chain_id' : IDL.Opt(IDL.Nat64),
    'token' : IDL.Text,
    'network' : IDL.Text,
  });

  const Quote = IDL.Record({
    'solver' : IDL.Principal,
    'output_amount' : IDL.Nat,
    'fee' : IDL.Nat,
    'solver_tip' : IDL.Nat,
    'expiry' : IDL.Int,
    'submitted_at' : IDL.Int,
    'solver_dest_address' : IDL.Opt(IDL.Text),
  });

  const Intent = IDL.Record({
    'id' : IDL.Nat,
    'user' : IDL.Principal,
    'source' : ChainSpec,
    'destination' : ChainSpec,
    'source_amount' : IDL.Nat,
    'min_output' : IDL.Nat,
    'dest_recipient' : IDL.Text,
    'created_at' : IDL.Int,
    'deadline' : IDL.Int,
    'verified_at' : IDL.Opt(IDL.Int),
    'status' : IntentStatus,
    'quotes' : IDL.Vec(Quote),
    'selected_quote' : IDL.Opt(Quote),
    'escrow_balance' : IDL.Nat,
    'generated_address' : IDL.Opt(IDL.Text),
    'protocol_fee_bps' : IDL.Nat,
  });

  const IntentError = IDL.Variant({
    'NotFound' : IDL.Null,
    'InvalidStatus' : IDL.Text,
    'Unauthorized' : IDL.Null,
    'InvalidAmount' : IDL.Text,
    'ChainNotSupported' : IDL.Text,
    'InvalidQuote' : IDL.Text,
    'QuoteExpired' : IDL.Null,
    'TransferFailed' : IDL.Text,
    'VerificationFailed' : IDL.Text,
    'DeadlineExceeded' : IDL.Null,
    'InsufficientFunds' : IDL.Text,
    'RateLimitExceeded' : IDL.Text,
  });

  const IntentResult = IDL.Variant({
    'ok' : IDL.Nat,
    'err' : IntentError,
  });

  const IntentResultUnit = IDL.Variant({
    'ok' : IDL.Null,
    'err' : IntentError,
  });

  const FeeBreakdown = IDL.Record({
    'protocol_fee' : IDL.Nat,
    'solver_fee' : IDL.Nat,
    'solver_tip' : IDL.Nat,
    'total_fee' : IDL.Nat,
    'net_output' : IDL.Nat,
  });

  const IntentResultFeeBreakdown = IDL.Variant({
    'ok' : FeeBreakdown,
    'err' : IntentError,
  });

  const IntentResultText = IDL.Variant({
    'ok' : IDL.Text,
    'err' : IntentError,
  });

  return IDL.Service({
    'registerToken' : IDL.Func([IDL.Text, IDL.Principal, IDL.Nat8, IDL.Nat], [], []),
    'getTokenLedger' : IDL.Func([IDL.Text], [IDL.Opt(IDL.Principal)], ['query']),
    'createIntent' : IDL.Func(
      [IDL.Text, IDL.Text, IDL.Nat, IDL.Text, IDL.Text, IDL.Nat, IDL.Text, IDL.Nat],
      [IntentResult],
      []
    ),
    'submitQuote' : IDL.Func([IDL.Nat, IDL.Nat, IDL.Nat, IDL.Nat], [IntentResultUnit], []),
    'confirmQuote' : IDL.Func([IDL.Nat, IDL.Principal], [IntentResultUnit], []),
    'depositTokens' : IDL.Func([IDL.Nat], [IntentResult], []),
    'verifyEVMDeposit' : IDL.Func([IDL.Nat, IDL.Text], [IntentResultUnit], []),
    'verifyHoosatDeposit' : IDL.Func([IDL.Nat, IDL.Text], [IntentResultUnit], []),
    'fulfillIntent' : IDL.Func([IDL.Nat], [IntentResultFeeBreakdown], []),
    'cancelIntent' : IDL.Func([IDL.Nat], [IntentResultUnit], []),
    'getIntent' : IDL.Func([IDL.Nat], [IDL.Opt(Intent)], ['query']),
    'getUserIntents' : IDL.Func([IDL.Principal], [IDL.Vec(Intent)], ['query']),
    'getSupportedChains' : IDL.Func([], [IDL.Vec(IDL.Text)], ['query']),
    'getEscrowBalance' : IDL.Func([IDL.Principal, IDL.Text], [IDL.Nat], ['query']),
    'getProtocolFees' : IDL.Func([], [IDL.Vec(IDL.Tuple(IDL.Text, IDL.Nat))], ['query']),
    'generateDepositAddress' : IDL.Func([IDL.Nat], [IntentResultText], []),
  });
};
