/**
 * Phase 3.6 + 3.7 — restaurant + filtered-items fetchers (web).
 *
 * Wire-format types live in `@biteworthy/filter-engine` (the single
 * source of truth). This module just adds the fetchers + the
 * web-specific Restaurant header type.
 */

import type {
  FilterableItem,
  FilteredItem,
  HideReason,
  ItemSection,
  Strictness,
} from '@biteworthy/filter-engine';
import { api } from './api';

export type { FilteredItem, HideReason, ItemSection, Strictness } from '@biteworthy/filter-engine';

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

/**
 * Items endpoint payload. The server enriches reasons with name +
 * family — same shape `applyProfile` from filter-engine produces, so
 * client-side recomputation stays byte-identical.
 */
export interface RestaurantItem extends FilterableItem {
  restaurant_id: string;
  name: string;
  description: string;
  popularity: number;
  status: 'visible' | 'hidden';
  reasons: HideReason[];
  /** Phase 4.2 — set by the API when authenticated. */
  overridden_by_user?: boolean;
  /** Phase 4.4 — total review count, populated for both anon + auth. */
  reviews_count?: number;
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

export interface FetchOptions {
  fetchImpl?: typeof fetch;
}

export interface FetchItemsOptions extends FetchOptions {
  jwt?: string;
  presetSlug?: string;
  strictness?: Strictness;
  /** Phase 3.9 — base64url-encoded shareable profile token. */
  profileToken?: string | null;
}

export async function fetchRestaurant(
  slugOrId: string,
  opts: FetchOptions = {},
): Promise<Restaurant> {
  return api<Restaurant>(`/restaurants/${encodeURIComponent(slugOrId)}`, {
    fetchImpl: opts.fetchImpl,
  });
}

/** Phase 4.5 — fetch a single item by id under a restaurant. */
export async function fetchItem(
  restaurantSlugOrId: string,
  itemId: string,
  opts: FetchOptions = {},
): Promise<RestaurantItem> {
  return api<RestaurantItem>(
    `/restaurants/${encodeURIComponent(restaurantSlugOrId)}/items/${encodeURIComponent(itemId)}`,
    { fetchImpl: opts.fetchImpl },
  );
}

export async function fetchRestaurantItems(
  slugOrId: string,
  opts: FetchItemsOptions = {},
): Promise<RestaurantItemsResponse> {
  const params = new URLSearchParams();
  if (opts.profileToken) params.set('profile_token', opts.profileToken);
  if (opts.presetSlug) params.set('profile', opts.presetSlug);
  if (opts.strictness) params.set('strictness', opts.strictness);
  const qs = params.toString();
  const path = `/restaurants/${encodeURIComponent(slugOrId)}/items${qs ? `?${qs}` : ''}`;
  const headers: Record<string, string> = {};
  if (opts.jwt) headers.Authorization = `Bearer ${opts.jwt}`;
  return api<RestaurantItemsResponse>(path, { headers, fetchImpl: opts.fetchImpl });
}

/**
 * Phase 4.2 — POST/DELETE the persistent never-hide override via the
 * Next proxy at /api/items/:id/never_hide. Returns the new state.
 */
export async function setNeverHide(
  itemId: string,
  opts: { fetchImpl?: typeof fetch } = {},
): Promise<{ item_id: string; overridden_by_user: boolean }> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`/api/items/${encodeURIComponent(itemId)}/never_hide`, {
    method: 'POST',
    credentials: 'same-origin',
  });
  if (!res.ok) throw new Error(`setNeverHide failed: ${res.status}`);
  return (await res.json()) as { item_id: string; overridden_by_user: boolean };
}

export async function clearNeverHide(
  itemId: string,
  opts: { fetchImpl?: typeof fetch } = {},
): Promise<{ item_id: string; overridden_by_user: boolean }> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`/api/items/${encodeURIComponent(itemId)}/never_hide`, {
    method: 'DELETE',
    credentials: 'same-origin',
  });
  if (!res.ok) throw new Error(`clearNeverHide failed: ${res.status}`);
  return (await res.json()) as { item_id: string; overridden_by_user: boolean };
}
