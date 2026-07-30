/**
 * Resolves "is this session an admin?" against Rails `GET /api/v1/me`.
 * Shared by the /admin layout guard and the /api/auth/admin header
 * probe; both fail CLOSED (false) on any ambiguity — signed out,
 * non-200 (including a 404 from an API that hasn't deployed /me yet),
 * network failure, or a payload missing the field (web and API deploy
 * independently). Hiding the shell from a real admin is harmless:
 * Rails re-checks `is_admin` on every admin API call — this is UI
 * gating only.
 */
import { API_BASE } from './api-base';

export async function jwtIsAdmin(
  jwt: string | null,
  fetchImpl: typeof fetch = fetch,
): Promise<boolean> {
  if (!jwt) return false;
  try {
    const res = await fetchImpl(`${API_BASE}/api/v1/me`, {
      headers: { Authorization: `Bearer ${jwt}`, Accept: 'application/json' },
      cache: 'no-store',
    });
    if (!res.ok) return false;
    const body = (await res.json()) as { user?: { is_admin?: boolean } };
    return body.user?.is_admin === true;
  } catch {
    return false;
  }
}
