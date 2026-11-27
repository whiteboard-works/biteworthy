import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Location-based URLs — lookup is always by the trailing slug, so a
 * country/region/city segment that doesn't match the restaurant's real
 * location must not silently render — it redirects to the canonical
 * `web_path` (query string preserved). City-only mismatches 307 because
 * city reassignment is reversible; country/region spelling 308s. This
 * only fires once the restaurant has actually been fetched; a failed
 * fetch (a draft, an unknown slug) falls through to notFound() instead.
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
  getServerUserId: () => null,
}));

const mockNotFound = vi.fn((): never => {
  throw new Error('NEXT_NOT_FOUND');
});
const mockPermanentRedirect = vi.fn((_target: string): never => {
  throw new Error('NEXT_REDIRECT');
});
const mockRedirect = vi.fn((_target: string): never => {
  throw new Error('NEXT_REDIRECT');
});
vi.mock('next/navigation', () => ({
  notFound: () => mockNotFound(),
  permanentRedirect: (target: string) => mockPermanentRedirect(target),
  redirect: (target: string) => mockRedirect(target),
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
  mockRedirect.mockClear();
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
  it('307s to the real web_path, preserving the query string, when only the city is stale', async () => {
    mockFetchRestaurant.mockResolvedValue({
      web_path: '/restaurants/usa/colorado/durango/rgp-s-wraps',
    });
    await expect(
      run(
        { country: 'usa', region: 'colorado', city: 'silverton', slug: 'rgp-s-wraps' },
        { profile: 'vegan' },
      ),
    ).rejects.toThrow('NEXT_REDIRECT');
    expect(mockRedirect).toHaveBeenCalledWith(
      '/restaurants/usa/colorado/durango/rgp-s-wraps?profile=vegan',
    );
    expect(mockPermanentRedirect).not.toHaveBeenCalled();
  });

  // WBW-247 — after an admin moves a restaurant Ogden → Draper the slug
  // is unchanged. City assignment is reversible, so the old city path
  // must 307 (not 308) or a reverse move can loop in a cached browser.
  it('307s the old city path to the new one after a restaurant changes city', async () => {
    mockFetchRestaurant.mockResolvedValue({
      web_path: '/restaurants/usa/utah/draper/laan-thai-restaurant',
    });
    await expect(
      run({ country: 'usa', region: 'utah', city: 'ogden', slug: 'laan-thai-restaurant' }),
    ).rejects.toThrow('NEXT_REDIRECT');
    expect(mockRedirect).toHaveBeenCalledWith(
      '/restaurants/usa/utah/draper/laan-thai-restaurant',
    );
    expect(mockPermanentRedirect).not.toHaveBeenCalled();
  });

  it('still 308s when country or region spelling is stale', async () => {
    mockFetchRestaurant.mockResolvedValue({
      web_path: '/restaurants/usa/utah/draper/laan-thai-restaurant',
    });
    await expect(
      run({ country: 'us', region: 'utah', city: 'draper', slug: 'laan-thai-restaurant' }),
    ).rejects.toThrow('NEXT_REDIRECT');
    expect(mockPermanentRedirect).toHaveBeenCalledWith(
      '/restaurants/usa/utah/draper/laan-thai-restaurant',
    );
    expect(mockRedirect).not.toHaveBeenCalled();
  });

  it('does not redirect when the URL segments already match web_path', async () => {
    mockFetchRestaurant.mockResolvedValue({
      web_path: '/restaurants/usa/colorado/durango/rgp-s-wraps',
    });
    await run({ country: 'usa', region: 'colorado', city: 'durango', slug: 'rgp-s-wraps' });
    expect(mockPermanentRedirect).not.toHaveBeenCalled();
    expect(mockRedirect).not.toHaveBeenCalled();
  });

  it('404s instead of redirecting when the restaurant fetch fails', async () => {
    mockFetchRestaurant.mockRejectedValue(new Error('404'));
    await expect(
      run({ country: 'usa', region: 'colorado', city: 'silverton', slug: 'some-draft' }),
    ).rejects.toThrow('NEXT_NOT_FOUND');
    expect(mockPermanentRedirect).not.toHaveBeenCalled();
    expect(mockRedirect).not.toHaveBeenCalled();
  });
});
