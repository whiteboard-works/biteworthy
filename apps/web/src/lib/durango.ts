/**
 * Phase 5.6 — fetcher + curated diet-slug list for the SSR
 * `/durango/[diet]` SEO pages and the sitemap entry hook.
 *
 * The slug list is hard-coded rather than fetched at build time:
 *
 *   * Production sitemap.ts is an async function but Vercel build
 *     workers shouldn't need an HTTP round-trip to the API to emit
 *     a list that changes once a quarter.
 *   * `db/seeds/dietary_profiles.yml` is the source of truth on the
 *     API side; this list mirrors it. When a new preset ships,
 *     update both.
 *   * Mismatch is non-catastrophic: the SSR page renders 404 for an
 *     unknown diet (via Next's `notFound()` from the upstream 404),
 *     so a stale slug here just hides one URL from the sitemap
 *     until the next deploy.
 */

import { API_BASE } from './api-base';

/**
 * Curated dietary-profile slugs Phase 3.1 seeded. Order is the
 * sitemap order (priority is the same for all, so order is just
 * stable URL listing).
 */
// These MUST be exact `dietary_profiles.yml` slugs — the API 404s on an
// unknown profile, which 404s the SEO page. The earlier list drifted
// (tree-nut-free / shellfish-free / lactose-free / low-fodmap were never
// seeded); replaced with the real allergy/intolerance slugs.
export const DURANGO_DIET_SLUGS = [
  'vegan',
  'vegetarian',
  'celiac',
  'pescatarian',
  'gluten-free',
  'dairy-free',
  'tree-nut-allergy',
  'peanut-allergy',
] as const;

export type DurangoDietSlug = (typeof DURANGO_DIET_SLUGS)[number];

/** 'tree-nut-allergy' → 'Tree Nut Allergy' — display names for the curated slugs. */
export function humanizeDietSlug(slug: string): string {
  return slug
    .split('-')
    .map((p) => (p.length > 0 ? p[0]!.toUpperCase() + p.slice(1) : p))
    .join(' ');
}

export interface CityRanked {
  city: { id: string; slug: string; name: string; region: string };
  profile: { id: string; slug: string; name: string; description: string | null };
  restaurants: Array<{
    id: string;
    slug: string;
    name: string;
    visible_count: number;
    hidden_count: number;
    total_count: number;
  }>;
}

export interface FetchOptions {
  fetchImpl?: typeof fetch;
}

export class CityRankingError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
    this.name = 'CityRankingError';
  }
}

export async function fetchCityRanking(
  citySlug: string,
  dietSlug: string,
  opts: FetchOptions = {},
): Promise<CityRanked> {
  const { fetchImpl = fetch } = opts;
  const url = `${API_BASE}/api/v1/cities/${encodeURIComponent(citySlug)}/restaurants?profile=${encodeURIComponent(dietSlug)}`;

  const res = await fetchImpl(url, { headers: { Accept: 'application/json' } });
  if (!res.ok) {
    throw new CityRankingError(res.status, `fetchCityRanking ${citySlug}/${dietSlug} failed: ${res.status}`);
  }
  return (await res.json()) as CityRanked;
}
