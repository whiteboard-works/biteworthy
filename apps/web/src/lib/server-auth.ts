/**
 * Phase 4.1 — server-side helpers for reading the auth cookie in
 * Next route handlers + SSR pages.
 *
 * `getServerJwt()` reads the HttpOnly `bw_session` cookie set by the
 * `/api/auth/*` routes. Pass the returned token straight into
 * `fetchRestaurantItems({ jwt })` etc. and the Rails endpoint applies
 * `current_user.profile` automatically (Phase 1.7 contract).
 *
 * The cookie name is centralized here so callers don't have to spell
 * it (and the dev shortcut + legacy `bw_jwt` reader stays in
 * `jwt-cookie.ts` for the client-side path).
 */
import { cookies } from 'next/headers';

export const SESSION_COOKIE = 'bw_session';

/** Async because next/headers' `cookies()` is a thenable in Next 15. */
export async function getServerJwt(): Promise<string | null> {
  const jar = await cookies();
  const value = jar.get(SESSION_COOKIE)?.value;
  return value && value.length > 0 ? value : null;
}
