/**
 * OAuth grants — the apps someone connected by walking the consent flow,
 * and the one way to disconnect one.
 *
 * Distinct from `mcp-tokens`, which are credentials this person minted
 * for themselves. A connection is something an outside client asked for
 * and they approved, so the list has to name the client and read back the
 * same sentences the consent screen showed.
 */
import { authedFetch } from './authed-fetch';

export interface ScopeDetail {
  scope: string;
  description: string;
}

export interface ConnectedApp {
  id: string;
  name: string;
  /**
   * Where the client registered to be sent back to. Registration is
   * unauthenticated, so the name is a claim and this is what makes two
   * apps claiming it apart — the same thing the consent screen shows.
   */
  redirect_host: string | null;
  scopes: string[];
  scope_details: ScopeDetail[];
  connected_at: string | null;
  last_renewed_at: string | null;
}

export async function listConnectedApps(): Promise<ConnectedApp[]> {
  const body = await authedFetch<{ apps: ConnectedApp[] }>('/api/connected-apps', {
    cache: 'no-store',
  });
  return body.apps;
}

export function disconnectApp(id: string): Promise<void> {
  return authedFetch(`/api/connected-apps/${encodeURIComponent(id)}`, { method: 'DELETE' });
}
