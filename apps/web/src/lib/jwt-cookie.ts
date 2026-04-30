/**
 * Phase 3.8 — temporary JWT cookie store.
 *
 * Phase 4 will land proper session cookies (HttpOnly, Secure, SameSite,
 * server-managed). For now the onboarding flow stores the JWT in a
 * client-side cookie so the next request to a profile-aware endpoint
 * (e.g. `/restaurants/[slug]?with_jwt=true`) can read it back.
 *
 * This is intentionally NOT secure for production — the cookie has
 * no HttpOnly flag and is JS-readable. The same plaintext-input
 * workaround the ingest/restaurant screens use today.
 */

const COOKIE_NAME = 'bw_jwt';
const ONE_WEEK = 60 * 60 * 24 * 7;

export function setJwtCookie(jwt: string): void {
  if (typeof document === 'undefined') return;
  const secure = window.location.protocol === 'https:' ? '; Secure' : '';
  document.cookie = `${COOKIE_NAME}=${encodeURIComponent(jwt)}; Path=/; Max-Age=${ONE_WEEK}; SameSite=Lax${secure}`;
}

export function getJwtCookie(): string | null {
  if (typeof document === 'undefined') return null;
  for (const part of document.cookie.split('; ')) {
    const [k, ...vparts] = part.split('=');
    if (k === COOKIE_NAME) {
      const v = vparts.join('=');
      try {
        return decodeURIComponent(v);
      } catch {
        return null;
      }
    }
  }
  return null;
}

export function clearJwtCookie(): void {
  if (typeof document === 'undefined') return;
  document.cookie = `${COOKIE_NAME}=; Path=/; Max-Age=0; SameSite=Lax`;
}
