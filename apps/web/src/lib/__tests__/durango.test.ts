import { describe, expect, it, vi } from 'vitest';
import {
  CityRankingError,
  DURANGO_DIET_SLUGS,
  fetchCityRanking,
  type CityRanked,
} from '../durango';

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

const samplePayload: CityRanked = {
  city: { id: 'c-1', slug: 'durango', name: 'Durango', region: 'CO' },
  profile: { id: 'p-1', slug: 'vegan', name: 'Vegan', description: null },
  restaurants: [
    { id: 'r-1', slug: 'tacos', name: 'Tacos', visible_count: 5, hidden_count: 2, total_count: 7 },
  ],
};

describe('fetchCityRanking', () => {
  it('GETs /api/v1/cities/:city/restaurants?profile=:diet with Accept JSON', async () => {
    const fetchImpl = fakeFetch(200, samplePayload);
    const out = await fetchCityRanking('durango', 'vegan', { fetchImpl });
    expect(out.restaurants[0]!.name).toBe('Tacos');
    const url = String(fetchImpl.mock.calls[0]![0]);
    expect(url).toContain('/api/v1/cities/durango/restaurants?profile=vegan');
    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect((init.headers as Record<string, string>).Accept).toBe('application/json');
  });

  it('encodes city + diet slugs containing reserved chars', async () => {
    const fetchImpl = fakeFetch(200, samplePayload);
    await fetchCityRanking('san josé', 'tree nut free', { fetchImpl });
    const url = String(fetchImpl.mock.calls[0]![0]);
    expect(url).toContain('/api/v1/cities/san%20jos%C3%A9/restaurants?profile=tree%20nut%20free');
  });

  it('throws CityRankingError preserving the upstream status (404 → notFound() in SSR)', async () => {
    const fetchImpl = fakeFetch(404, { error: 'unknown city' });
    await expect(fetchCityRanking('nope', 'vegan', { fetchImpl })).rejects.toMatchObject({
      name: 'CityRankingError',
      status: 404,
    });
  });

  it('throws on 500 too so SSR can boundary-error rather than render half a page', async () => {
    const fetchImpl = fakeFetch(500, {});
    await expect(fetchCityRanking('durango', 'vegan', { fetchImpl })).rejects.toBeInstanceOf(
      CityRankingError,
    );
  });
});

describe('DURANGO_DIET_SLUGS', () => {
  it('contains the curated production-ready presets seeded in Phase 3.1', () => {
    expect(DURANGO_DIET_SLUGS).toContain('vegan');
    expect(DURANGO_DIET_SLUGS).toContain('celiac');
    expect(DURANGO_DIET_SLUGS).toContain('tree-nut-free');
    // Order matters for stable sitemap output.
    expect(DURANGO_DIET_SLUGS[0]).toBe('vegan');
  });
});
