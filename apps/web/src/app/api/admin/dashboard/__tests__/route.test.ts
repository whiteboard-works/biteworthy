import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The ops dashboard's proxy. Must forward the cookie JWT to the exact
 * Rails admin path, relay the gate statuses verbatim (401 signed out,
 * 404 non-admin), and never let admin JSON become cacheable.
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

describe('GET /api/admin/dashboard', () => {
  it('forwards to the Rails admin dashboard with the bearer token and no-store response', async () => {
    mockGetServerJwt.mockResolvedValue('jwt-1');
    const spy = vi.spyOn(globalThis, 'fetch').mockResolvedValue({
      status: 200,
      text: async () => '{"queues":{}}',
      headers: { get: () => 'application/json' },
    } as unknown as Response);

    const res = await GET();

    const [url, init] = spy.mock.calls[0]! as [string, { headers: Record<string, string> }];
    expect(String(url)).toContain('/api/v1/admin/dashboard');
    expect(init.headers.Authorization).toBe('Bearer jwt-1');
    expect(res.status).toBe(200);
    expect(res.headers.get('Cache-Control')).toBe('no-store');
  });

  it('401s locally without an upstream call when signed out', async () => {
    mockGetServerJwt.mockResolvedValue(null);
    const spy = vi.spyOn(globalThis, 'fetch');
    const res = await GET();
    expect(res.status).toBe(401);
    expect(spy).not.toHaveBeenCalled();
  });

  it('relays a Rails 404 (non-admin) verbatim', async () => {
    mockGetServerJwt.mockResolvedValue('jwt-1');
    vi.spyOn(globalThis, 'fetch').mockResolvedValue({
      status: 404,
      text: async () => '{"error":"not_found"}',
      headers: { get: () => 'application/json' },
    } as unknown as Response);
    const res = await GET();
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: 'not_found' });
  });
});
