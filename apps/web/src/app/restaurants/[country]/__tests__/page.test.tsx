import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Location-based URLs — old flat restaurant URL `/restaurants/<slug>`.
 * Handled at the shallow `[country]` level of the new
 * `/restaurants/[country]/[region]/[city]/[slug]` tree (Next routes any
 * 1-segment path here since the real restaurant page is 4 segments
 * deep). Must 301 to the fetched restaurant's `web_path`, carrying the
 * query string, and 404 when the restaurant can't be fetched at all.
 */

const mockFetchRestaurant = vi.fn();
vi.mock('../../../../lib/restaurants', () => ({
  fetchRestaurant: (slug: string, opts: unknown) => mockFetchRestaurant(slug, opts),
}));

vi.mock('../../../../lib/edge-headers', () => ({
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

import OldRestaurantUrl from '../page';

beforeEach(() => {
  mockFetchRestaurant.mockReset();
  mockNotFound.mockClear();
  mockPermanentRedirect.mockClear();
});

function run(country: string, search: Record<string, string | string[] | undefined> = {}) {
  return OldRestaurantUrl({
    params: Promise.resolve({ country }),
    searchParams: Promise.resolve(search),
  });
}

describe('OldRestaurantUrl (/restaurants/[country])', () => {
  it('301s to the canonical web_path, preserving the query string', async () => {
    mockFetchRestaurant.mockResolvedValue({
      web_path: '/restaurants/usa/colorado/durango/rgp-s-wraps',
    });
    await expect(run('rgp-s-wraps', { p: 'tok123' })).rejects.toThrow('NEXT_REDIRECT');
    expect(mockPermanentRedirect).toHaveBeenCalledWith(
      '/restaurants/usa/colorado/durango/rgp-s-wraps?p=tok123',
    );
  });

  it('redirects with no query string when none was present', async () => {
    mockFetchRestaurant.mockResolvedValue({
      web_path: '/restaurants/usa/colorado/durango/rgp-s-wraps',
    });
    await expect(run('rgp-s-wraps')).rejects.toThrow('NEXT_REDIRECT');
    expect(mockPermanentRedirect).toHaveBeenCalledWith(
      '/restaurants/usa/colorado/durango/rgp-s-wraps',
    );
  });

  it('404s when the restaurant cannot be fetched (unknown slug or a draft)', async () => {
    mockFetchRestaurant.mockRejectedValue(new Error('404'));
    await expect(run('some-draft')).rejects.toThrow('NEXT_NOT_FOUND');
    expect(mockPermanentRedirect).not.toHaveBeenCalled();
  });
});
