import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The `{ signedIn, onboarded }` read the site header uses to pick
 * Sign-in vs Account, and to decide whether to nudge a signed-in user
 * who hasn't finished onboarding. Auth state must never be cacheable,
 * or a shared cache could hand a signed-in response to a signed-out
 * visitor. `onboarded` fails safe to true so a transient API error
 * never nags an already-set-up user.
 */

const mockGetServerUserId = vi.fn();
const mockGetServerJwt = vi.fn();
vi.mock('../../../../../lib/server-auth', () => ({
  getServerUserId: () => mockGetServerUserId(),
  getServerJwt: () => mockGetServerJwt(),
}));

import { GET } from '../route';

function mockProfileFetch(body: { disclaimer_acknowledged_at?: string | null }, ok = true) {
  return vi.spyOn(globalThis, 'fetch').mockResolvedValue({
    ok,
    json: async () => body,
  } as unknown as Response);
}

beforeEach(() => {
  vi.restoreAllMocks();
  mockGetServerUserId.mockReset();
  mockGetServerJwt.mockReset();
});

describe('GET /api/auth/session', () => {
  it('reports signedIn:false without a profile lookup, and forbids caching', async () => {
    mockGetServerUserId.mockResolvedValue(null);
    const fetchSpy = vi.spyOn(globalThis, 'fetch');
    const res = await GET();
    expect(await res.json()).toEqual({ signedIn: false, onboarded: false });
    expect(res.headers.get('Cache-Control')).toBe('no-store');
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('reports onboarded:true when the profile has a disclaimer_acknowledged_at', async () => {
    mockGetServerUserId.mockResolvedValue('user-1');
    mockGetServerJwt.mockResolvedValue('jwt-1');
    mockProfileFetch({ disclaimer_acknowledged_at: '2026-07-20T00:00:00Z' });
    const res = await GET();
    expect(await res.json()).toEqual({ signedIn: true, onboarded: true });
  });

  it('reports onboarded:false when onboarding has not been completed', async () => {
    mockGetServerUserId.mockResolvedValue('user-1');
    mockGetServerJwt.mockResolvedValue('jwt-1');
    mockProfileFetch({ disclaimer_acknowledged_at: null });
    const res = await GET();
    expect(await res.json()).toEqual({ signedIn: true, onboarded: false });
  });

  it('fails safe to onboarded:true when the profile lookup errors', async () => {
    mockGetServerUserId.mockResolvedValue('user-1');
    mockGetServerJwt.mockResolvedValue('jwt-1');
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('network'));
    const res = await GET();
    expect(await res.json()).toEqual({ signedIn: true, onboarded: true });
  });
});
