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
  /** Phase 4.2 — set by the API when authenticated. */
  overridden_by_user?: boolean;
  /** Phase 4.4 — total review count, populated for both anon + auth. */
  reviews_count?: number;
  /**
   * Phase 4.11.3 — signed `rails_blob_url` for the dish photo cropped
   * out of the source menu page. Null for items extracted before
   * 4.11.2 / for menu items with no inline photo.
   */
  photo_url: string | null;
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

/**
 * Phase 4.2 — POST/DELETE the persistent never-hide override.
 * Idempotent on both ends; returns the new state.
 */
export async function setNeverHide(
  itemId: string,
  jwt: string,
  opts: FetchOptions = {},
): Promise<{ item_id: string; overridden_by_user: boolean }> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`${API_BASE}/api/v1/items/${encodeURIComponent(itemId)}/never_hide`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${jwt}`, Accept: 'application/json' },
  });
  if (!res.ok) throw new RestaurantFetchError(res.status, `setNeverHide ${itemId} failed: ${res.status}`);
  return (await res.json()) as { item_id: string; overridden_by_user: boolean };
}

export async function clearNeverHide(
  itemId: string,
  jwt: string,
  opts: FetchOptions = {},
): Promise<{ item_id: string; overridden_by_user: boolean }> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`${API_BASE}/api/v1/items/${encodeURIComponent(itemId)}/never_hide`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${jwt}`, Accept: 'application/json' },
  });
  if (!res.ok) throw new RestaurantFetchError(res.status, `clearNeverHide ${itemId} failed: ${res.status}`);
  return (await res.json()) as { item_id: string; overridden_by_user: boolean };
}
