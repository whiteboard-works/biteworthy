import { describe, expect, it, vi } from 'vitest';
import { fetchHistory, HistoryError, type HistoryResponse } from '../history';

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

type FetchArgs = Parameters<typeof fetch>;

function fakeFetch(status: number, body: unknown) {
  return vi.fn(
    async (..._args: FetchArgs) =>
      ({
        ok: status >= 200 && status < 300,
        status,
        statusText: status === 200 ? 'OK' : 'ERR',
        json: async () => body,
      }) as unknown as Response,
  );
}

describe('fetchHistory', () => {
  it('GETs the Next proxy at /api/profile/history with credentials', async () => {
    const fetchImpl = fakeFetch(200, samplePayload);
    const out = await fetchHistory({ fetchImpl });
    expect(out.total).toBe(1);

    const url = String(fetchImpl.mock.calls[0]![0]);
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect(url).toBe('/api/profile/history');
    expect(init.credentials).toBe('same-origin');
  });

  it('passes limit + offset query params when supplied', async () => {
    const fetchImpl = fakeFetch(200, samplePayload);
    await fetchHistory({ fetchImpl, limit: 10, offset: 20 });
    const url = String(fetchImpl.mock.calls[0]![0]);
    expect(url).toContain('limit=10');
    expect(url).toContain('offset=20');
  });

  it('throws HistoryError preserving status (for 401 → /login redirects)', async () => {
    const fetchImpl = fakeFetch(401, { error: 'Not signed in' });
    await expect(fetchHistory({ fetchImpl })).rejects.toMatchObject({
      name: 'HistoryError',
      status: 401,
    });
  });
});
