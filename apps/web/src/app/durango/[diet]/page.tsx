/**
 * Phase 5.6 — SEO landing for `<diet> restaurants in Durango`.
 *
 * Pure SSR (no client islands). Indexable. The metadata block uses
 * the diet slug to compose a deterministic title + description that
 * Google can use as the SERP snippet.
 *
 * 404 path: an unknown diet slug 404s the page via Next's
 * `notFound()` — the upstream API returns 404 for an unknown
 * `profile` slug, so we propagate. Same for an empty city. The diet
 * list in `lib/durango.ts` mirrors `db/seeds/dietary_profiles.yml`
 * but a stale slug here just shows 404 instead of a stale grid —
 * that's the right failure mode.
 */

import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import { notFound } from 'next/navigation';
import {
  DURANGO_DIET_SLUGS,
  type DurangoDietSlug,
  CityRankingError,
  fetchCityRanking,
  type CityRanked,
} from '../../../lib/durango';

interface Params {
  diet: string;
}

interface PageProps {
  params: Promise<Params>;
}

export async function generateStaticParams(): Promise<Params[]> {
  // Pre-render every curated diet at build time so the SEO pages
  // don't pay an SSR penalty on first crawl. Dynamic-route fallback
  // still kicks in for diets we ship between builds.
  return DURANGO_DIET_SLUGS.map((diet) => ({ diet }));
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { diet } = await params;
  if (!isCuratedDiet(diet)) {
    return { title: 'Not found — BiteWorthy', robots: { index: false } };
  }
  const dietName = humanizeDietSlug(diet);
  const title = `${dietName} restaurants in Durango — BiteWorthy`;
  const description = `Find Durango restaurants ranked by how many menu items pass a ${dietName.toLowerCase()} filter. Built for celiac, allergies, vegan, and every other dietary need.`;
  return {
    title,
    description,
    alternates: { canonical: `/durango/${diet}` },
    openGraph: { title, description, type: 'website', url: `/durango/${diet}` },
    twitter: { card: 'summary_large_image', title, description },
  };
}

export default async function DurangoDietPage({ params }: PageProps): Promise<ReactElement> {
  const { diet } = await params;
  if (!isCuratedDiet(diet)) notFound();

  let ranking: CityRanked;
  try {
    ranking = await fetchCityRanking('durango', diet);
  } catch (e) {
    if (e instanceof CityRankingError && e.status === 404) notFound();
    throw e;
  }

  const visibleSlugs = ranking.restaurants.filter((r) => r.visible_count > 0);
  const allHiddenSlugs = ranking.restaurants.filter((r) => r.visible_count === 0);

  return (
    <main className="bg-white">
      <Hero
        dietName={ranking.profile.name}
        totalRestaurants={ranking.restaurants.length}
        visibleRestaurants={visibleSlugs.length}
      />

      {ranking.restaurants.length === 0 ? (
        <EmptyState />
      ) : (
        <RestaurantGrid
          ranked={ranking.restaurants}
          dietName={ranking.profile.name}
          visibleSlugs={visibleSlugs}
          allHiddenSlugs={allHiddenSlugs}
        />
      )}
    </main>
  );
}

function Hero({
  dietName,
  totalRestaurants,
  visibleRestaurants,
}: {
  dietName: string;
  totalRestaurants: number;
  visibleRestaurants: number;
}): ReactElement {
  return (
    <section className="mx-auto max-w-4xl px-bw-6 pt-bw-16 pb-bw-12">
      <p className="text-bite text-bw-sm font-bold uppercase tracking-[0.2em]">
        Durango, Colorado
      </p>
      <h1 className="mt-bw-3 text-bw-3xl font-bold leading-tight text-zinc-900 md:text-bw-4xl">
        {dietName} restaurants in Durango
      </h1>
      <p className="mt-bw-4 max-w-2xl text-bw-base text-zinc-700">
        {totalRestaurants === 0
          ? `We're seeding Durango restaurants now — check back soon.`
          : `${visibleRestaurants} of ${totalRestaurants} restaurants in our index have at least one ${dietName.toLowerCase()}-safe menu item. Ranked by how many items pass the filter.`}
      </p>
    </section>
  );
}

function RestaurantGrid({
  ranked,
  dietName,
  visibleSlugs,
  allHiddenSlugs,
}: {
  ranked: CityRanked['restaurants'];
  dietName: string;
  visibleSlugs: CityRanked['restaurants'];
  allHiddenSlugs: CityRanked['restaurants'];
}): ReactElement {
  // Mark unused for clarity; consumers may want them in future.
  void ranked;
  return (
    <section className="mx-auto max-w-4xl px-bw-6 pb-bw-16">
      {visibleSlugs.length > 0 && (
        <ul className="mt-bw-4 grid gap-bw-3 md:grid-cols-2">
          {visibleSlugs.map((r) => (
            <RestaurantCard key={r.id} r={r} dietName={dietName} />
          ))}
        </ul>
      )}

      {allHiddenSlugs.length > 0 && (
        <details className="mt-bw-8" data-testid="all-hidden">
          <summary className="cursor-pointer text-bw-sm font-semibold text-bite hover:text-bite-dark">
            Show {allHiddenSlugs.length} restaurant{allHiddenSlugs.length === 1 ? '' : 's'} with no
            {' '}
            {dietName.toLowerCase()}-safe items
          </summary>
          <ul className="mt-bw-3 grid gap-bw-3 md:grid-cols-2">
            {allHiddenSlugs.map((r) => (
              <RestaurantCard key={r.id} r={r} dietName={dietName} />
            ))}
          </ul>
        </details>
      )}
    </section>
  );
}

function RestaurantCard({
  r,
  dietName,
}: {
  r: CityRanked['restaurants'][number];
  dietName: string;
}): ReactElement {
  const allHidden = r.visible_count === 0;
  return (
    <li
      data-testid={`restaurant-${r.slug}`}
      className={[
        'rounded-bw-lg border p-bw-4',
        allHidden ? 'border-zinc-200 bg-zinc-50' : 'border-zinc-200 bg-white shadow-sm',
      ].join(' ')}
    >
      <a
        href={`/restaurants/${encodeURIComponent(r.slug)}`}
        className="block"
        data-testid={`restaurant-link-${r.slug}`}
      >
        <h2 className={['text-bw-lg font-bold', allHidden ? 'text-zinc-500' : 'text-zinc-900'].join(' ')}>
          {r.name}
        </h2>
        <p className="mt-bw-1 text-bw-sm text-zinc-600">
          {allHidden ? (
            <>No {dietName.toLowerCase()}-safe items in our index yet.</>
          ) : (
            <>
              <span className="font-semibold text-zinc-900">{r.visible_count}</span> safe item
              {r.visible_count === 1 ? '' : 's'}
              {' '}
              <span className="text-zinc-500">
                · {r.hidden_count} hidden by your filter
              </span>
            </>
          )}
        </p>
      </a>
    </li>
  );
}

function EmptyState(): ReactElement {
  return (
    <section className="mx-auto max-w-3xl px-bw-6 pb-bw-16 text-center">
      <p className="text-bw-base text-zinc-600">
        We&rsquo;re seeding the Durango launch with 30 independent restaurants now.
      </p>
      <a
        href="/onboarding"
        className="mt-bw-6 inline-block rounded-bw-md bg-bite px-bw-6 py-bw-3 text-bw-base font-bold text-white shadow-sm hover:bg-bite-dark"
      >
        Set up your filter while you wait →
      </a>
    </section>
  );
}

function isCuratedDiet(diet: string): diet is DurangoDietSlug {
  return (DURANGO_DIET_SLUGS as readonly string[]).includes(diet);
}

function humanizeDietSlug(slug: string): string {
  return slug
    .split('-')
    .map((p) => (p.length > 0 ? p[0]!.toUpperCase() + p.slice(1) : p))
    .join(' ');
}
