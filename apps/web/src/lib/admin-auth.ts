/**
 * Resolves "is this session an admin?" against Rails `GET /api/v1/me`.
 * Shared by the /admin layout guard and the /api/auth/admin header
 * probe; ambiguity fails CLOSED — non-200 (including a 404 from an
 * API that hasn't deployed /me yet), network failure, or a payload
 * missing the field (web and API deploy independently) all resolve to
 * `denied`. The one distinction that matters for UX: an upstream 401
 * means the cookie's JWT is expired/revoked, so the layout can send
 * the visitor to login instead of a confusing 404. Hiding the shell
 * from a real admin is harmless: Rails re-checks `is_admin` on every
 * admin API call — this is UI gating only.
 */
import { API_BASE } from './api-base';

export type AdminStatus = 'admin' | 'denied' | 'unauthenticated';

export async function adminStatus(
  jwt: string | null,
  fetchImpl: typeof fetch = fetch,
): Promise<AdminStatus> {
  if (!jwt) return 'unauthenticated';
  try {
    const res = await fetchImpl(`${API_BASE}/api/v1/me`, {
      headers: { Authorization: `Bearer ${jwt}`, Accept: 'application/json' },
      cache: 'no-store',
    });
    if (res.status === 401) return 'unauthenticated';
    if (!res.ok) return 'denied';
    const body = (await res.json()) as { user?: { is_admin?: boolean } };
    return body.user?.is_admin === true ? 'admin' : 'denied';
  } catch {
    return 'denied';
  }
}

/** Boolean view for callers that only branch on adminness (the header probe). */
export async function jwtIsAdmin(
  jwt: string | null,
  fetchImpl: typeof fetch = fetch,
): Promise<boolean> {
  return (await adminStatus(jwt, fetchImpl)) === 'admin';
}
