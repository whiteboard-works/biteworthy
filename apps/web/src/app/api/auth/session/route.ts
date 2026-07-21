/**
 * `GET /api/auth/session` — the one auth-state read the client can make
 * without touching the HttpOnly `bw_session` cookie itself.
 *
 * The site header (a client component) hits this to decide whether to
 * show "Sign in" or "Account / Log out". Keeping it a dedicated route
 * means the SSR/static pages don't have to read cookies in the root
 * layout, so the marketing + SEO pages stay statically rendered.
 *
 * Deliberately a purely-local cookie read (no upstream call): signed-in
 * state must resolve fast and stay independent of Rails health, so the
 * header never blanks out when the API is slow. The onboarding-status
 * signal, which DOES need the API, lives in the separate
 * `/api/auth/onboarded` route so it can't hold this one up.
 *
 * A static `session/` segment sits alongside the dynamic `[action]/`
 * proxy; Next resolves this exact path here (the proxy only handles
 * login/signup/logout POSTs).
 */
import { NextResponse } from 'next/server';
import { getServerUserId } from '../../../../lib/server-auth';

export async function GET() {
  const userId = await getServerUserId();
  return NextResponse.json(
    { signedIn: userId !== null },
    // Auth state is per-user and must never be cached by the browser or
    // any shared cache — otherwise a signed-out visitor could read a
    // signed-in response (or vice-versa).
    { headers: { 'Cache-Control': 'no-store' } },
  );
}
