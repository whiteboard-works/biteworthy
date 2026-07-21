/**
 * `GET /api/auth/session` — the one auth-state read the client can make
 * without touching the HttpOnly `bw_session` cookie itself.
 *
 * The site header (a client component) hits this to decide whether to
 * show "Sign in" or "Account / Log out". Keeping it a dedicated route
 * means the SSR/static pages don't have to read cookies in the root
 * layout, so the marketing + SEO pages stay statically rendered.
 *
 * It also reports `onboarded` — whether the signed-in user has finished
 * the dietary-profile onboarding — so the header can nudge users who
 * signed up but skipped setup. The signal is the profile's
 * `disclaimer_acknowledged_at` (stamped on the final onboarding save;
 * null for a brand-new account). We read it from `GET /api/v1/profile`
 * rather than the JWT, which doesn't carry it.
 *
 * A static `session/` segment sits alongside the dynamic `[action]/`
 * proxy; Next resolves this exact path here (the proxy only handles
 * login/signup/logout POSTs).
 */
import { NextResponse } from 'next/server';
import { getServerJwt, getServerUserId } from '../../../../lib/server-auth';
import { API_BASE } from '../../../../lib/api-base';

export async function GET() {
  const userId = await getServerUserId();
  if (userId === null) {
    return json({ signedIn: false, onboarded: false });
  }
  return json({ signedIn: true, onboarded: await hasOnboarded() });
}

/**
 * Whether the signed-in user has completed onboarding. `true` on any
 * lookup failure — we fail safe so a transient API hiccup never nags an
 * already-set-up user to "finish" a profile they already have.
 */
async function hasOnboarded(): Promise<boolean> {
  const jwt = await getServerJwt();
  if (!jwt) return true;
  try {
    const res = await fetch(`${API_BASE}/api/v1/profile`, {
      headers: { Authorization: `Bearer ${jwt}`, Accept: 'application/json' },
      cache: 'no-store',
    });
    if (!res.ok) return true;
    const body = (await res.json()) as { disclaimer_acknowledged_at?: string | null };
    return Boolean(body.disclaimer_acknowledged_at);
  } catch {
    return true;
  }
}

function json(payload: { signedIn: boolean; onboarded: boolean }) {
  return NextResponse.json(payload, {
    // Auth state is per-user and must never be cached by the browser or
    // any shared cache — otherwise a signed-out visitor could read a
    // signed-in response (or vice-versa).
    headers: { 'Cache-Control': 'no-store' },
  });
}
