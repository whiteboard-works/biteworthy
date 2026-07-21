/**
 * `GET /api/auth/onboarded` → `{ onboarded }` — whether the signed-in
 * user has finished the dietary-profile onboarding.
 *
 * The signal is the profile's `disclaimer_acknowledged_at` (stamped on
 * the final onboarding save; null for a brand-new account), read from
 * Rails `GET /api/v1/profile`. It lives in its own route — NOT folded
 * into `/api/auth/session` — so the header's signed-in/out state stays a
 * fast local cookie read that never blocks on Rails. Only this
 * nudge-only value depends on the API, and it fails safe to `true`
 * (never nag) whenever we can't tell: signed out, non-200, or a fetch
 * error.
 */
import { NextResponse } from 'next/server';
import { getServerJwt } from '../../../../lib/server-auth';
import { API_BASE } from '../../../../lib/api-base';

export async function GET() {
  return NextResponse.json(
    { onboarded: await hasOnboarded() },
    { headers: { 'Cache-Control': 'no-store' } },
  );
}

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
