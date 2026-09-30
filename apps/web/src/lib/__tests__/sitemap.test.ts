import { describe, expect, it } from 'vitest';
import { buildSitemapEntries } from '../sitemap';

const FROZEN = new Date('2026-04-30T19:00:00Z');

describe('buildSitemapEntries', () => {
  it('emits the static routes with sensible priorities', () => {
    const entries = buildSitemapEntries('https://bite-worthy.com', {}, FROZEN);

    const urls = entries.map((e) => e.url);
    expect(urls).toEqual([
      'https://bite-worthy.com/',
      'https://bite-worthy.com/restaurants',
      'https://bite-worthy.com/durango',
      'https://bite-worthy.com/story',
      'https://bite-worthy.com/updates',
      'https://bite-worthy.com/login',
      'https://bite-worthy.com/signup',
    ]);

    const home = entries[0]!;
    expect(home.priority).toBe(1.0);
    expect(home.changeFrequency).toBe('weekly');
    expect(home.lastModified).toBe(FROZEN.toISOString());
  });

  it('appends Phase 5.6 diet pages when dietSlugs is provided', () => {
    const entries = buildSitemapEntries(
      'https://bite-worthy.com',
      { dietSlugs: ['celiac', 'vegan'] },
      FROZEN,
    );
    const dietUrls = entries.map((e) => e.url).filter((u) => u.includes('/durango/'));
    expect(dietUrls).toEqual([
      'https://bite-worthy.com/durango/celiac',
      'https://bite-worthy.com/durango/vegan',
    ]);
  });

  it('appends restaurant web_paths verbatim', () => {
    const entries = buildSitemapEntries(
      'https://bite-worthy.com',
      { restaurantPaths: ['/restaurants/usa/colorado/durango/ninis'] },
      FROZEN,
    );
    expect(entries.at(-1)!.url).toBe(
      'https://bite-worthy.com/restaurants/usa/colorado/durango/ninis',
    );
  });

  it('strips trailing slashes from the base URL', () => {
    const entries = buildSitemapEntries('https://bite-worthy.com////', {}, FROZEN);
    expect(entries[0]!.url).toBe('https://bite-worthy.com/');
  });

  it('combines diet + restaurant extensions in order: static → diets → restaurants', () => {
    const entries = buildSitemapEntries(
      'https://bite-worthy.com',
      { dietSlugs: ['vegan'], restaurantPaths: ['/restaurants/usa/colorado/durango/ninis'] },
      FROZEN,
    );
    expect(entries.map((e) => e.url)).toEqual([
      'https://bite-worthy.com/',
      'https://bite-worthy.com/restaurants',
      'https://bite-worthy.com/durango',
      'https://bite-worthy.com/story',
      'https://bite-worthy.com/updates',
      'https://bite-worthy.com/login',
      'https://bite-worthy.com/signup',
      'https://bite-worthy.com/durango/vegan',
      'https://bite-worthy.com/restaurants/usa/colorado/durango/ninis',
    ]);
  });
});
