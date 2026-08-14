/**
 * Phase 4.1 — server-side helpers for reading the auth cookie in
 * Next route handlers + SSR pages.
 *
 * `getServerJwt()` reads the HttpOnly `bw_session` cookie set by the
 * `/api/auth/*` routes. Pass the returned token straight into
 * `fetchRestaurantItems({ jwt })` etc. and the Rails endpoint applies
 * `current_user.profile` automatically (Phase 1.7 contract).
 *
 * The cookie name is centralized here so callers don't have to spell it.
 * `bw_session` is now the web app's only auth cookie — the Phase 3.8
 * `bw_jwt` reader in `jwt-cookie.ts` was JS-readable by design, said so
 * in its own header, and was deleted once nothing imported it.
 */
import { cookies } from 'next/headers';

export const SESSION_COOKIE = 'bw_session';

/** Async because next/headers' `cookies()` is a thenable in Next 15. */
export async function getServerJwt(): Promise<string | null> {
  const jar = await cookies();
  const value = jar.get(SESSION_COOKIE)?.value;
  return value && value.length > 0 ? value : null;
}

/**
 * The signed-in user's id, read from the JWT's `sub` claim (devise-jwt
 * puts the user id there). Used only to decide which UI to show — e.g.
 * the owner-only edit/delete controls on a review (E11). We do NOT
 * verify the signature here: the server still gates every mutation by
 * ownership (403), so a forged id only changes which buttons render,
 * never what the API allows. Returns null when signed out or malformed.
 */
export async function getServerUserId(): Promise<string | null> {
  const jwt = await getServerJwt();
  if (!jwt) return null;
  const payload = jwt.split('.')[1];
  if (!payload) return null;
  try {
    const json = Buffer.from(payload.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString(
      'utf8',
    );
    const sub = (JSON.parse(json) as { sub?: unknown }).sub;
    return typeof sub === 'string' && sub.length > 0 ? sub : null;
  } catch {
    return null;
  }
}
