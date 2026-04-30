/**
 * Thin fetch wrapper for the BiteWorthy Rails API.
 * Real auth header injection lands with the JWT login flow in Phase 1.
 *
 * `fetchImpl` is optional and only set by tests — production code
 * uses the global fetch.
 */

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? 'http://localhost:3000';

export interface ApiOptions extends RequestInit {
  fetchImpl?: typeof fetch;
}

export async function api<T>(path: string, options: ApiOptions = {}): Promise<T> {
  const { fetchImpl = fetch, ...init } = options;
  const res = await fetchImpl(`${API_BASE}/api/v1${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      ...(init.headers ?? {}),
    },
  });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return (await res.json()) as T;
}
