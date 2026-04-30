/**
 * Phase 3.3 + 3.4 + 3.7 — restaurant + filtered-items fetchers (mobile).
 *
 * Wire-format types live in `@biteworthy/filter-engine` (the single
 * source of truth as of Phase 3.7). This module just adds the
 * fetchers + the mobile-specific Restaurant header type.
 */

import type {
  FilterableItem,
  FilteredItem,
  HideReason,
  ItemSection,
  Strictness,
} from '@biteworthy/filter-engine';

export type {
  FilteredItem,
  HideReason,
  ItemSection,
  Strictness,
} from '@biteworthy/filter-engine';

const API_BASE = process.env.EXPO_PUBLIC_API_BASE ?? 'http://localhost:3000';

export interface FetchOptions {
  fetchImpl?: typeof fetch;
}

export interface RestaurantCity {
  id: string;
  slug: string;
  name: string;
  region: string;
}

export interface Restaurant {
  id: string;
  slug: string;
  name: string;
  about: string | null;
  phone: string | null;
  website: string | null;
  status: string;
  city: RestaurantCity;
}

export type ItemStatus = 'visible' | 'hidden';

export interface RestaurantItem extends FilterableItem {
  restaurant_id: string;
  name: string;
  description: string;
  popularity: number;
  status: ItemStatus;
  reasons: HideReason[];
}

export interface FilterSummary {
  source: 'preset' | 'user_profile' | 'none';
  preset_slug: string | null;
  strictness: Strictness;
  avoid_ingredient_ids: string[];
  avoid_tag_ids: string[];
}

export interface RestaurantItemsResponse {
  restaurant_id: string;
  filter: FilterSummary;
  items: RestaurantItem[];
}

export class RestaurantFetchError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'RestaurantFetchError';
  }
}

export async function fetchRestaurant(
  id: string,
  opts: FetchOptions = {},
): Promise<Restaurant> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`${API_BASE}/api/v1/restaurants/${id}`);
  if (!res.ok) throw new RestaurantFetchError(res.status, `fetchRestaurant ${id} failed: ${res.status}`);
  return (await res.json()) as Restaurant;
}

export interface FetchItemsOptions extends FetchOptions {
  jwt?: string;
  presetSlug?: string;
  strictness?: 'relaxed' | 'balanced' | 'strict';
}

export async function fetchRestaurantItems(
  id: string,
  opts: FetchItemsOptions = {},
): Promise<RestaurantItemsResponse> {
  const { fetchImpl = fetch, jwt, presetSlug, strictness } = opts;
  const url = new URL(`${API_BASE}/api/v1/restaurants/${id}/items`);
  if (presetSlug) url.searchParams.set('profile', presetSlug);
  if (strictness) url.searchParams.set('strictness', strictness);

  const headers: Record<string, string> = {};
  if (jwt) headers.Authorization = `Bearer ${jwt}`;

  const res = await fetchImpl(url.toString(), { headers });
  if (!res.ok) throw new RestaurantFetchError(res.status, `fetchRestaurantItems ${id} failed: ${res.status}`);
  return (await res.json()) as RestaurantItemsResponse;
}

// Re-export from filter-engine so mobile callers don't need a second import.
export { groupItemsBySection } from '@biteworthy/filter-engine';
