import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Location-based URLs — old flat item URL `/restaurants/<slug>/items/<id>`.
 * `region` must be the literal `items`; a successful fetch 301s to
 * `<web_path>/items/<id>` (query string preserved), anything else 404s.
 */

const mockFetchRestaurant = vi.fn();
vi.mock('../../../../../../lib/restaurants', () => ({
  fetchRestaurant: (slug: string, opts: unknown) => mockFetchRestaurant(slug, opts),
}));

vi.mock('../../../../../../lib/edge-headers', () => ({
  edgeHeaders: async () => ({}),
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

import OldRestaurantItemUrl from '../page';

beforeEach(() => {
  mockFetchRestaurant.mockReset();
  mockNotFound.mockClear();
  mockPermanentRedirect.mockClear();
});

function run(
  country: string,
  region: string,
  city: string,
  search: Record<string, string | string[] | undefined> = {},
) {
  return OldRestaurantItemUrl({
    params: Promise.resolve({ country, region, city }),
    searchParams: Promise.resolve(search),
  });
}

describe('OldRestaurantItemUrl (/restaurants/[country]/[region]/[city])', () => {
  it('404s when region is not "items"', async () => {
    await expect(run('rgp-s-wraps', 'scan', 'item-1')).rejects.toThrow('NEXT_NOT_FOUND');
    expect(mockFetchRestaurant).not.toHaveBeenCalled();
  });

  it('301s to <web_path>/items/<id>, preserving the query string', async () => {
    mockFetchRestaurant.mockResolvedValue({
      web_path: '/restaurants/usa/colorado/durango/rgp-s-wraps',
    });
    await expect(run('rgp-s-wraps', 'items', 'item-1', { profile: 'vegan' })).rejects.toThrow(
      'NEXT_REDIRECT',
    );
    expect(mockPermanentRedirect).toHaveBeenCalledWith(
      '/restaurants/usa/colorado/durango/rgp-s-wraps/items/item-1?profile=vegan',
    );
  });

  it('404s when the restaurant cannot be fetched', async () => {
    mockFetchRestaurant.mockRejectedValue(new Error('404'));
    await expect(run('some-draft', 'items', 'item-1')).rejects.toThrow('NEXT_NOT_FOUND');
    expect(mockPermanentRedirect).not.toHaveBeenCalled();
  });
});
