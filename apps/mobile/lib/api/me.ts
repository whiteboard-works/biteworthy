/**
 * The caller's own account — read + handle edit. Mirrors
 * apps/web/src/lib/me.ts against the same GET/PATCH /api/v1/me pair.
 *
 * A 422 comes back per-field ({ errors: { handle: [...] } }); it is
 * rethrown as MeValidationError so the account screen can render
 * "already taken" inline instead of a generic failure.
 */
import type { UserPayload } from '@biteworthy/api-types';
import { API_BASE } from '../api-base';

export class MeError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'MeError';
  }
}

export class MeValidationError extends Error {
  constructor(public readonly messages: string[]) {
    super(messages.join(', ') || 'invalid value');
    this.name = 'MeValidationError';
  }
}

export interface FetchOptions {
  fetchImpl?: typeof fetch;
}

export async function fetchMe(jwt: string, opts: FetchOptions = {}): Promise<UserPayload> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`${API_BASE}/api/v1/me`, {
    headers: { Authorization: `Bearer ${jwt}` },
  });
  if (!res.ok) throw new MeError(res.status, `fetchMe failed: ${res.status}`);
  const body = (await res.json()) as { user: UserPayload };
  return body.user;
}

export async function updateMyHandle(
  handle: string,
  jwt: string,
  opts: FetchOptions = {},
): Promise<UserPayload> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`${API_BASE}/api/v1/me`, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${jwt}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ handle }),
  });
  if (res.status === 422) {
    let body: { errors?: Record<string, string[]> } | null = null;
    try {
      body = (await res.json()) as { errors?: Record<string, string[]> };
    } catch {
      // non-JSON body — fall through to the empty-messages error
    }
    throw new MeValidationError(body?.errors?.handle ?? []);
  }
  if (!res.ok) throw new MeError(res.status, `updateMyHandle failed: ${res.status}`);
  const body = (await res.json()) as { user: UserPayload };
  return body.user;
}
