/**
 * Least-privilege credentials for MCP clients.
 *
 * A Devise JWT carries everything the account can do; one of these names
 * what it may touch. The secret is returned **once**, by `createToken` —
 * only its digest is stored, so nothing can show it again.
 */
import { authedFetch } from './authed-fetch';

export interface McpTokenSummary {
  id: string;
  name: string;
  scopes: string[];
  created_at: string;
  last_used_at: string | null;
}

/** Only ever returned by `createToken`, and only that once. */
export interface McpTokenWithSecret extends McpTokenSummary {
  secret: string;
}

export interface McpTokenList {
  tokens: McpTokenSummary[];
  /** Every grantable scope, so the UI need not hardcode the vocabulary. */
  scopes: string[];
}

export function listTokens(): Promise<McpTokenList> {
  return authedFetch('/api/mcp-tokens', { cache: 'no-store' });
}

export function createToken(name: string, scopes: string[]): Promise<McpTokenWithSecret> {
  return authedFetch('/api/mcp-tokens', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, scopes }),
  });
}

export function revokeToken(id: string): Promise<void> {
  return authedFetch(`/api/mcp-tokens/${encodeURIComponent(id)}`, { method: 'DELETE' });
}
