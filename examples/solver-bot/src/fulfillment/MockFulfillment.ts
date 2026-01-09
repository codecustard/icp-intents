// Mock fulfillment - simulates token delivery on destination chain

import { Intent, Quote } from '../types/intent-pool.js';
import { SolverConfig } from '../config.js';
import { logger } from '../utils/logger.js';
import { randomBytes } from 'crypto';

export interface FulfillmentResult {
  success: boolean;
  txHash: string;
  error?: string;
}

export class MockFulfillment {
  constructor(private config: SolverConfig) {}

  async fulfill(intent: Intent, quote: Quote): Promise<FulfillmentResult> {
    const intentId = intent.id.toString();

    logger.info('Starting mock fulfillment', {
      intentId,
      destChain: intent.destination.chain,
      destToken: intent.destination.token,
      outputAmount: quote.output_amount.toString(),
      recipient: intent.dest_recipient,
    });

    try {
      // Simulate network delay
      await this.simulateDelay(2000, 5000);

      // Generate mock transaction hash
      const txHash = this.generateMockTxHash(intent.destination.chain);

      logger.success('Mock fulfillment completed', {
        intentId,
        txHash,
        destChain: intent.destination.chain,
        outputAmount: quote.output_amount.toString(),
      });

      return {
        success: true,
        txHash,
      };
    } catch (error) {
      logger.error('Mock fulfillment failed', {
        intentId,
        error: String(error),
      });

      return {
        success: false,
        txHash: '',
        error: String(error),
      };
    }
  }

  private async simulateDelay(minMs: number, maxMs: number): Promise<void> {
    const delay = Math.floor(Math.random() * (maxMs - minMs + 1)) + minMs;
    logger.debug(`Simulating fulfillment delay: ${delay}ms`);
    return new Promise((resolve) => setTimeout(resolve, delay));
  }

  private generateMockTxHash(chain: string): string {
    // Generate different format tx hashes based on chain
    if (chain === 'ethereum' || chain === 'sepolia') {
      // EVM chains use 0x + 64 hex characters
      const hash = randomBytes(32).toString('hex');
      return `0x${hash}`;
    } else if (chain === 'hoosat') {
      // Hoosat uses base58-like format (simplified)
      const hash = randomBytes(32).toString('hex');
      return hash;
    } else if (chain === 'icp') {
      // ICP uses different format (simplified)
      const hash = randomBytes(32).toString('hex');
      return hash;
    } else {
      // Default
      const hash = randomBytes(32).toString('hex');
      return hash;
    }
  }

  validateAddress(chain: string, address: string): boolean {
    // Basic address validation (simplified for demo)
    if (chain === 'ethereum' || chain === 'sepolia') {
      // EVM addresses start with 0x and are 42 characters
      return address.startsWith('0x') && address.length === 42;
    } else if (chain === 'hoosat') {
      // Hoosat addresses (simplified - just check non-empty)
      return address.length > 0;
    } else if (chain === 'icp') {
      // ICP principal addresses
      return address.length > 0;
    }
    return false;
  }
}
