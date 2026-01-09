// Intent filter - checks if intents match solver capabilities

import { Intent, IntentStatus } from '../types/intent-pool.js';
import { SolverConfig } from '../config.js';
import { logger } from '../utils/logger.js';

export class IntentFilter {
  constructor(private config: SolverConfig) {}

  canHandle(intent: Intent): boolean {
    const intentId = intent.id.toString();

    // Check if intent is in a quotable state
    if (!this.isQuotableStatus(intent.status)) {
      logger.debug(`Intent ${intentId} not in quotable status`, {
        status: this.getStatusName(intent.status),
      });
      return false;
    }

    // Check if deadline is reasonable (at least 5 minutes from now)
    const now = BigInt(Date.now()) * 1_000_000n; // Convert to nanoseconds
    const minDeadline = now + 300_000_000_000n; // 5 minutes in nanoseconds
    if (intent.deadline < minDeadline) {
      logger.debug(`Intent ${intentId} deadline too soon`, {
        deadline: intent.deadline.toString(),
        minDeadline: minDeadline.toString(),
      });
      return false;
    }

    // Check if source chain is supported
    if (!this.config.supportedChains.has(intent.source.chain)) {
      logger.debug(`Intent ${intentId} source chain not supported`, {
        chain: intent.source.chain,
        supported: Array.from(this.config.supportedChains),
      });
      return false;
    }

    // Check if destination chain is supported
    if (!this.config.supportedChains.has(intent.destination.chain)) {
      logger.debug(`Intent ${intentId} destination chain not supported`, {
        chain: intent.destination.chain,
        supported: Array.from(this.config.supportedChains),
      });
      return false;
    }

    // Check if source token is supported
    if (!this.config.supportedTokens.has(intent.source.token)) {
      logger.debug(`Intent ${intentId} source token not supported`, {
        token: intent.source.token,
        supported: Array.from(this.config.supportedTokens),
      });
      return false;
    }

    // Check if destination token is supported
    if (!this.config.supportedTokens.has(intent.destination.token)) {
      logger.debug(`Intent ${intentId} destination token not supported`, {
        token: intent.destination.token,
        supported: Array.from(this.config.supportedTokens),
      });
      return false;
    }

    // Check if amounts are reasonable (not zero)
    if (intent.source_amount === 0n || intent.min_output === 0n) {
      logger.debug(`Intent ${intentId} has zero amounts`, {
        sourceAmount: intent.source_amount.toString(),
        minOutput: intent.min_output.toString(),
      });
      return false;
    }

    logger.debug(`Intent ${intentId} passed all filters`, {
      sourceChain: intent.source.chain,
      destChain: intent.destination.chain,
      sourceToken: intent.source.token,
      destToken: intent.destination.token,
    });

    return true;
  }

  private isQuotableStatus(status: IntentStatus): boolean {
    return 'PendingQuote' in status || 'Quoted' in status;
  }

  private getStatusName(status: IntentStatus): string {
    if ('PendingQuote' in status) return 'PendingQuote';
    if ('Quoted' in status) return 'Quoted';
    if ('Confirmed' in status) return 'Confirmed';
    if ('Deposited' in status) return 'Deposited';
    if ('Fulfilled' in status) return 'Fulfilled';
    if ('Cancelled' in status) return 'Cancelled';
    if ('Expired' in status) return 'Expired';
    return 'Unknown';
  }

  isDeposited(intent: Intent): boolean {
    return 'Deposited' in intent.status;
  }

  isFulfilledOrCancelled(intent: Intent): boolean {
    return 'Fulfilled' in intent.status || 'Cancelled' in intent.status;
  }
}
