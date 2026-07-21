import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The `{ signedIn }` read the site header uses to pick Sign-in vs
 * Account. Auth state must never be cacheable, or a shared cache could
 * hand a signed-in response to a signed-out visitor. It's a purely-local
 * cookie read — it must NOT call the API, so signed-in state stays fast
 * and independent of Rails health (onboarding status lives in the
 * separate /api/auth/onboarded route).
 */

const mockGetServerUserId = vi.fn();
vi.mock('../../../../../lib/server-auth', () => ({
  getServerUserId: () => mockGetServerUserId(),
}));

import { GET } from '../route';

beforeEach(() => {
  vi.restoreAllMocks();
  mockGetServerUserId.mockReset();
});

describe('GET /api/auth/session', () => {
  it('reports signedIn:false and forbids caching when there is no session', async () => {
    mockGetServerUserId.mockResolvedValue(null);
    const res = await GET();
    expect(await res.json()).toEqual({ signedIn: false });
    expect(res.headers.get('Cache-Control')).toBe('no-store');
  });

  it('reports signedIn:true without any upstream call when a user id is present', async () => {
    mockGetServerUserId.mockResolvedValue('user-1');
    const fetchSpy = vi.spyOn(globalThis, 'fetch');
    const res = await GET();
    expect(await res.json()).toEqual({ signedIn: true });
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});
