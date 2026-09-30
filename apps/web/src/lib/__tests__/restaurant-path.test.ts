import { describe, expect, it } from 'vitest';
import { isCanonicalPath, restaurantBasePath } from '../restaurant-path';

/**
 * The canonical check runs on every restaurant, dish and scan page; a
 * false "not canonical" on the canonical URL is a redirect loop.
 */
const WEB_PATH = '/restaurants/usa/utah/salt-lake-city/a%20b%3F';

describe('isCanonicalPath', () => {
  it('matches an encoded web_path against decoded or encoded params', () => {
    const base = { country: 'usa', region: 'utah', city: 'salt-lake-city' };
    expect(isCanonicalPath(WEB_PATH, { ...base, slug: 'a b?' })).toBe(true);
    expect(isCanonicalPath(WEB_PATH, { ...base, slug: 'a%20b%3F' })).toBe(true);
  });

  it('rejects a stale location', () => {
    expect(
      isCanonicalPath(WEB_PATH, {
        country: 'usa',
        region: 'colorado',
        city: 'durango',
        slug: 'a b?',
      }),
    ).toBe(false);
  });
});

describe('restaurantBasePath', () => {
  // Params can arrive either way; the link must come out the same and
  // never double-encoded.
  it('encodes decoded params and leaves encoded ones alone', () => {
    const base = { country: 'usa', region: 'utah', city: 'salt-lake-city' };
    expect(restaurantBasePath({ ...base, slug: 'a b?' })).toBe(WEB_PATH);
    expect(restaurantBasePath({ ...base, slug: 'a%20b%3F' })).toBe(WEB_PATH);
  });
});
