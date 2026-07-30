import { describe, expect, it, vi } from 'vitest';

/**
 * jwtIsAdmin backs BOTH the /admin layout guard and the header's
 * /api/auth/admin probe. The contract that matters is fail-closed:
 * every ambiguous outcome (signed out, non-200 — including a 404 from
 * an API that predates /me — network error, payload without the field)
 * must resolve to false, because a wrong `true` renders admin chrome
 * to a non-admin while a wrong `false` merely hides a link Rails
 * would still authorize.
 */
import { adminStatus, jwtIsAdmin } from '../admin-auth';

function fetchResolving(body: unknown, ok = true) {
  return vi.fn().mockResolvedValue({ ok, json: async () => body });
}

describe('jwtIsAdmin', () => {
  it('is false without a jwt and never calls the API', async () => {
    const impl = vi.fn();
    expect(await jwtIsAdmin(null, impl as unknown as typeof fetch)).toBe(false);
    expect(impl).not.toHaveBeenCalled();
  });

  it('is true only for a 200 payload with user.is_admin === true', async () => {
    expect(
      await jwtIsAdmin('jwt', fetchResolving({ user: { is_admin: true } }) as unknown as typeof fetch),
    ).toBe(true);
    expect(
      await jwtIsAdmin(
        'jwt',
        fetchResolving({ user: { is_admin: false } }) as unknown as typeof fetch,
      ),
    ).toBe(false);
  });

  it('fails closed on non-200 (e.g. an API deployed without /me yet)', async () => {
    expect(
      await jwtIsAdmin(
        'jwt',
        fetchResolving({ user: { is_admin: true } }, false) as unknown as typeof fetch,
      ),
    ).toBe(false);
  });

  it('fails closed when the payload is missing the field (deploy skew)', async () => {
    expect(await jwtIsAdmin('jwt', fetchResolving({ user: {} }) as unknown as typeof fetch)).toBe(
      false,
    );
    expect(await jwtIsAdmin('jwt', fetchResolving({}) as unknown as typeof fetch)).toBe(false);
  });

  it('fails closed on network errors', async () => {
    const impl = vi.fn().mockRejectedValue(new Error('boom'));
    expect(await jwtIsAdmin('jwt', impl as unknown as typeof fetch)).toBe(false);
  });

  it('distinguishes an expired/revoked session (401) so the layout can bounce to login', async () => {
    const impl = vi.fn().mockResolvedValue({ ok: false, status: 401, json: async () => ({}) });
    expect(await adminStatus('stale-jwt', impl as unknown as typeof fetch)).toBe('unauthenticated');
    // Any other upstream failure stays a plain denial, not a login loop.
    const impl500 = vi.fn().mockResolvedValue({ ok: false, status: 500, json: async () => ({}) });
    expect(await adminStatus('jwt', impl500 as unknown as typeof fetch)).toBe('denied');
  });

  it('sends the bearer token to /api/v1/me with caching disabled', async () => {
    const impl = fetchResolving({ user: { is_admin: true } });
    await jwtIsAdmin('jwt-1', impl as unknown as typeof fetch);
    const call = impl.mock.calls[0] as unknown as [
      string,
      { headers: Record<string, string>; cache: RequestCache },
    ];
    expect(String(call[0])).toContain('/api/v1/me');
    expect(call[1].headers.Authorization).toBe('Bearer jwt-1');
    expect(call[1].cache).toBe('no-store');
  });
});
