import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';

/**
 * Location-based URLs — old flat sub-page URL
 * `/restaurants/<slug>/{scan|claim|suggestions}`. A successful fetch 301s
 * to `<web_path>/<sub>` with the query string preserved. `scan` alone
 * falls through to rendering the scan screen directly when the fetch
 * fails — a draft restaurant is invisible to the public show endpoint
 * even for its own creator, so a failed fetch there must not 404 the
 * creator's own scan flow.
 */

const mockFetchRestaurant = vi.fn();
vi.mock('../../../../../lib/restaurants', () => ({
  fetchRestaurant: (slug: string, opts: unknown) => mockFetchRestaurant(slug, opts),
}));

vi.mock('../../../../../lib/edge-headers', () => ({
  edgeHeaders: async () => ({}),
}));

const mockGetServerJwt = vi.fn();
vi.mock('../../../../../lib/server-auth', () => ({
  getServerJwt: () => mockGetServerJwt(),
}));

vi.mock('../[city]/[slug]/scan/_ScanClient', () => ({
  ScanClient: ({ slug, basePath }: { slug: string; basePath: string }) => (
    <p data-testid="scan-client-stub">
      {slug} / {basePath}
    </p>
  ),
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

import OldRestaurantSubPageUrl from '../page';

beforeEach(() => {
  mockFetchRestaurant.mockReset();
  mockGetServerJwt.mockReset().mockResolvedValue(null);
  mockNotFound.mockClear();
  mockPermanentRedirect.mockClear();
  mockRedirect.mockClear();
});

function run(
  country: string,
  region: string,
  search: Record<string, string | string[] | undefined> = {},
) {
  return OldRestaurantSubPageUrl({
    params: Promise.resolve({ country, region }),
    searchParams: Promise.resolve(search),
  });
}

describe('OldRestaurantSubPageUrl (/restaurants/[country]/[region])', () => {
  it('404s when region is not one of scan/claim/suggestions', async () => {
    await expect(run('rgp-s-wraps', 'menu')).rejects.toThrow('NEXT_NOT_FOUND');
    expect(mockFetchRestaurant).not.toHaveBeenCalled();
  });

  it('301s scan to <web_path>/scan, preserving the query string', async () => {
    mockFetchRestaurant.mockResolvedValue({
      web_path: '/restaurants/usa/colorado/durango/rgp-s-wraps',
    });
    await expect(run('rgp-s-wraps', 'scan', { scan: 'run-1' })).rejects.toThrow('NEXT_REDIRECT');
    expect(mockPermanentRedirect).toHaveBeenCalledWith(
      '/restaurants/usa/colorado/durango/rgp-s-wraps/scan?scan=run-1',
    );
  });

  it('301s claim to <web_path>/claim, preserving the query string', async () => {
    mockFetchRestaurant.mockResolvedValue({
      web_path: '/restaurants/usa/colorado/durango/rgp-s-wraps',
    });
    await expect(run('rgp-s-wraps', 'claim', { t: 'token-1' })).rejects.toThrow('NEXT_REDIRECT');
    expect(mockPermanentRedirect).toHaveBeenCalledWith(
      '/restaurants/usa/colorado/durango/rgp-s-wraps/claim?t=token-1',
    );
  });

  it('301s suggestions to <web_path>/suggestions', async () => {
    mockFetchRestaurant.mockResolvedValue({
      web_path: '/restaurants/usa/colorado/durango/rgp-s-wraps',
    });
    await expect(run('rgp-s-wraps', 'suggestions')).rejects.toThrow('NEXT_REDIRECT');
    expect(mockPermanentRedirect).toHaveBeenCalledWith(
      '/restaurants/usa/colorado/durango/rgp-s-wraps/suggestions',
    );
  });

  it('404s claim when the restaurant cannot be fetched', async () => {
    mockFetchRestaurant.mockRejectedValue(new Error('404'));
    await expect(run('some-draft', 'claim')).rejects.toThrow('NEXT_NOT_FOUND');
  });

  it('404s suggestions when the restaurant cannot be fetched', async () => {
    mockFetchRestaurant.mockRejectedValue(new Error('404'));
    await expect(run('some-draft', 'suggestions')).rejects.toThrow('NEXT_NOT_FOUND');
  });

  it('renders the scan screen from the slug alone when a draft restaurant fails the public fetch', async () => {
    mockGetServerJwt.mockResolvedValue('jwt');
    mockFetchRestaurant.mockRejectedValue(new Error('404'));
    const result = await run('some-draft', 'scan');
    render(result);
    expect(screen.getByTestId('scan-client-stub')).toHaveTextContent(
      'some-draft / /restaurants/some-draft',
    );
    expect(mockPermanentRedirect).not.toHaveBeenCalled();
    expect(mockNotFound).not.toHaveBeenCalled();
  });

  // Signing in after picking photos would lose them to a 401.
  it('sends a signed-out visitor to login first, keeping the resume id', async () => {
    mockFetchRestaurant.mockRejectedValue(new Error('404'));
    await expect(run('some-draft', 'scan', { scan: 'run-1' })).rejects.toThrow('NEXT_REDIRECT');
    expect(mockRedirect).toHaveBeenCalledWith(
      `/login?next=${encodeURIComponent('/restaurants/some-draft/scan?scan=run-1')}`,
    );
  });
});
