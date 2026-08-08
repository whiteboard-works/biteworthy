import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import Link from 'next/link';
import { fetchRestaurants, type RestaurantSummary } from '../../lib/restaurants';
import { RestaurantCards } from '../_RestaurantCards';

// ISR: the browse list refreshes every 5 minutes as menus are published.
export const revalidate = 300;

export const metadata: Metadata = {
  title: 'Restaurants — BiteWorthy',
  description:
    'Browse restaurants and see only the dishes you can eat — for allergies, intolerances, and every dietary need, with why.',
};

export default async function RestaurantsPage(): Promise<ReactElement> {
  let restaurants: RestaurantSummary[] = [];
  try {
    restaurants = await fetchRestaurants({ revalidate: 300 });
  } catch {
    // API hiccup — render the empty state rather than 500 the page.
  }

  return (
    <main className="mx-auto max-w-5xl px-bw-6 py-bw-12">
      <p className="text-bite text-bw-sm font-bold uppercase tracking-[0.2em]">Browse</p>
      <h1 className="mt-bw-2 text-bw-3xl font-bold text-zinc-900">Restaurants</h1>
      <p className="mt-bw-3 max-w-2xl text-bw-base text-zinc-600">
        Pick a place — BiteWorthy shows only the dishes that fit your dietary filter, with{' '}
        <span className="font-bold">why</span>, every time.
      </p>

      {restaurants.length === 0 ? (
        <div
          className="mt-bw-8 rounded-bw-lg border border-zinc-200 bg-zinc-50 p-bw-6 text-bw-base text-zinc-600"
          data-testid="restaurants-empty"
        >
          No published menus yet.{' '}
          <Link href="/chat" data-testid="restaurants-empty-chat" className="font-bold text-bite underline hover:text-bite-dark">
            Add one from a photo →
          </Link>
        </div>
      ) : (
        <div className="mt-bw-8" data-testid="restaurants-list">
          <RestaurantCards restaurants={restaurants} />
        </div>
      )}
    </main>
  );
}
