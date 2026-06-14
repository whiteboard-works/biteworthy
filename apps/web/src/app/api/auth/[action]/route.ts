/**
 * Phase 4.1 — auth proxy.
 *
 * `POST /api/auth/{login,signup,logout}` proxies to the Rails
 * `/api/v1/auth/{login,signup,logout}` endpoint, extracts the JWT
 * from the upstream `Authorization` response header on success, and
 * sets/clears the HttpOnly `bw_session` cookie. The browser never
 * touches the JWT directly — only Rails (over the cookie-forwarded
 * Bearer header) does.
 *
 * The Rails contract is unchanged: it still expects
 * `{ user: { email, password } }` body shape on login/signup and a
 * Bearer header on logout.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { SESSION_COOKIE } from '../../../../lib/server-auth';
import { getServerJwt } from '../../../../lib/server-auth';
import { buildAuthCookieOptions } from '../../../../lib/cookie-options';

import { API_BASE } from '../../../../lib/api-base';
const COOKIE_MAX_AGE = 60 * 60 * 24 * 30; // 30 days

const ACTIONS = new Set(['login', 'signup', 'logout']);

interface CredentialsBody {
  email?: string;
  password?: string;
  // Legal remediation E4 — present on signup only; the 13+ affirmation.
  age_confirmation?: boolean;
}

export async function POST(
  request: NextRequest,
  context: { params: Promise<{ action: string }> },
) {
  const { action } = await context.params;
  if (!ACTIONS.has(action)) {
    return NextResponse.json({ error: 'Unknown auth action' }, { status: 404 });
  }

  if (action === 'logout') {
    return await handleLogout();
  }

  const body = (await request.json().catch(() => ({}))) as CredentialsBody;
  return await handleLoginOrSignup(action, body);
}

async function handleLoginOrSignup(action: string, body: CredentialsBody) {
  if (!body.email || !body.password) {
    return NextResponse.json({ error: 'Email and password required' }, { status: 400 });
  }

  const path = action === 'login' ? '/api/v1/auth/login' : '/api/v1/auth/signup';
  // Forward the 13+ affirmation on signup only (login ignores it).
  const user =
    action === 'signup'
      ? { email: body.email, password: body.password, age_confirmation: body.age_confirmation }
      : { email: body.email, password: body.password };
  const upstream = await fetch(`${API_BASE}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({ user }),
  });

  if (!upstream.ok) {
    const detail = await upstream.text().catch(() => '');
    return NextResponse.json(
      { error: `Auth failed: ${upstream.status}`, upstream: detail },
      { status: upstream.status },
    );
  }

  const token = extractBearer(upstream.headers.get('Authorization'));
  if (!token) {
    return NextResponse.json(
      { error: 'Auth response missing Authorization header' },
      { status: 502 },
    );
  }

  const userPayload = await upstream.json().catch(() => ({}));
  const response = NextResponse.json(userPayload, { status: 200 });
  response.cookies.set(buildAuthCookieOptions(SESSION_COOKIE, token, COOKIE_MAX_AGE));
  return response;
}

async function handleLogout() {
  const token = await getServerJwt();
  if (token) {
    // Best-effort: rotate the user's jti on the API side. We
    // continue even if this fails — the local cookie's gone either
    // way and an attacker without it can't replay.
    await fetch(`${API_BASE}/api/v1/auth/logout`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
    }).catch(() => {});
  }
  const response = NextResponse.json({ ok: true }, { status: 200 });
  response.cookies.set(buildAuthCookieOptions(SESSION_COOKIE, '', 0));
  return response;
}

function extractBearer(header: string | null): string | null {
  if (!header) return null;
  const match = /^Bearer\s+(.+)$/i.exec(header);
  return match ? match[1]!.trim() : null;
}
