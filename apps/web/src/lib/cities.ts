/**
 * Cities we cover, and adding restaurants to them.
 *
 * `fetchCities` is the public list (server-side); it includes cities with
 * no published restaurants yet, which is what lets a brand-new city take
 * its first restaurant. `createCity` is admin-only; `createRestaurant` is
 * any signed-in user and goes through the cookie proxy.
 */
import type { paths } from '@biteworthy/api-types';
import { api } from './api';
import { postAdminJson } from './admin/shared';

export type City =
  paths['/api/v1/cities']['get']['responses']['200']['content']['application/json']['cities'][number];

export async function fetchCities(opts: { fetchImpl?: typeof fetch } = {}): Promise<City[]> {
  const body = await api<{ cities: City[] }>('/cities', {
    fetchImpl: opts.fetchImpl,
    cache: 'no-store',
  });
  return body.cities;
}

export async function createCity(
  input: { name: string; region: string },
  fetchImpl: typeof fetch = fetch,
): Promise<City> {
  return postAdminJson<City>('/api/admin/cities', { body: input }, fetchImpl);
}

export interface DuplicateCandidate {
  id: string;
  slug: string;
  name: string;
  status: string;
  street: string | null;
}

export type CreateRestaurantResult =
  { kind: 'created'; slug: string } | { kind: 'duplicate'; candidates: DuplicateCandidate[] };

export async function createRestaurant(
  input: {
    name: string;
    city_slug: string;
    street?: string;
    postal_code?: string;
    force?: boolean;
  },
  fetchImpl: typeof fetch = fetch,
): Promise<CreateRestaurantResult> {
  const res = await fetchImpl('/api/restaurants', {
    method: 'POST',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(input),
  });
  if (res.status === 409) {
    const body = (await res.json()) as { candidates: DuplicateCandidate[] };
    return { kind: 'duplicate', candidates: body.candidates };
  }
  if (!res.ok) throw new Error(`createRestaurant failed: ${res.status}`);
  const body = (await res.json()) as { slug: string };
  return { kind: 'created', slug: body.slug };
}
