// IC Agent setup and actor creation

import { HttpAgent, Actor, Identity } from '@dfinity/agent';
import { Ed25519KeyIdentity } from '@dfinity/identity';
import { readFileSync, writeFileSync, existsSync } from 'fs';
import { SolverConfig } from './config.js';
import { logger } from './utils/logger.js';
import { IntentPoolActor } from './types/intent-pool.js';
import { idlFactory } from './idl/intent-pool.idl.js';

export function loadIdentity(identityPath: string): Ed25519KeyIdentity {
  try {
    // Check if identity file exists
    if (!existsSync(identityPath)) {
      // Generate a new identity and save it
      logger.info('No identity file found, generating new identity', { path: identityPath });
      const identity = Ed25519KeyIdentity.generate();
      const json = JSON.stringify(identity.toJSON());
      writeFileSync(identityPath, json, 'utf-8');
      logger.info('New identity generated and saved', { path: identityPath });
      return identity;
    }

    // Load existing identity from JSON
    const jsonContent = readFileSync(identityPath, 'utf-8');
    const jsonIdentity = JSON.parse(jsonContent);
    return Ed25519KeyIdentity.fromJSON(JSON.stringify(jsonIdentity));
  } catch (error) {
    throw new Error(`Failed to load identity from ${identityPath}: ${error}`);
  }
}

export interface AgentWithIdentity {
  agent: HttpAgent;
  identity: Identity;
}

export async function createAgent(config: SolverConfig): Promise<AgentWithIdentity> {
  const identity = loadIdentity(config.solverIdentityPath);

  const host =
    config.icNetwork === 'local'
      ? 'http://127.0.0.1:4943'
      : 'https://ic0.app';

  logger.info('Creating IC agent', {
    network: config.icNetwork,
    host,
    principal: identity.getPrincipal().toText(),
  });

  const agent = new HttpAgent({
    host,
    identity,
  });

  // Fetch root key for local development (not needed for mainnet)
  if (config.icNetwork === 'local') {
    try {
      await agent.fetchRootKey();
      logger.debug('Fetched root key for local network');
    } catch (error) {
      logger.warn('Failed to fetch root key', { error: String(error) });
    }
  }

  return { agent, identity };
}

export function createIntentPoolActor(
  agent: HttpAgent,
  canisterId: string
): IntentPoolActor {
  logger.info('Creating IntentPool actor', { canisterId });

  return Actor.createActor<IntentPoolActor>(idlFactory, {
    agent,
    canisterId,
  }) as IntentPoolActor;
}
