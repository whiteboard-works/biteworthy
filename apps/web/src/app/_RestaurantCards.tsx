'use client';

import Link from 'next/link';
import type { Route } from 'next';
import type { ReactElement } from 'react';
import type { RestaurantSummary } from '../lib/restaurants';
import { getOpenStatus } from '../lib/hours';

/**
 * Presentational grid of restaurant cards linking to each restaurant's
 * filtered menu page. Shared by the homepage "browse" section and the
 * /restaurants index — both fetch server-side and pass the summaries in.
 */
export function RestaurantCards({
  restaurants,
}: {
  restaurants: RestaurantSummary[];
}): ReactElement {
  return (
    <ul className="grid gap-bw-4 sm:grid-cols-2 lg:grid-cols-3">
      {restaurants.map((r) => {
        // Compute open status client-side to avoid ISR cache issues
        const openStatus =
          r.hours && r.hours.length > 0 ? getOpenStatus(r.hours, r.time_zone) : null;

        return (
          <li key={r.id}>
            <Link
              href={r.web_path as Route}
              data-testid={`restaurant-card-${r.slug}`}
              className="flex h-full flex-col rounded-bw-lg border border-zinc-200 bg-white p-bw-5 shadow-sm transition hover:border-bite hover:shadow-md"
            >
              <div className="flex items-start justify-between gap-bw-2">
                <p className="text-bw-lg font-bold text-zinc-900">{r.name}</p>
                {openStatus && (
                  <span
                    className={`shrink-0 rounded-bw-md px-bw-2 py-bw-1 text-bw-xs font-semibold ${
                      openStatus.isOpen
                        ? 'bg-green-100 text-green-800'
                        : 'bg-zinc-100 text-zinc-600'
                    }`}
                    data-testid={`open-badge-${r.slug}`}
                  >
                    {openStatus.isOpen ? 'Open' : 'Closed'}
                  </span>
                )}
              </div>
              <p className="mt-bw-1 text-bw-sm text-zinc-500">
                {r.city.name}
                {r.city.region ? `, ${r.city.region}` : ''}
              </p>
              <p className="mt-bw-4 text-bw-sm font-bold text-bite">See what you can eat →</p>
            </Link>
          </li>
        );
      })}
    </ul>
  );
}
