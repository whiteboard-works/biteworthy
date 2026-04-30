/**
 * Phase 5.4 — sitemap.xml served at `/sitemap.xml`.
 *
 * Next.js 13+ App Router: this file's default export becomes the
 * sitemap route. Composition lives in `lib/sitemap.ts` so the URL
 * list is unit-testable without touching Next.
 *
 * Hooks (currently empty; populated by future phases):
 *
 *   * `dietSlugs` — Phase 5.6 will fetch active `DietaryProfile`
 *     slugs from the API and pass them through.
 *   * `restaurantSlugs` — Phase 5.7 will fetch published Restaurant
 *     slugs after the seed run.
 *
 * Until both ship, the sitemap covers the static homepage + auth
 * pages; both are valid + indexable on day one.
 */

import type { MetadataRoute } from 'next';
import { buildSitemapEntries } from '../lib/sitemap';
import { DURANGO_DIET_SLUGS } from '../lib/durango';

const DEFAULT_BASE_URL = 'https://bite-worthy.com';

export default function sitemap(): MetadataRoute.Sitemap {
  const baseUrl = process.env.NEXT_PUBLIC_SITE_URL ?? DEFAULT_BASE_URL;
  return buildSitemapEntries(baseUrl, {
    // Phase 5.6 — every curated diet slug becomes /durango/[diet].
    // Phase 5.7 will populate restaurantSlugs once the seed run lands.
    dietSlugs: [...DURANGO_DIET_SLUGS],
  });
}
