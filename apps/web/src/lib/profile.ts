/**
 * Read + write helpers for the account page's dietary preferences.
 *
 * Both go through the Next `/api/profile` proxy (not the direct `api`
 * helper), so the HttpOnly `bw_session` JWT is attached server-side
 * and never reaches JS — same path as `saveProfile` in `./onboarding`.
 *
 * `updateProfile` sends a PARTIAL patch: the Rails endpoint only
 * replaces the arrays present in the body, so changing strictness or
 * one avoid list never touches the others. Each array it DOES send is
 * replaced wholesale, so callers pass the full canonical array (built
 * from the current profile loaded via `fetchProfile`).
 */
import type { ProfilePayload } from '@biteworthy/api-types';
import type { Strictness } from '@biteworthy/filter-engine';

export type { ProfilePayload };

/** The fields the account page can patch. All optional; omit to leave untouched. */
export interface ProfilePatch {
  strictness?: Strictness;
  avoid_ingredient_ids?: string[];
  avoid_tag_ids?: string[];
  prefer_tag_ids?: string[];
  liked_ingredient_ids?: string[];
  liked_tag_ids?: string[];
  disliked_ingredient_ids?: string[];
  disliked_tag_ids?: string[];
  /** Additive — unions the preset's avoid lists onto the stored ones. */
  dietary_profile_slug?: string;
}

/** Raised on a 401 so callers can bounce to /login. */
export class NotSignedInError extends Error {
  constructor() {
    super('not signed in');
    this.name = 'NotSignedInError';
  }
}

async function readJsonOrThrow(res: Response, action: string): Promise<ProfilePayload> {
  if (res.status === 401) throw new NotSignedInError();
  if (!res.ok) {
    let body: unknown = null;
    try {
      body = await res.json();
    } catch {
      // ignore — non-JSON error body
    }
    throw new Error(`${action} failed: ${res.status} ${JSON.stringify(body)}`);
  }
  return (await res.json()) as ProfilePayload;
}

export async function fetchProfile(
  opts: { fetchImpl?: typeof fetch } = {},
): Promise<ProfilePayload> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl('/api/profile', {
    credentials: 'same-origin',
    headers: { Accept: 'application/json' },
  });
  return readJsonOrThrow(res, 'fetchProfile');
}

export async function updateProfile(
  patch: ProfilePatch,
  opts: { fetchImpl?: typeof fetch } = {},
): Promise<ProfilePayload> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl('/api/profile', {
    method: 'PATCH',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(patch),
  });
  return readJsonOrThrow(res, 'updateProfile');
}
