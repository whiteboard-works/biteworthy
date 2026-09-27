import type { ReactElement } from 'react';
import { edgeHeaders } from '../../../lib/edge-headers';
import { fetchCities, type City } from '../../../lib/cities';
import { CityCreateForm } from './_CityCreateForm';

/**
 * /admin/cities — the cities we cover, and a form to add one. Adding a
 * city publishes nothing by itself; restaurants still need adding and
 * their menus scanning.
 */
export default async function AdminCitiesPage(): Promise<ReactElement> {
  let cities: City[] = [];
  let loadFailed = false;
  try {
    cities = await fetchCities({ edgeHeaders: await edgeHeaders() });
  } catch {
    loadFailed = true;
  }

  return (
    <main data-testid="admin-cities">
      <h1 className="text-bw-2xl font-bold text-zinc-900">Cities</h1>
      <CityCreateForm />
      {loadFailed ? (
        <p className="mt-bw-4 text-bw-sm text-red-700">Could not load cities.</p>
      ) : (
        <ul data-testid="city-list" className="mt-bw-4 divide-y divide-zinc-200 text-bw-sm">
          {cities.map((c) => (
            <li key={c.id} className="flex justify-between py-bw-2">
              <span className="font-semibold text-zinc-900">
                {c.name}, {c.region}
              </span>
              <span className="text-zinc-500">{c.slug}</span>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}
