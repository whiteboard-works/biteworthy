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

const API_BASE = process.env.EXPO_PUBLIC_API_BASE ?? 'http://localhost:3000';
const TOKEN_KEY = 'bw_jwt';

export interface UserPayload {
  id: string;
  email: string;
  handle: string | null;
  display_name: string | null;
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

export async function getJwt(): Promise<string | null> {
  try {
    return (await SecureStore.getItemAsync(TOKEN_KEY)) ?? null;
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
  opts: AuthOptions = {},
): Promise<UserPayload> {
  return await postCredentials('/api/v1/auth/signup', email, password, opts);
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
): Promise<UserPayload> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`${API_BASE}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({ user: { email, password } }),
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
