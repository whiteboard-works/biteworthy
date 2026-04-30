import { describe, expect, it, vi } from 'vitest';
import { fetchPublicUserProfile, type PublicUserProfile } from '../users';

const samplePayload: PublicUserProfile = {
  handle: 'diner_jane',
  display_name: 'Diner Jane',
  member_since: '2026-04-01T00:00:00Z',
  reviews_count: 3,
  restaurants_reviewed_count: 2,
  recent_reviews: [],
};

type FetchArgs = Parameters<typeof fetch>;

function fakeFetch(status: number, body: unknown) {
  return vi.fn(
    async (..._args: FetchArgs) =>
      ({
        ok: status >= 200 && status < 300,
        status,
        statusText: status === 200 ? 'OK' : 'NOT FOUND',
        json: async () => body,
      }) as unknown as Response,
  );
}

describe('fetchPublicUserProfile', () => {
  it('GETs /api/v1/users/:handle and returns the parsed payload', async () => {
    const fetchImpl = fakeFetch(200, samplePayload);
    const out = await fetchPublicUserProfile('diner_jane', { fetchImpl });
    expect(out).toEqual(samplePayload);
    expect(String(fetchImpl.mock.calls[0]![0])).toContain('/api/v1/users/diner_jane');
  });

  it('returns null on 404 (so SSR can call notFound())', async () => {
    const fetchImpl = fakeFetch(404, { error: 'not found' });
    const out = await fetchPublicUserProfile('ghost', { fetchImpl });
    expect(out).toBeNull();
  });

  it('throws on other non-2xx', async () => {
    const fetchImpl = fakeFetch(500, { error: 'boom' });
    await expect(fetchPublicUserProfile('diner_jane', { fetchImpl })).rejects.toThrow(/500/);
  });

  it('URL-encodes handles that contain reserved chars (defense-in-depth)', async () => {
    const fetchImpl = fakeFetch(200, samplePayload);
    await fetchPublicUserProfile('a/b', { fetchImpl });
    expect(String(fetchImpl.mock.calls[0]![0])).toContain('/api/v1/users/a%2Fb');
  });
});
