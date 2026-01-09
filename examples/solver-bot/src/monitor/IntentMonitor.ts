// Intent monitor - polls intent pool for new intents

import { IntentPoolActor, Intent } from '../types/intent-pool.js';
import { logger } from '../utils/logger.js';
import { retryWithBackoff } from '../utils/retry.js';
import { Principal } from '@dfinity/principal';

export class IntentMonitor {
  private seenIntentIds: Set<string> = new Set();

  constructor(private intentPool: IntentPoolActor) {}

  async pollAllIntents(): Promise<Intent[]> {
    try {
      logger.debug('Polling for all intents');

      // Get all supported chains
      const chains = await retryWithBackoff(
        () => this.intentPool.getSupportedChains(),
        {},
        'getSupportedChains'
      );

      logger.debug(`Found ${chains.length} supported chains`, { chains });

      // For demo purposes, we poll by getting intents from known users
      // In production, you'd want a dedicated solver API endpoint
      // For now, return empty array - we'll rely on periodic full state polling
      return [];
    } catch (error) {
      logger.error('Failed to poll intents', { error: String(error) });
      return [];
    }
  }

  async getIntent(intentId: bigint): Promise<Intent | null> {
    try {
      const result = await retryWithBackoff(
        () => this.intentPool.getIntent(intentId),
        {},
        `getIntent(${intentId})`
      );

      if (result.length === 0) {
        return null;
      }

      return result[0];
    } catch (error) {
      logger.error(`Failed to get intent ${intentId}`, { error: String(error) });
      return null;
    }
  }

  async getUserIntents(user: Principal): Promise<Intent[]> {
    try {
      return await retryWithBackoff(
        () => this.intentPool.getUserIntents(user),
        {},
        `getUserIntents(${user.toText()})`
      );
    } catch (error) {
      logger.error(`Failed to get user intents for ${user.toText()}`, {
        error: String(error),
      });
      return [];
    }
  }

  filterNew(intents: Intent[]): Intent[] {
    const newIntents: Intent[] = [];

    for (const intent of intents) {
      const intentKey = intent.id.toString();
      if (!this.seenIntentIds.has(intentKey)) {
        this.seenIntentIds.add(intentKey);
        newIntents.push(intent);
      }
    }

    if (newIntents.length > 0) {
      logger.info(`Found ${newIntents.length} new intent(s)`, {
        intentIds: newIntents.map((i) => i.id.toString()),
      });
    }

    return newIntents;
  }

  markAsSeen(intentId: bigint) {
    this.seenIntentIds.add(intentId.toString());
  }

  hasSeen(intentId: bigint): boolean {
    return this.seenIntentIds.has(intentId.toString());
  }

  clearSeenIntents() {
    this.seenIntentIds.clear();
    logger.debug('Cleared seen intents cache');
  }
}
