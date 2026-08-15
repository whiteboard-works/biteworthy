/**
 * Thin fetch wrapper for the BiteWorthy Rails API.
 * Real auth header injection lands with the JWT login flow in Phase 1.
 *
 * `fetchImpl` is optional and only set by tests — production code
 * uses the global fetch.
 */

import { API_BASE } from './api-base';

export interface ApiOptions extends RequestInit {
  fetchImpl?: typeof fetch;
}

/** Non-2xx from Rails. `status` is the contract — never parse the message. */
export class ApiError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }
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
  if (!res.ok) throw new ApiError(res.status, `${res.status} ${res.statusText}`);
  return (await res.json()) as T;
}
