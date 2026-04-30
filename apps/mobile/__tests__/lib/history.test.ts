import {
  fetchHistory,
  HistoryError,
  type HistoryResponse,
} from '../../lib/api/history';

const samplePayload: HistoryResponse = {
  total: 1,
  visits: [
    {
      id: 'v1',
      viewed_on: '2026-04-30',
      updated_at: '2026-04-30T12:00:00Z',
      items_visible_count: 5,
      items_hidden_count: 1,
      restaurant: {
        id: 'rest-1',
        slug: 'cream-bean-berry-1',
        name: 'Cream, Bean & Berry',
        city: { slug: 'durango', name: 'Durango', region: 'CO' },
      },
    },
  ],
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

describe('fetchHistory (mobile)', () => {
  it('GETs the API endpoint with Bearer JWT', async () => {
    const fetchImpl = fakeFetch(200, samplePayload);
    const out = await fetchHistory('jjj.www.ttt', { fetchImpl });
    expect(out.total).toBe(1);

    const url = String(fetchImpl.mock.calls[0]![0]);
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(url).toContain('/api/v1/profile/history');
    expect((init.headers as Record<string, string>).Authorization).toBe('Bearer jjj.www.ttt');
  });

  it('passes limit + offset query params when supplied', async () => {
    const fetchImpl = fakeFetch(200, samplePayload);
    await fetchHistory('jwt', { fetchImpl, limit: 10, offset: 20 });
    const url = String(fetchImpl.mock.calls[0]![0]);
    expect(url).toContain('limit=10');
    expect(url).toContain('offset=20');
  });

  it('throws HistoryError on 401 so the screen can bounce to /login', async () => {
    const fetchImpl = fakeFetch(401, { error: 'unauth' });
    await expect(fetchHistory('bad', { fetchImpl })).rejects.toBeInstanceOf(HistoryError);
  });
});
