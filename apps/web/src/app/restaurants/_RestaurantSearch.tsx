'use client';

import { useState, type ReactElement } from 'react';
import Link from 'next/link';
import type { RestaurantSummary } from '../../lib/restaurants';
import { RestaurantCards } from '../_RestaurantCards';

/**
 * Name search over the SSR-delivered restaurant list, filtered locally.
 *
 * Deliberately NOT wired to the API's `?q=` ILIKE search: an SSR search
 * would route every visitor's query through the Next server's egress IP
 * — the single shared rack-attack bucket `fetchRestaurantItemsClient`'s
 * comment warns about — and give Next's Data Cache an unbounded key per
 * distinct query. The page already ships the full published list (a
 * couple dozen restaurants at most during the Durango beta), so a local
 * substring match is instant, uncacheable-problem-free, and equivalent
 * to the server's name ILIKE. The API's index cap (INDEX_LIMIT, 100)
 * is what makes "full list" true — if the index ever paginates or the
 * restaurant count approaches the cap, this must switch to server
 * search or the filter will confidently deny restaurants it never saw.
 */
export function RestaurantSearch({
  restaurants,
}: {
  restaurants: RestaurantSummary[];
}): ReactElement {
  const [query, setQuery] = useState('');
  const q = query.trim().toLowerCase();
  const matches = q
    ? restaurants.filter(
        (r) => r.name.toLowerCase().includes(q) || r.city.name.toLowerCase().includes(q),
      )
    : restaurants;

  return (
    <>
      <div className="mt-bw-6 max-w-md">
        <input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search restaurants by name"
          aria-label="Search restaurants"
          data-testid="restaurant-search"
          className="w-full rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-base"
        />
      </div>

      {matches.length === 0 ? (
        <div
          className="mt-bw-8 rounded-bw-lg border border-zinc-200 bg-zinc-50 p-bw-6 text-bw-base text-zinc-600"
          data-testid="restaurants-empty"
        >
          {q ? (
            <>
              No restaurants match &ldquo;{query.trim()}&rdquo;.{' '}
              <button
                type="button"
                onClick={() => setQuery('')}
                data-testid="restaurants-clear-search"
                className="font-bold text-bite underline hover:text-bite-dark"
              >
                Clear search
              </button>
            </>
          ) : (
            <>
              No published menus yet.{' '}
              <Link
                href="/chat"
                data-testid="restaurants-empty-chat"
                className="font-bold text-bite underline hover:text-bite-dark"
              >
                Add one from a photo →
              </Link>
            </>
          )}
        </div>
      ) : (
        <div className="mt-bw-8" data-testid="restaurants-list">
          <RestaurantCards restaurants={matches} />
        </div>
      )}
    </>
  );
}
