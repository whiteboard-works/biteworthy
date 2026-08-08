/**
 * Least-privilege credentials for MCP clients.
 *
 * A Devise JWT carries everything the account can do; one of these names
 * what it may touch. The secret is returned **once**, by `createToken` —
 * only its digest is stored, so nothing can show it again.
 */
import { NotSignedInError } from './chat';

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

async function call<T>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(path, { credentials: 'same-origin', ...init });
  if (res.status === 401) throw new NotSignedInError();
  if (!res.ok) {
    let message = `Request failed (${res.status})`;
    try {
      const body = (await res.json()) as { error?: string };
      if (body.error) message = body.error;
    } catch {
      // Non-JSON error bodies fall through to the status line.
    }
    throw new Error(message);
  }
  return res.status === 204 ? (undefined as T) : ((await res.json()) as T);
}

export function listTokens(): Promise<McpTokenList> {
  return call('/api/mcp-tokens', { cache: 'no-store' });
}

export function createToken(name: string, scopes: string[]): Promise<McpTokenWithSecret> {
  return call('/api/mcp-tokens', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, scopes }),
  });
}

export function revokeToken(id: string): Promise<void> {
  return call(`/api/mcp-tokens/${encodeURIComponent(id)}`, { method: 'DELETE' });
}
