import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import { redirect } from 'next/navigation';
import { getServerJwt } from '../../../lib/server-auth';
import { edgeHeaders } from '../../../lib/edge-headers';
import { fetchCities, type City } from '../../../lib/cities';
import { NewRestaurantForm } from './_NewRestaurantForm';

export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: 'Add a restaurant — BiteWorthy',
  robots: { index: false, follow: false },
};

/**
 * /restaurants/new — add a place we don't have, then scan its menu. The
 * restaurant starts as a draft, so it stays off search and city pages
 * until enough of its menu is verified.
 */
export default async function NewRestaurantPage(): Promise<ReactElement> {
  if (!(await getServerJwt())) redirect('/login?next=/restaurants/new');

  let cities: City[] = [];
  let loadFailed = false;
  try {
    cities = await fetchCities({ edgeHeaders: await edgeHeaders() });
  } catch {
    loadFailed = true;
  }

  return (
    <main className="mx-auto max-w-xl px-bw-6 py-bw-12">
      <p className="text-bite text-bw-sm font-bold uppercase tracking-[0.2em]">Add a restaurant</p>
      <h1 className="mt-bw-2 text-bw-3xl font-bold text-zinc-900">Where did you eat?</h1>
      <p className="mt-bw-3 text-bw-base text-zinc-600">
        Add the place, then snap its menu. It stays private until the dishes are checked.
      </p>
      <NewRestaurantForm cities={cities} loadFailed={loadFailed} />
    </main>
  );
}
