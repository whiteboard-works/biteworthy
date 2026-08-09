/**
 * OAuth grants — the apps someone connected by walking the consent flow,
 * and the one way to disconnect one.
 *
 * Distinct from `mcp-tokens`, which are credentials this person minted
 * for themselves. A connection is something an outside client asked for
 * and they approved, so the list has to name the client and read back the
 * same sentences the consent screen showed.
 */
import { NotSignedInError } from './chat';

export interface ScopeDetail {
  scope: string;
  description: string;
}

export interface ConnectedApp {
  id: string;
  name: string;
  scopes: string[];
  scope_details: ScopeDetail[];
  connected_at: string | null;
  last_renewed_at: string | null;
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

export async function listConnectedApps(): Promise<ConnectedApp[]> {
  const body = await call<{ apps: ConnectedApp[] }>('/api/connected-apps', { cache: 'no-store' });
  return body.apps;
}

export function disconnectApp(id: string): Promise<void> {
  return call(`/api/connected-apps/${encodeURIComponent(id)}`, { method: 'DELETE' });
}
