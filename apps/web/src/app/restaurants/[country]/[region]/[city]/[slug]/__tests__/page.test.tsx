import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Location-based URLs — lookup is always by the trailing slug, so a
 * country/region/city segment that doesn't match the restaurant's real
 * location must not silently render — it 301s to the canonical
 * `web_path` (query string preserved). This only fires once the
 * restaurant has actually been fetched; a failed fetch (a draft, an
 * unknown slug) falls through to the existing notFound() instead.
 */

const mockFetchRestaurant = vi.fn();
const mockFetchRestaurantItems = vi.fn();
vi.mock('../../../../../../../lib/restaurants', () => ({
  fetchRestaurant: (slug: string, opts: unknown) => mockFetchRestaurant(slug, opts),
  fetchRestaurantItems: (slug: string, opts: unknown) => mockFetchRestaurantItems(slug, opts),
}));

vi.mock('../../../../../../../lib/edge-headers', () => ({
  edgeHeaders: async () => ({}),
}));

const mockGetServerJwt = vi.fn();
vi.mock('../../../../../../../lib/server-auth', () => ({
  getServerJwt: () => mockGetServerJwt(),
}));

const mockNotFound = vi.fn((): never => {
  throw new Error('NEXT_NOT_FOUND');
});
const mockPermanentRedirect = vi.fn((_target: string): never => {
  throw new Error('NEXT_REDIRECT');
});
vi.mock('next/navigation', () => ({
  notFound: () => mockNotFound(),
  permanentRedirect: (target: string) => mockPermanentRedirect(target),
}));

import RestaurantPage from '../page';

beforeEach(() => {
  mockFetchRestaurant.mockReset();
  mockFetchRestaurantItems.mockReset().mockResolvedValue({
    restaurant_id: 'r-1',
    filter: {
      source: 'none',
      preset_slug: null,
      strictness: 'balanced',
      avoid_ingredient_ids: [],
      avoid_tag_ids: [],
    },
    items: [],
  });
  mockGetServerJwt.mockReset().mockResolvedValue(null);
  mockNotFound.mockClear();
  mockPermanentRedirect.mockClear();
});

function run(
  params: { country: string; region: string; city: string; slug: string },
  search: Record<string, string | string[] | undefined> = {},
) {
  return RestaurantPage({
    params: Promise.resolve(params),
    searchParams: Promise.resolve(search),
  });
}

describe('RestaurantPage — canonical redirect on a location mismatch', () => {
  it('301s to the real web_path, preserving the query string, when the URL segments are stale', async () => {
    mockFetchRestaurant.mockResolvedValue({
      web_path: '/restaurants/usa/colorado/durango/rgp-s-wraps',
    });
    await expect(
      run(
        { country: 'usa', region: 'colorado', city: 'silverton', slug: 'rgp-s-wraps' },
        { profile: 'vegan' },
      ),
    ).rejects.toThrow('NEXT_REDIRECT');
    expect(mockPermanentRedirect).toHaveBeenCalledWith(
      '/restaurants/usa/colorado/durango/rgp-s-wraps?profile=vegan',
    );
  });

  it('does not redirect when the URL segments already match web_path', async () => {
    mockFetchRestaurant.mockResolvedValue({
      web_path: '/restaurants/usa/colorado/durango/rgp-s-wraps',
    });
    await run({ country: 'usa', region: 'colorado', city: 'durango', slug: 'rgp-s-wraps' });
    expect(mockPermanentRedirect).not.toHaveBeenCalled();
  });

  it('404s instead of redirecting when the restaurant fetch fails', async () => {
    mockFetchRestaurant.mockRejectedValue(new Error('404'));
    await expect(
      run({ country: 'usa', region: 'colorado', city: 'silverton', slug: 'some-draft' }),
    ).rejects.toThrow('NEXT_NOT_FOUND');
    expect(mockPermanentRedirect).not.toHaveBeenCalled();
  });
});
