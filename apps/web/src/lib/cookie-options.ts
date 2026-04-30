/**
 * Phase 5.4 — auth-cookie attribute composition.
 *
 * Centralizes the `cookies.set()` options used by the auth proxy
 * route at `app/api/auth/[action]/route.ts`. Pulls `domain` from
 * `NEXT_PUBLIC_COOKIE_DOMAIN` so production can scope the cookie
 * across subdomains (`.bite-worthy.com` → works for `www`, `app`,
 * etc.) while dev / CI leave it unset (localhost cookies must NOT
 * carry a domain attribute or the browser silently drops them).
 *
 * Pure function so the route handler stays a thin adapter and
 * vitest can cover the env-driven branches without touching Next.
 */

export interface AuthCookieOptions {
  name: string;
  value: string;
  httpOnly: true;
  secure: boolean;
  sameSite: 'lax';
  path: '/';
  maxAge: number;
  domain?: string;
}

const DEFAULT_MAX_AGE = 60 * 60 * 24 * 30; // 30 days

interface BuildOptions {
  /** Override the env-driven `NEXT_PUBLIC_COOKIE_DOMAIN` (test-only). */
  domain?: string | null;
  /** Override `NODE_ENV === 'production'` (test-only). */
  production?: boolean;
}

export function buildAuthCookieOptions(
  name: string,
  value: string,
  maxAge: number = DEFAULT_MAX_AGE,
  overrides: BuildOptions = {},
): AuthCookieOptions {
  const domain =
    overrides.domain !== undefined
      ? (overrides.domain ?? undefined)
      : process.env.NEXT_PUBLIC_COOKIE_DOMAIN || undefined;

  const production =
    overrides.production !== undefined
      ? overrides.production
      : process.env.NODE_ENV === 'production';

  const opts: AuthCookieOptions = {
    name,
    value,
    httpOnly: true,
    secure: production,
    sameSite: 'lax',
    path: '/',
    maxAge,
  };
  if (domain) {
    opts.domain = domain;
  }
  return opts;
}
