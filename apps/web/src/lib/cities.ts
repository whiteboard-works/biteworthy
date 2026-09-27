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
import { NotSignedInError } from './chat';

export type City =
  paths['/api/v1/cities']['get']['responses']['200']['content']['application/json']['cities'][number];

/**
 * Server-side, uncached: pass `edgeHeaders()` so Rails throttles the
 * visitor rather than the Next server's shared bucket.
 */
export async function fetchCities(
  opts: { fetchImpl?: typeof fetch; edgeHeaders?: Record<string, string> } = {},
): Promise<City[]> {
  const body = await api<{ cities: City[] }>('/cities', {
    fetchImpl: opts.fetchImpl,
    headers: opts.edgeHeaders,
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
  /** null for someone else's draft, which comes back as a name only. */
  id: string | null;
  slug: string | null;
  name: string;
  status: string;
  street: string | null;
  /** Whether the scan door would accept this caller for this restaurant. */
  scannable: boolean;
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
  if (res.status === 401) throw new NotSignedInError();
  if (!res.ok) throw new Error(`createRestaurant failed: ${res.status}`);
  const body = (await res.json()) as { slug: string };
  return { kind: 'created', slug: body.slug };
}
