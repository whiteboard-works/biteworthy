import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';
import { GET } from '../route';

/**
 * The menu is filtered by who is asking, so the one thing this handler
 * must never do is drop the caller's credential — that is the bug it
 * exists to fix. It must also stay reachable without one: browsing a
 * menu never requires an account.
 */

const mockGetServerJwt = vi.fn();
vi.mock('../../../../../../lib/server-auth', () => ({
  getServerJwt: () => mockGetServerJwt(),
}));

beforeEach(() => {
  mockGetServerJwt.mockReset().mockResolvedValue('jwt-123');
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({
      status: 200,
      text: async () => '{"items":[]}',
      headers: { get: () => 'application/json' },
    }),
  );
});

afterEach(() => vi.unstubAllGlobals());

function call(query = '') {
  return GET(new NextRequest(`http://localhost:3001/api/restaurants/ninis/items${query}`), {
    params: Promise.resolve({ slug: 'ninis' }),
  });
}

function lastFetch() {
  const mock = fetch as unknown as { mock: { calls: [string, RequestInit][] } };
  return mock.mock.calls[0]!;
}

describe('GET /api/restaurants/:slug/items', () => {
  it('forwards the session JWT as a Bearer token', async () => {
    await call();
    const [, init] = lastFetch();
    expect((init.headers as Record<string, string>).Authorization).toBe('Bearer jwt-123');
  });

  it('still proxies anonymously — a menu never requires an account', async () => {
    mockGetServerJwt.mockResolvedValue(null);
    const res = await call();
    expect(res.status).toBe(200);
    const [, init] = lastFetch();
    expect((init.headers as Record<string, string>).Authorization).toBeUndefined();
  });

  it('forwards only the params Rails reads, and drops the rest', async () => {
    await call('?strictness=strict&profile=vegan&profile_token=tok&evil=1');
    const [url] = lastFetch();
    expect(url).toContain('strictness=strict');
    expect(url).toContain('profile=vegan');
    expect(url).toContain('profile_token=tok');
    expect(url).not.toContain('evil');
  });

  it('marks the response private — it varies by caller', async () => {
    const res = await call();
    expect(res.headers.get('Cache-Control')).toBe('private, no-store');
  });

  it('relays an upstream failure rather than masking it', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        status: 404,
        text: async () => '{"error":"not found"}',
        headers: { get: () => 'application/json' },
      }),
    );
    const res = await call();
    expect(res.status).toBe(404);
  });
});
