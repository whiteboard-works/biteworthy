/**
 * Phase 4.1 — web auth helpers.
 *
 * Login/signup go through the Next API routes at `/api/auth/*` which
 * proxy to Rails (`/api/v1/auth/*`), then set the JWT into a server-
 * managed `bw_session` HttpOnly cookie. Subsequent fetches read the
 * cookie back via the server helpers below and forward as a Bearer
 * header to Rails — Rails-side auth contract is unchanged.
 *
 * The legacy `bw_jwt` JS-readable cookie from Phase 3.8 stays around
 * for the dev shortcut + for non-auth flows that need a token in the
 * URL (claim, password reset). Production reads `bw_session`.
 */
'use client';

export interface UserPayload {
  id: string;
  email: string;
  handle: string | null;
  display_name: string | null;
}

export interface AuthResponse {
  user: UserPayload;
}

export class AuthError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'AuthError';
  }
}

interface FetchOptions {
  fetchImpl?: typeof fetch;
}

async function authPost<T>(
  path: string,
  body: unknown,
  opts: FetchOptions = {},
): Promise<T> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    credentials: 'same-origin',
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    let detail: string | null = null;
    try {
      const parsed = (await res.json()) as { error?: string };
      detail = parsed?.error ?? null;
    } catch {
      // ignore
    }
    throw new AuthError(res.status, detail ?? `${path} failed: ${res.status}`);
  }
  return (await res.json()) as T;
}

export function login(
  email: string,
  password: string,
  opts: FetchOptions = {},
): Promise<AuthResponse> {
  return authPost<AuthResponse>('/api/auth/login', { email, password }, opts);
}

export function signup(
  email: string,
  password: string,
  opts: FetchOptions = {},
): Promise<AuthResponse> {
  return authPost<AuthResponse>('/api/auth/signup', { email, password }, opts);
}

export async function logout(opts: FetchOptions = {}): Promise<void> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl('/api/auth/logout', {
    method: 'POST',
    credentials: 'same-origin',
  });
  if (!res.ok) throw new AuthError(res.status, 'logout failed');
}
