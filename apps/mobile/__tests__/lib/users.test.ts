import {
  fetchPublicUserProfile,
  UserProfileFetchError,
  type PublicUserProfile,
} from '../../lib/api/users';

const samplePayload: PublicUserProfile = {
  handle: 'diner_jane',
  display_name: 'Diner Jane',
  member_since: '2026-04-01T00:00:00Z',
  reviews_count: 3,
  restaurants_reviewed_count: 2,
  recent_reviews: [],
};

type FetchCall = Parameters<typeof fetch>;
type FetchMock = jest.Mock<Promise<Response>, FetchCall>;

function fakeFetch(status: number, body: unknown): FetchMock {
  return jest.fn(async (..._args: FetchCall) =>
    ({
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
    }) as unknown as Response,
  ) as FetchMock;
}

describe('fetchPublicUserProfile (mobile)', () => {
  it('GETs the public user endpoint and returns the parsed payload', async () => {
    const fetchImpl = fakeFetch(200, samplePayload);
    const out = await fetchPublicUserProfile('diner_jane', { fetchImpl });
    expect(out).toEqual(samplePayload);
    expect(String(fetchImpl.mock.calls[0]![0])).toContain('/api/v1/users/diner_jane');
  });

  it('returns null on 404 (mirrors the web client semantics)', async () => {
    const fetchImpl = fakeFetch(404, { error: 'not found' });
    const out = await fetchPublicUserProfile('ghost', { fetchImpl });
    expect(out).toBeNull();
  });

  it('throws UserProfileFetchError on other non-2xx', async () => {
    const fetchImpl = fakeFetch(500, { error: 'boom' });
    await expect(fetchPublicUserProfile('diner_jane', { fetchImpl })).rejects.toBeInstanceOf(
      UserProfileFetchError,
    );
  });
});
