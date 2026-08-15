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

const ACTIONS = new Set(['login', 'signup', 'logout', 'forgot', 'reset']);

interface CredentialsBody {
  email?: string;
  password?: string;
  // Legal remediation E4 — present on signup only; the 13+ affirmation.
  age_confirmation?: boolean;
  // Clickwrap — present on signup only; agreement to Terms + Privacy.
  terms_acceptance?: boolean;
  // Password reset only.
  reset_password_token?: string;
  password_confirmation?: string;
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
  if (action === 'forgot' || action === 'reset') {
    return await handlePasswordReset(action, body);
  }
  return await handleLoginOrSignup(action, body);
}

/**
 * forgot → POST /api/v1/auth/password (202 whether or not the email has
 * an account — no enumeration). reset → PUT with the emailed token.
 * Neither touches the session cookie: the user signs in afterwards.
 */
async function handlePasswordReset(action: 'forgot' | 'reset', body: CredentialsBody) {
  if (action === 'forgot' && !body.email) {
    return NextResponse.json({ error: 'Email required' }, { status: 400 });
  }
  if (action === 'reset') {
    if (!body.reset_password_token || !body.password || !body.password_confirmation) {
      return NextResponse.json(
        { error: 'Token, new password, and confirmation required' },
        { status: 400 },
      );
    }
    if (body.password !== body.password_confirmation) {
      return NextResponse.json({ error: 'Passwords do not match' }, { status: 422 });
    }
  }
  const user =
    action === 'forgot'
      ? { email: body.email }
      : {
          reset_password_token: body.reset_password_token,
          password: body.password,
          password_confirmation: body.password_confirmation,
        };

  const upstream = await fetch(`${API_BASE}/api/v1/auth/password`, {
    method: action === 'forgot' ? 'POST' : 'PUT',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({ user }),
  });

  // The forgot endpoint is documented to always succeed — relaying an
  // upstream 429/500 would only be visible for addresses that reached the
  // mail step, i.e. real accounts. Clamp it: defence-in-depth for the
  // enumeration guard (the failure still shows in server logs).
  if (action === 'forgot') {
    if (!upstream.ok) console.error(`forgot-password upstream ${upstream.status}`);
    return new NextResponse('{}', {
      status: 202,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const text = await upstream.text();
  if (!upstream.ok) {
    return NextResponse.json(
      { error: flattenResetError(text, upstream.status) },
      { status: upstream.status },
    );
  }
  return new NextResponse(text || '{}', {
    status: upstream.status,
    headers: { 'Content-Type': 'application/json' },
  });
}

/**
 * Rails 422s with the field-keyed Devise envelope
 * ({ errors: { password: ["is too short…"] } }); the client's AuthError
 * carries one string. "field message" per entry, generic when the body
 * is empty or not that shape.
 */
function flattenResetError(text: string, status: number): string {
  const generic = `Password reset failed (${status})`;
  try {
    const parsed = JSON.parse(text) as {
      errors?: Record<string, string[]> | string[];
      error?: string;
    };
    if (Array.isArray(parsed.errors) && parsed.errors.length > 0) return parsed.errors.join(', ');
    if (parsed.errors && !Array.isArray(parsed.errors)) {
      const lines = Object.entries(parsed.errors).flatMap(([field, msgs]) =>
        (msgs ?? []).map((m) => `${field.replace(/_/g, ' ')} ${m}`),
      );
      if (lines.length > 0) return lines.join(', ');
    }
    if (parsed.error) return parsed.error;
  } catch {
    // Non-JSON upstream body — fall through.
  }
  return generic;
}

async function handleLoginOrSignup(action: string, body: CredentialsBody) {
  if (!body.email || !body.password) {
    return NextResponse.json({ error: 'Email and password required' }, { status: 400 });
  }

  const path = action === 'login' ? '/api/v1/auth/login' : '/api/v1/auth/signup';
  // Forward the signup affirmations (13+ + Terms agreement) on signup
  // only; login ignores them.
  const user =
    action === 'signup'
      ? {
          email: body.email,
          password: body.password,
          age_confirmation: body.age_confirmation,
          terms_acceptance: body.terms_acceptance,
        }
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
