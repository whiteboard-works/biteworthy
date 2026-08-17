/**
 * Read + write helpers for the caller's own account identity.
 *
 * Both go through the Next `/api/me` proxy (HttpOnly `bw_session` JWT
 * attached server-side), same as `./profile`. PATCH edits are
 * field-level: a 422 comes back as `{ errors: { handle: [...] } }`, and
 * `updateMyHandle` rethrows it as `HandleValidationError` so the form
 * can render "already taken" inline instead of a generic failure.
 */
import type { UserPayload } from '@biteworthy/api-types';
import { NotSignedInError } from './profile';

export class HandleValidationError extends Error {
  constructor(public readonly messages: string[]) {
    super(messages.join(', ') || 'invalid handle');
    this.name = 'HandleValidationError';
  }
}

export async function fetchMe(opts: { fetchImpl?: typeof fetch } = {}): Promise<UserPayload> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl('/api/me', {
    credentials: 'same-origin',
    headers: { Accept: 'application/json' },
  });
  if (res.status === 401) throw new NotSignedInError();
  if (!res.ok) throw new Error(`fetchMe failed: ${res.status}`);
  const body = (await res.json()) as { user: UserPayload };
  return body.user;
}

export async function updateMyHandle(
  handle: string,
  opts: { fetchImpl?: typeof fetch } = {},
): Promise<UserPayload> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl('/api/me', {
    method: 'PATCH',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({ handle }),
  });
  if (res.status === 401) throw new NotSignedInError();
  if (res.status === 422) {
    const body = (await res.json().catch(() => null)) as {
      errors?: Record<string, string[]>;
    } | null;
    throw new HandleValidationError(body?.errors?.handle ?? []);
  }
  if (!res.ok) throw new Error(`updateMyHandle failed: ${res.status}`);
  const body = (await res.json()) as { user: UserPayload };
  return body.user;
}
