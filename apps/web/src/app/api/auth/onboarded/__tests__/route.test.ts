import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * `{ onboarded }` drives the header's resume nudge. It reads the profile
 * from Rails, so unlike /api/auth/session it CAN call the API — but it
 * fails safe to `true` (never nag) whenever it can't tell: signed out,
 * non-200, or a fetch error.
 */

const mockGetServerJwt = vi.fn();
vi.mock('../../../../../lib/server-auth', () => ({
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
  mockGetServerJwt.mockReset();
});

describe('GET /api/auth/onboarded', () => {
  it('returns onboarded:true without a lookup when signed out, and forbids caching', async () => {
    mockGetServerJwt.mockResolvedValue(null);
    const fetchSpy = vi.spyOn(globalThis, 'fetch');
    const res = await GET();
    expect(await res.json()).toEqual({ onboarded: true });
    expect(res.headers.get('Cache-Control')).toBe('no-store');
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('reports onboarded:true when the profile has a disclaimer_acknowledged_at', async () => {
    mockGetServerJwt.mockResolvedValue('jwt-1');
    mockProfileFetch({ disclaimer_acknowledged_at: '2026-07-20T00:00:00Z' });
    expect(await (await GET()).json()).toEqual({ onboarded: true });
  });

  it('reports onboarded:false when onboarding has not been completed', async () => {
    mockGetServerJwt.mockResolvedValue('jwt-1');
    mockProfileFetch({ disclaimer_acknowledged_at: null });
    expect(await (await GET()).json()).toEqual({ onboarded: false });
  });

  it('fails safe to onboarded:true when the profile lookup errors', async () => {
    mockGetServerJwt.mockResolvedValue('jwt-1');
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('network'));
    expect(await (await GET()).json()).toEqual({ onboarded: true });
  });
});
