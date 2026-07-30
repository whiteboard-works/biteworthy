import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';

/**
 * The runs-queue proxy must pass filters through untouched (a dropped
 * param silently unfilters the moderation inbox) and keep admin JSON
 * uncacheable.
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

describe('GET /api/admin/ingestion_runs', () => {
  it('forwards the query string verbatim with the bearer token and no-store', async () => {
    mockGetServerJwt.mockResolvedValue('jwt-1');
    const spy = vi.spyOn(globalThis, 'fetch').mockResolvedValue({
      status: 200,
      text: async () => '{"runs":[]}',
      headers: { get: () => 'application/json' },
    } as unknown as Response);

    const req = new NextRequest(
      'http://localhost/api/admin/ingestion_runs?status=staged&community=true&offset=25',
    );
    const res = await GET(req);

    const [url, init] = spy.mock.calls[0]! as [string, { headers: Record<string, string> }];
    expect(String(url)).toContain(
      '/api/v1/admin/ingestion_runs?status=staged&community=true&offset=25',
    );
    expect(init.headers.Authorization).toBe('Bearer jwt-1');
    expect(res.headers.get('Cache-Control')).toBe('no-store');
  });

  it('401s locally when signed out', async () => {
    mockGetServerJwt.mockResolvedValue(null);
    const res = await GET(new NextRequest('http://localhost/api/admin/ingestion_runs'));
    expect(res.status).toBe(401);
  });
});
