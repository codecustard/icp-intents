// Main entry point for solver bot

import { loadConfig } from './config.js';
import { createAgent, createIntentPoolActor } from './agent.js';
import { IntentMonitor } from './monitor/IntentMonitor.js';
import { IntentFilter } from './monitor/IntentFilter.js';
import { MockPricing } from './pricing/MockPricing.js';
import { MockFulfillment } from './fulfillment/MockFulfillment.js';
import { logger, LogLevel } from './utils/logger.js';
import { retryWithBackoff } from './utils/retry.js';
import { Intent } from './types/intent-pool.js';

interface TrackedIntent {
  intent: Intent;
  lastChecked: number;
}

async function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
  logger.info('=== ICP Intents Solver Bot ===');
  logger.info('Educational demo - NOT for production use');

  // Load configuration
  const config = loadConfig();

  // Set log level (DEBUG for development, INFO for production)
  logger.setLevel(LogLevel.DEBUG);

  // Initialize IC agent
  const { agent, identity } = await createAgent(config);
  const intentPool = createIntentPoolActor(agent, config.intentPoolCanisterId);

  // Initialize components
  const monitor = new IntentMonitor(intentPool);
  const filter = new IntentFilter(config);
  const pricing = new MockPricing(config);
  const fulfillment = new MockFulfillment(config);

  // Get solver principal
  const solverPrincipal = identity.getPrincipal();
  logger.info('Solver bot initialized', {
    principal: solverPrincipal.toText(),
    supportedChains: Array.from(config.supportedChains),
    supportedTokens: Array.from(config.supportedTokens),
  });

  // Track active intents we've quoted on
  const activeIntents = new Map<string, TrackedIntent>();

  // Setup graceful shutdown
  let shutdownRequested = false;
  process.on('SIGINT', () => {
    logger.info('Shutdown requested (SIGINT)');
    shutdownRequested = true;
  });
  process.on('SIGTERM', () => {
    logger.info('Shutdown requested (SIGTERM)');
    shutdownRequested = true;
  });

  // Main monitoring loop
  logger.info('Starting monitoring loop', {
    pollingInterval: `${config.pollingIntervalMs}ms`,
  });

  let loopCount = 0;

  while (!shutdownRequested) {
    loopCount++;
    const loopStart = Date.now();

    try {
      logger.debug(`=== Loop ${loopCount} ===`);

      // TODO: In a real implementation, you'd have a dedicated API endpoint
      // to get all intents in PendingQuote/Quoted status
      // For now, we'll demonstrate by manually tracking intent IDs
      // Users would call this bot with specific intent IDs, or we'd
      // periodically scan a range of intent IDs

      // For demo: Check a range of recent intent IDs (0-100)
      const intentIdsToCheck = Array.from({ length: 100 }, (_, i) => BigInt(i));

      for (const intentId of intentIdsToCheck) {
        // Skip if we've seen this before
        if (monitor.hasSeen(intentId)) {
          continue;
        }

        // Get intent details
        const intent = await monitor.getIntent(intentId);
        if (!intent) {
          monitor.markAsSeen(intentId);
          continue;
        }

        // Check if we can handle this intent
        if (!filter.canHandle(intent)) {
          continue;
        }

        // Calculate quote
        const quote = pricing.calculateQuote(intent);
        if (!quote || !quote.profitable) {
          logger.info(`Intent ${intentId} not profitable, skipping`, {
            profitable: quote?.profitable,
            expectedProfit: quote?.expectedProfit.toString(),
          });
          continue;
        }

        // Submit quote
        try {
          logger.info(`Submitting quote for intent ${intentId}`, {
            outputAmount: quote.outputAmount.toString(),
            solverFee: quote.solverFee.toString(),
            solverTip: quote.solverTip.toString(),
          });

          const result = await retryWithBackoff(
            () =>
              intentPool.submitQuote(
                intentId,
                quote.outputAmount,
                quote.solverFee,
                quote.solverTip
              ),
            {},
            `submitQuote(${intentId})`
          );

          if ('ok' in result) {
            logger.success(`Quote submitted for intent ${intentId}`);
            activeIntents.set(intentId.toString(), {
              intent,
              lastChecked: Date.now(),
            });
          } else {
            logger.warn(`Quote submission failed for intent ${intentId}`, {
              error: JSON.stringify(result.err),
            });
          }
        } catch (error) {
          logger.error(`Failed to submit quote for intent ${intentId}`, {
            error: String(error),
          });
        }
      }

      // Check active intents for fulfillment
      for (const [intentIdStr, tracked] of activeIntents.entries()) {
        const intentId = BigInt(intentIdStr);

        // Refetch current state
        const currentIntent = await monitor.getIntent(intentId);
        if (!currentIntent) {
          logger.warn(`Intent ${intentId} no longer exists`);
          activeIntents.delete(intentIdStr);
          continue;
        }

        // Check if deposited and we're the selected solver
        if (filter.isDeposited(currentIntent)) {
          const selectedQuote = currentIntent.selected_quote;
          if (selectedQuote.length > 0) {
            const quote = selectedQuote[0];
            if (!quote) continue; // Type guard

            if (quote.solver.toText() === solverPrincipal.toText()) {
              logger.info(`Intent ${intentId} deposited, fulfilling...`);

              // Fulfill the intent
              const fulfillmentResult = await fulfillment.fulfill(
                currentIntent,
                quote
              );

            if (fulfillmentResult.success) {
              // Call fulfillIntent on canister
              try {
                const result = await retryWithBackoff(
                  () => intentPool.fulfillIntent(intentId),
                  {},
                  `fulfillIntent(${intentId})`
                );

                if ('ok' in result) {
                  logger.success(`Intent ${intentId} fulfilled successfully`, {
                    txHash: fulfillmentResult.txHash,
                    feeBreakdown: JSON.stringify(result.ok),
                  });
                  activeIntents.delete(intentIdStr);
                } else {
                  logger.error(`Fulfillment call failed for intent ${intentId}`, {
                    error: JSON.stringify(result.err),
                  });
                }
              } catch (error) {
                logger.error(`Failed to call fulfillIntent for ${intentId}`, {
                  error: String(error),
                });
              }
            } else {
              logger.error(`Mock fulfillment failed for intent ${intentId}`, {
                error: fulfillmentResult.error,
              });
            }
            }
          }
        }

        // Remove if fulfilled or cancelled
        if (filter.isFulfilledOrCancelled(currentIntent)) {
          logger.debug(`Intent ${intentId} terminal, removing from tracking`);
          activeIntents.delete(intentIdStr);
        }
      }

      // Log loop summary
      const loopDuration = Date.now() - loopStart;
      logger.debug(`Loop ${loopCount} completed`, {
        duration: `${loopDuration}ms`,
        activeIntents: activeIntents.size,
      });

    } catch (error) {
      logger.error('Error in main loop', { error: String(error) });
    }

    // Wait before next poll
    await sleep(config.pollingIntervalMs);
  }

  logger.info('Solver bot shutting down');
  logger.info(`Total loops executed: ${loopCount}`);
  logger.info(`Active intents at shutdown: ${activeIntents.size}`);
}

// Run main and handle errors
main().catch((error) => {
  logger.error('Fatal error in main', { error: String(error) });
  process.exit(1);
});
