/**
 * Phase 4.1 — mobile auth helpers.
 *
 * `getJwt` / `setJwt` / `clearJwt` wrap `expo-secure-store` so the
 * JWT lives in the OS keychain (iOS) / Keystore (Android) instead of
 * a paste-the-token URL param the way Phases 1–3 deferred it.
 *
 * `login` / `signup` POST to Rails directly (mobile doesn't go
 * through a Next proxy), pull the JWT off the response's
 * `Authorization` header, and persist it. `logout` clears the token
 * locally and best-effort calls Rails to rotate the user's jti.
 *
 * The store is mocked module-level in tests so this stays jest-pure.
 */
import * as SecureStore from 'expo-secure-store';

// The auth user shape is the codegen'd contract — import it from
// @biteworthy/api-types rather than re-declaring.
import type { UserPayload } from '@biteworthy/api-types';

import { API_BASE } from './api-base';
const TOKEN_KEY = 'bw_jwt';

export type { UserPayload };

export class AuthError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'AuthError';
  }
}

export async function getJwt(): Promise<string | null> {
  try {
    return (await SecureStore.getItemAsync(TOKEN_KEY)) ?? null;
  } catch {
    return null;
  }
}

/**
 * The signed-in user's id, decoded from the stored JWT's `sub` claim
 * (devise-jwt). Legal remediation E11 uses it to show the owner-only
 * edit/delete controls on a review. Display-only — the API still gates
 * every mutation by ownership — so we don't verify the signature.
 */
export async function getUserId(): Promise<string | null> {
  const token = await getJwt();
  if (!token) return null;
  const payload = token.split('.')[1];
  if (!payload) return null;
  try {
    const json = atob(payload.replace(/-/g, '+').replace(/_/g, '/'));
    const sub = (JSON.parse(json) as { sub?: unknown }).sub;
    return typeof sub === 'string' && sub.length > 0 ? sub : null;
  } catch {
    return null;
  }
}

export async function setJwt(token: string): Promise<void> {
  await SecureStore.setItemAsync(TOKEN_KEY, token);
}

export async function clearJwt(): Promise<void> {
  await SecureStore.deleteItemAsync(TOKEN_KEY);
}

export interface AuthOptions {
  fetchImpl?: typeof fetch;
}

export async function login(
  email: string,
  password: string,
  opts: AuthOptions = {},
): Promise<UserPayload> {
  return await postCredentials('/api/v1/auth/login', email, password, opts);
}

export async function signup(
  email: string,
  password: string,
  // Legal remediation E4 — the 13+ affirmation, sent as age_confirmation.
  ageConfirmation: boolean,
  // Clickwrap — agreement to the Terms + Privacy Policy, sent as
  // terms_acceptance.
  termsAcceptance: boolean,
  opts: AuthOptions = {},
): Promise<UserPayload> {
  return await postCredentials('/api/v1/auth/signup', email, password, opts, {
    age_confirmation: ageConfirmation,
    terms_acceptance: termsAcceptance,
  });
}

export async function logout(opts: AuthOptions = {}): Promise<void> {
  const { fetchImpl = fetch } = opts;
  const token = await getJwt();
  if (token) {
    // Best-effort jti rotation — swallow errors so a disconnected
    // user can still log out locally.
    await fetchImpl(`${API_BASE}/api/v1/auth/logout`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
    }).catch(() => {});
  }
  await clearJwt();
}

async function postCredentials(
  path: string,
  email: string,
  password: string,
  opts: AuthOptions,
  // Extra user fields merged into the request (e.g. age_confirmation on
  // signup). Login passes nothing.
  extraUserFields: Record<string, unknown> = {},
): Promise<UserPayload> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`${API_BASE}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({ user: { email, password, ...extraUserFields } }),
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
  const token = extractBearer(res.headers.get('Authorization'));
  if (!token) {
    throw new AuthError(502, 'Auth response missing Authorization header');
  }
  await setJwt(token);
  const body = (await res.json()) as { user: UserPayload };
  return body.user;
}

function extractBearer(header: string | null): string | null {
  if (!header) return null;
  const match = /^Bearer\s+(.+)$/i.exec(header);
  return match ? match[1]!.trim() : null;
}
