// Mock pricing engine using fixed exchange rates

import { Intent } from '../types/intent-pool.js';
import { SolverConfig } from '../config.js';
import { logger } from '../utils/logger.js';

export interface QuoteCalculation {
  outputAmount: bigint;
  solverFee: bigint;
  solverTip: bigint;
  profitable: boolean;
  expectedProfit: bigint;
  exchangeRate: number;
}

export class MockPricing {
  constructor(private config: SolverConfig) {}

  calculateQuote(intent: Intent): QuoteCalculation | null {
    const intentId = intent.id.toString();

    // Get exchange rate for this pair
    const rateName = `${intent.source.token}_${intent.destination.token}`;
    const exchangeRate = this.config.exchangeRates.get(rateName);

    if (!exchangeRate) {
      logger.warn(`No exchange rate configured for ${rateName}`, { intentId });
      return null;
    }

    // Convert source amount to floating point for calculation
    const sourceAmountFloat = Number(intent.source_amount);
    if (sourceAmountFloat === 0) {
      logger.warn('Source amount is zero', { intentId });
      return null;
    }

    // Calculate raw output based on exchange rate
    const rawOutput = sourceAmountFloat * exchangeRate;

    // Add a small margin to beat minimum (2% above minimum)
    const marginMultiplier = 1.02;
    const minOutputFloat = Number(intent.min_output);
    const targetOutput = Math.max(rawOutput, minOutputFloat * marginMultiplier);

    // Calculate fees
    const outputAmount = BigInt(Math.floor(targetOutput));
    const solverFeeBps = BigInt(this.config.defaultSolverFeeBps);
    const solverTipBps = BigInt(this.config.defaultSolverTipBps);

    // Fee = outputAmount * bps / 10000
    const solverFee = (outputAmount * solverFeeBps) / 10000n;
    const solverTip = (outputAmount * solverTipBps) / 10000n;

    // Calculate expected profit
    // Profit = (outputAmount - solverFee - solverTip) - cost
    // Cost = sourceAmount converted to destination token
    const cost = BigInt(Math.floor(sourceAmountFloat * exchangeRate));
    const netOutput = outputAmount - solverFee - solverTip;
    const expectedProfit = netOutput - cost;

    // Check profitability against minimum
    const minProfitBps = BigInt(this.config.minProfitBps);
    const minProfit = (cost * minProfitBps) / 10000n;
    const profitable = expectedProfit >= minProfit;

    // Check if we can meet minimum output
    if (outputAmount < intent.min_output) {
      logger.debug(`Output ${outputAmount} below minimum ${intent.min_output}`, {
        intentId,
        exchangeRate,
      });
      return {
        outputAmount,
        solverFee,
        solverTip,
        profitable: false,
        expectedProfit,
        exchangeRate,
      };
    }

    logger.debug('Quote calculated', {
      intentId,
      sourceAmount: intent.source_amount.toString(),
      outputAmount: outputAmount.toString(),
      solverFee: solverFee.toString(),
      solverTip: solverTip.toString(),
      expectedProfit: expectedProfit.toString(),
      profitable,
      exchangeRate,
    });

    return {
      outputAmount,
      solverFee,
      solverTip,
      profitable,
      expectedProfit,
      exchangeRate,
    };
  }

  supportsTokenPair(sourceToken: string, destToken: string): boolean {
    const rateName = `${sourceToken}_${destToken}`;
    return this.config.exchangeRates.has(rateName);
  }

  listSupportedPairs(): string[] {
    return Array.from(this.config.exchangeRates.keys());
  }
}
