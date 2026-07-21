import Link from 'next/link';
import type { Route } from 'next';
import type { ReactElement } from 'react';
import type { RestaurantSummary } from '../lib/restaurants';

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
      {restaurants.map((r) => (
        <li key={r.id}>
          <Link
            href={`/restaurants/${r.slug}` as Route}
            data-testid={`restaurant-card-${r.slug}`}
            className="flex h-full flex-col rounded-bw-lg border border-zinc-200 bg-white p-bw-5 shadow-sm transition hover:border-bite hover:shadow-md"
          >
            <p className="text-bw-lg font-bold text-zinc-900">{r.name}</p>
            <p className="mt-bw-1 text-bw-sm text-zinc-500">
              {r.city.name}
              {r.city.region ? `, ${r.city.region}` : ''}
            </p>
            <p className="mt-bw-4 text-bw-sm font-bold text-bite">See what you can eat →</p>
          </Link>
        </li>
      ))}
    </ul>
  );
}
