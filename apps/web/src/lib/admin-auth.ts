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

/**
 * Status plus the tier, from the one `/me` call. `is_super_admin` is a
 * strict boolean check for the same fail-closed reason as `is_admin`:
 * a payload missing the field (web and API deploy independently)
 * resolves to false, so a stale API hides the destructive controls
 * rather than offering ones the server will refuse.
 */
export interface AdminIdentity {
  status: AdminStatus;
  isSuperAdmin: boolean;
}

export async function adminIdentity(
  jwt: string | null,
  fetchImpl: typeof fetch = fetch,
): Promise<AdminIdentity> {
  if (!jwt) return { status: 'unauthenticated', isSuperAdmin: false };
  try {
    const res = await fetchImpl(`${API_BASE}/api/v1/me`, {
      headers: { Authorization: `Bearer ${jwt}`, Accept: 'application/json' },
      cache: 'no-store',
    });
    if (res.status === 401) return { status: 'unauthenticated', isSuperAdmin: false };
    if (!res.ok) return { status: 'denied', isSuperAdmin: false };
    const body = (await res.json()) as {
      user?: { is_admin?: boolean; is_super_admin?: boolean };
    };
    if (body.user?.is_admin !== true) return { status: 'denied', isSuperAdmin: false };
    return { status: 'admin', isSuperAdmin: body.user.is_super_admin === true };
  } catch {
    return { status: 'denied', isSuperAdmin: false };
  }
}

export async function adminStatus(
  jwt: string | null,
  fetchImpl: typeof fetch = fetch,
): Promise<AdminStatus> {
  return (await adminIdentity(jwt, fetchImpl)).status;
}

/** Boolean view for callers that only branch on adminness (the header probe). */
export async function jwtIsAdmin(
  jwt: string | null,
  fetchImpl: typeof fetch = fetch,
): Promise<boolean> {
  return (await adminStatus(jwt, fetchImpl)) === 'admin';
}
