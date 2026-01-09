// Retry logic with exponential backoff for IC calls

import { logger } from './logger.js';

export interface RetryConfig {
  maxAttempts?: number;
  initialDelayMs?: number;
  maxDelayMs?: number;
  backoffMultiplier?: number;
}

const defaultConfig: Required<RetryConfig> = {
  maxAttempts: 3,
  initialDelayMs: 1000,
  maxDelayMs: 10000,
  backoffMultiplier: 2,
};

async function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isTransientError(error: any): boolean {
  const errorMessage = error?.message || String(error);

  // Common transient error patterns
  const transientPatterns = [
    'network',
    'timeout',
    'ECONNREFUSED',
    'ENOTFOUND',
    'ETIMEDOUT',
    'rate limit',
    '429',
    '503',
    '504',
  ];

  return transientPatterns.some((pattern) =>
    errorMessage.toLowerCase().includes(pattern.toLowerCase())
  );
}

export async function retryWithBackoff<T>(
  fn: () => Promise<T>,
  config: RetryConfig = {},
  context?: string
): Promise<T> {
  const cfg = { ...defaultConfig, ...config };
  let lastError: any;
  let delay = cfg.initialDelayMs;

  for (let attempt = 1; attempt <= cfg.maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;

      // Don't retry if this is the last attempt
      if (attempt === cfg.maxAttempts) {
        break;
      }

      // Only retry on transient errors
      if (!isTransientError(error)) {
        logger.debug(`Non-transient error, not retrying`, {
          context,
          attempt,
          error: String(error),
        });
        throw error;
      }

      logger.warn(`Attempt ${attempt}/${cfg.maxAttempts} failed, retrying in ${delay}ms`, {
        context,
        error: String(error),
      });

      await sleep(delay);

      // Exponential backoff with max cap
      delay = Math.min(delay * cfg.backoffMultiplier, cfg.maxDelayMs);
    }
  }

  logger.error(`All ${cfg.maxAttempts} attempts failed`, {
    context,
    error: String(lastError),
  });
  throw lastError;
}
