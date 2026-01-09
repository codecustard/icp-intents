// TypeScript types for SimpleIntentPool
// Based on candid/SimpleIntentPool.did

import { Principal } from '@dfinity/principal';
import { ActorSubclass } from '@dfinity/agent';

export type IntentStatus =
  | { PendingQuote: null }
  | { Quoted: null }
  | { Confirmed: null }
  | { Deposited: null }
  | { Fulfilled: null }
  | { Cancelled: null }
  | { Expired: null };

export interface ChainSpec {
  chain: string;
  chain_id: [] | [bigint];
  token: string;
  network: string;
}

export interface Quote {
  solver: Principal;
  output_amount: bigint;
  fee: bigint;
  solver_tip: bigint;
  expiry: bigint;
  submitted_at: bigint;
  solver_dest_address: [] | [string];
}

export interface Intent {
  id: bigint;
  user: Principal;
  source: ChainSpec;
  destination: ChainSpec;
  source_amount: bigint;
  min_output: bigint;
  dest_recipient: string;
  created_at: bigint;
  deadline: bigint;
  verified_at: [] | [bigint];
  status: IntentStatus;
  quotes: Array<Quote>;
  selected_quote: [] | [Quote];
  escrow_balance: bigint;
  generated_address: [] | [string];
  protocol_fee_bps: bigint;
}

export type IntentError =
  | { NotFound: null }
  | { InvalidStatus: string }
  | { Unauthorized: null }
  | { InvalidAmount: string }
  | { ChainNotSupported: string }
  | { InvalidQuote: string }
  | { QuoteExpired: null }
  | { TransferFailed: string }
  | { VerificationFailed: string }
  | { DeadlineExceeded: null }
  | { InsufficientFunds: string }
  | { RateLimitExceeded: string };

export type IntentResult = { ok: bigint } | { err: IntentError };
export type IntentResultUnit = { ok: null } | { err: IntentError };
export type IntentResultText = { ok: string } | { err: IntentError };

export interface FeeBreakdown {
  protocol_fee: bigint;
  solver_fee: bigint;
  solver_tip: bigint;
  total_fee: bigint;
  net_output: bigint;
}

export type IntentResultFeeBreakdown = { ok: FeeBreakdown } | { err: IntentError };

export interface IntentPoolService {
  // Token Management
  registerToken: (symbol: string, ledger: Principal, decimals: number, fee: bigint) => Promise<void>;
  getTokenLedger: (symbol: string) => Promise<[] | [Principal]>;

  // Intent Lifecycle
  createIntent: (
    source_chain: string,
    source_token: string,
    source_amount: bigint,
    dest_chain: string,
    dest_token: string,
    min_output: bigint,
    dest_recipient: string,
    deadline_seconds: bigint
  ) => Promise<IntentResult>;
  submitQuote: (
    intent_id: bigint,
    output_amount: bigint,
    solver_fee: bigint,
    solver_tip: bigint
  ) => Promise<IntentResultUnit>;
  confirmQuote: (intent_id: bigint, solver: Principal) => Promise<IntentResultUnit>;
  depositTokens: (intent_id: bigint) => Promise<IntentResult>;
  verifyEVMDeposit: (intent_id: bigint, tx_hash: string) => Promise<IntentResultUnit>;
  verifyHoosatDeposit: (intent_id: bigint, tx_id: string) => Promise<IntentResultUnit>;
  fulfillIntent: (intent_id: bigint) => Promise<IntentResultFeeBreakdown>;
  cancelIntent: (intent_id: bigint) => Promise<IntentResultUnit>;

  // Query Functions
  getIntent: (id: bigint) => Promise<[] | [Intent]>;
  getUserIntents: (user: Principal) => Promise<Array<Intent>>;
  getSupportedChains: () => Promise<Array<string>>;
  getEscrowBalance: (user: Principal, token: string) => Promise<bigint>;
  getProtocolFees: () => Promise<Array<[string, bigint]>>;
  generateDepositAddress: (intent_id: bigint) => Promise<IntentResultText>;
}

export type IntentPoolActor = ActorSubclass<IntentPoolService>;
