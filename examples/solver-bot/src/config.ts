// Configuration loader from environment variables

import { config as dotenvConfig } from 'dotenv';
import { logger } from './utils/logger.js';

// Load .env file if it exists
dotenvConfig();

export interface SolverConfig {
  // IC Network
  icNetwork: 'local' | 'ic';
  intentPoolCanisterId: string;
  solverIdentityPath: string;

  // Monitoring
  pollingIntervalMs: number;

  // Profitability
  minProfitBps: number;

  // Exchange rates (demo - fixed rates)
  exchangeRates: Map<string, number>;

  // Supported assets
  supportedChains: Set<string>;
  supportedTokens: Set<string>;

  // Solver fees
  defaultSolverFeeBps: number;
  defaultSolverTipBps: number;
}

function getEnvVar(name: string, defaultValue?: string): string {
  const value = process.env[name] || defaultValue;
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function parseIntEnv(name: string, defaultValue: number): number {
  const value = process.env[name];
  if (!value) return defaultValue;
  const parsed = parseInt(value, 10);
  if (isNaN(parsed)) {
    throw new Error(`Invalid integer value for ${name}: ${value}`);
  }
  return parsed;
}

function parseExchangeRates(): Map<string, number> {
  const rates = new Map<string, number>();

  // Parse all RATE_* environment variables
  for (const [key, value] of Object.entries(process.env)) {
    if (key.startsWith('RATE_')) {
      const pairName = key.substring(5); // Remove 'RATE_' prefix
      const rate = parseFloat(value || '0');
      if (isNaN(rate) || rate <= 0) {
        throw new Error(`Invalid exchange rate for ${key}: ${value}`);
      }
      rates.set(pairName, rate);
    }
  }

  if (rates.size === 0) {
    logger.warn('No exchange rates configured, using defaults');
    // Default rates from .env.example
    rates.set('ETH_HOO', 50000);
    rates.set('ICP_ETH', 0.002);
    rates.set('ICP_HOO', 100);
    rates.set('HOO_ETH', 0.00002);
  }

  return rates;
}

function parseSetEnv(name: string, defaultValue: string): Set<string> {
  const value = process.env[name] || defaultValue;
  return new Set(
    value
      .split(',')
      .map((s) => s.trim())
      .filter((s) => s.length > 0)
  );
}

export function loadConfig(): SolverConfig {
  logger.info('Loading configuration from environment');

  // Get identity path (will be auto-generated if it doesn't exist)
  const identityPath = getEnvVar('SOLVER_IDENTITY_PATH', './identity.json');

  const config: SolverConfig = {
    icNetwork: (getEnvVar('IC_NETWORK', 'local') as 'local' | 'ic'),
    intentPoolCanisterId: getEnvVar('INTENT_POOL_CANISTER_ID'),
    solverIdentityPath: identityPath,
    pollingIntervalMs: parseIntEnv('POLLING_INTERVAL_MS', 5000),
    minProfitBps: parseIntEnv('MIN_PROFIT_BPS', 50),
    exchangeRates: parseExchangeRates(),
    supportedChains: parseSetEnv('SUPPORTED_CHAINS', 'ethereum,sepolia,hoosat,icp'),
    supportedTokens: parseSetEnv('SUPPORTED_TOKENS', 'ETH,ICP,HOO,USDC'),
    defaultSolverFeeBps: parseIntEnv('DEFAULT_SOLVER_FEE_BPS', 30),
    defaultSolverTipBps: parseIntEnv('DEFAULT_SOLVER_TIP_BPS', 10),
  };

  logger.info('Configuration loaded', {
    network: config.icNetwork,
    canisterId: config.intentPoolCanisterId,
    supportedChains: Array.from(config.supportedChains).join(','),
    supportedTokens: Array.from(config.supportedTokens).join(','),
    exchangeRates: config.exchangeRates.size,
  });

  return config;
}
