/**
 * Phase 5.4 — sitemap composition.
 *
 * Pure-TS helper so the URL list can be unit-tested without spinning
 * up Next's app router. The route handler at `app/sitemap.ts`
 * calls this with the production base URL + extension hooks
 * (Phase 5.6 will add `/durango/[diet]` rows; Phase 5.7 the
 * seeded-restaurant rows).
 *
 * Returns the same shape Next 13+'s `MetadataRoute.Sitemap` expects.
 */

export type ChangeFreq =
  | 'always'
  | 'hourly'
  | 'daily'
  | 'weekly'
  | 'monthly'
  | 'yearly'
  | 'never';

export interface SitemapEntry {
  url: string;
  lastModified: string | Date;
  changeFrequency?: ChangeFreq;
  priority?: number;
}

export interface SitemapExtension {
  /**
   * Phase 5.6 hook — diet preset slugs (e.g. `'celiac'`, `'vegan'`).
   * Each becomes `/durango/<slug>`. Empty array until 5.6 lands;
   * the call site decides whether to fetch or hard-code.
   */
  dietSlugs?: string[];
  /**
   * Phase 5.7 hook — published restaurant slugs. Each becomes
   * `/restaurants/<slug>`. Empty until the seed run.
   */
  restaurantSlugs?: string[];
}

const STATIC_ROUTES: ReadonlyArray<{
  path: string;
  priority: number;
  changeFrequency: ChangeFreq;
}> = [
  { path: '/', priority: 1.0, changeFrequency: 'weekly' },
  { path: '/login', priority: 0.3, changeFrequency: 'monthly' },
  { path: '/signup', priority: 0.3, changeFrequency: 'monthly' },
];

export function buildSitemapEntries(
  baseUrl: string,
  options: SitemapExtension = {},
  now: Date = new Date(),
): SitemapEntry[] {
  const lastModified = now.toISOString();
  const base = baseUrl.replace(/\/+$/, '');

  const staticEntries: SitemapEntry[] = STATIC_ROUTES.map((r) => ({
    url: `${base}${r.path}`,
    lastModified,
    changeFrequency: r.changeFrequency,
    priority: r.priority,
  }));

  const dietEntries: SitemapEntry[] = (options.dietSlugs ?? []).map((slug) => ({
    url: `${base}/durango/${encodeURIComponent(slug)}`,
    lastModified,
    changeFrequency: 'weekly',
    priority: 0.8,
  }));

  const restaurantEntries: SitemapEntry[] = (options.restaurantSlugs ?? []).map((slug) => ({
    url: `${base}/restaurants/${encodeURIComponent(slug)}`,
    lastModified,
    changeFrequency: 'weekly',
    priority: 0.7,
  }));

  return [...staticEntries, ...dietEntries, ...restaurantEntries];
}
