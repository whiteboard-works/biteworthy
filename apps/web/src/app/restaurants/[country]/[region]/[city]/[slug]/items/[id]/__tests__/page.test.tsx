import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * A dish page is indexable, so a stale country/region/city in its URL
 * must 301 to the canonical location rather than render a duplicate.
 */

const mockFetchRestaurant = vi.fn();
const mockFetchItem = vi.fn();
vi.mock('../../../../../../../../../lib/restaurants', () => ({
  fetchRestaurant: (slug: string, opts: unknown) => mockFetchRestaurant(slug, opts),
  fetchItem: (slug: string, id: string, opts: unknown) => mockFetchItem(slug, id, opts),
}));
vi.mock('../../../../../../../../../lib/reviews', () => ({
  fetchReviewsServer: async () => null,
}));
vi.mock('../../../../../../../../../lib/edge-headers', () => ({ edgeHeaders: async () => ({}) }));
vi.mock('../../../../../../../../../lib/server-auth', () => ({
  getServerJwt: async () => null,
  getServerUserId: async () => null,
}));

const mockPermanentRedirect = vi.fn((_target: string): never => {
  throw new Error('NEXT_REDIRECT');
});
vi.mock('next/navigation', () => ({
  notFound: (): never => {
    throw new Error('NEXT_NOT_FOUND');
  },
  permanentRedirect: (target: string) => mockPermanentRedirect(target),
}));

import ItemDetailPage from '../page';

beforeEach(() => {
  mockFetchRestaurant.mockReset().mockResolvedValue({
    web_path: '/restaurants/usa/colorado/durango/rgp-s-wraps',
  });
  mockFetchItem.mockReset().mockResolvedValue({ id: 'i-1' });
  mockPermanentRedirect.mockClear();
});

describe('ItemDetailPage — canonical redirect on a location mismatch', () => {
  it('301s to the dish under the real location, keeping the query string', async () => {
    await expect(
      ItemDetailPage({
        params: Promise.resolve({
          country: 'usa',
          region: 'utah',
          city: 'salt-lake-city',
          slug: 'rgp-s-wraps',
          id: 'i-1',
        }),
        searchParams: Promise.resolve({ profile: 'vegan' }),
      }),
    ).rejects.toThrow('NEXT_REDIRECT');

    expect(mockPermanentRedirect).toHaveBeenCalledWith(
      '/restaurants/usa/colorado/durango/rgp-s-wraps/items/i-1?profile=vegan',
    );
  });
});
