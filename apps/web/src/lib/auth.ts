/**
 * Phase 4.1 — web auth helpers.
 *
 * Login/signup go through the Next API routes at `/api/auth/*` which
 * proxy to Rails (`/api/v1/auth/*`), then set the JWT into a server-
 * managed `bw_session` HttpOnly cookie. Subsequent fetches read the
 * cookie back via the server helpers below and forward as a Bearer
 * header to Rails — Rails-side auth contract is unchanged.
 *
 * `bw_session` is the only auth cookie. The Phase 3.8 `bw_jwt` cookie
 * this used to mention was JS-readable — it described itself as "not
 * secure for production" — and it is gone: nothing had imported it since
 * the server-managed cookie landed.
 */
'use client';

// The auth response shapes are the codegen'd contract — import them
// from @biteworthy/api-types rather than re-declaring (the generated
// UserPayload also carries the OAuth `provider` field).
import type { UserPayload, AuthResponse } from '@biteworthy/api-types';
export type { UserPayload, AuthResponse };

export class AuthError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'AuthError';
  }
}

/**
 * Coarse, PII-free failure reason for the auth analytics events, derived
 * from an AuthError status. `specific` maps a status to a form-specific
 * reason (login: 401 → wrong_credentials; signup: 422 → rejected — Rails
 * returns 422 for any registration validation failure, not only a taken
 * email, so we don't over-claim). Everything else collapses to
 * server / network / unknown to keep the taxonomy small. `status === 0`
 * means the request never reached the API.
 */
export function authFailureReason(
  status: number,
  specific: Record<number, string> = {},
): string {
  if (specific[status]) return specific[status]!;
  if (status >= 500) return 'server';
  if (status === 0) return 'network';
  return 'unknown';
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
  // Legal remediation E4 — the 13+ affirmation, forwarded to Rails as
  // age_confirmation. The form gates submit on it being true.
  ageConfirmation: boolean,
  // Clickwrap — agreement to the Terms + Privacy Policy, forwarded as
  // terms_acceptance. Also gated by the form.
  termsAcceptance: boolean,
  opts: FetchOptions = {},
): Promise<AuthResponse> {
  return authPost<AuthResponse>(
    '/api/auth/signup',
    { email, password, age_confirmation: ageConfirmation, terms_acceptance: termsAcceptance },
    opts,
  );
}

export async function logout(opts: FetchOptions = {}): Promise<void> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl('/api/auth/logout', {
    method: 'POST',
    credentials: 'same-origin',
  });
  if (!res.ok) throw new AuthError(res.status, 'logout failed');
}
