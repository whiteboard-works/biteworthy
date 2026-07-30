import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * `{ admin }` backs the header's Admin link. It must never 401 (the
 * header calls it for every signed-in user), must fail safe to false,
 * and must not be cacheable — a cached `true` replayed by a shared
 * cache would render the link for the wrong visitor.
 */

const mockGetServerJwt = vi.fn();
vi.mock('../../../../../lib/server-auth', () => ({
  getServerJwt: () => mockGetServerJwt(),
}));

import { GET } from '../route';

beforeEach(() => {
  vi.restoreAllMocks();
  mockGetServerJwt.mockReset();
});

describe('GET /api/auth/admin', () => {
  it('returns admin:false without an upstream call when signed out, and forbids caching', async () => {
    mockGetServerJwt.mockResolvedValue(null);
    const fetchSpy = vi.spyOn(globalThis, 'fetch');
    const res = await GET();
    expect(await res.json()).toEqual({ admin: false });
    expect(res.headers.get('Cache-Control')).toBe('no-store');
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('returns admin:true when Rails confirms is_admin', async () => {
    mockGetServerJwt.mockResolvedValue('jwt-1');
    vi.spyOn(globalThis, 'fetch').mockResolvedValue({
      ok: true,
      json: async () => ({ user: { is_admin: true } }),
    } as unknown as Response);
    expect(await (await GET()).json()).toEqual({ admin: true });
  });

  it('fails safe to admin:false when the lookup errors', async () => {
    mockGetServerJwt.mockResolvedValue('jwt-1');
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('network'));
    expect(await (await GET()).json()).toEqual({ admin: false });
  });
});
