/**
 * Phase 3.3 — restaurant + filtered-items fetchers.
 *
 * `fetchRestaurant(id)` powers the page header (name + city).
 * `fetchRestaurantItems(id, jwt?)` returns the per-item filter
 * verdict the screen renders. The server applies the filter using
 * `current_user.profile` when a JWT is supplied (per Phase 1.7) so
 * the client never recomputes it.
 *
 * Both endpoints work anonymously — the JWT is optional.
 */

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

export type HideReason =
  | {
      kind: 'avoid_ingredient';
      ingredient_id: string;
      ingredient_name: string | null;
      ingredient_family: string | null;
    }
  | {
      kind: 'avoid_tag';
      tag_id: string;
      tag_name: string | null;
      tag_family: string | null;
    }
  | { kind: 'unconfirmed_strict'; confidence: string };

export interface FilteredItem {
  id: string;
  restaurant_id: string;
  name: string;
  description: string;
  confidence: 'confirmed' | 'suggested' | 'inferred';
  popularity: number;
  ingredient_ids: string[];
  tag_ids: string[];
  menu_section_id: string | null;
  menu_section_name: string | null;
  status: ItemStatus;
  reasons: HideReason[];
}

export interface FilterSummary {
  source: 'preset' | 'user_profile' | 'none';
  preset_slug: string | null;
  strictness: 'relaxed' | 'balanced' | 'strict';
  avoid_ingredient_ids: string[];
  avoid_tag_ids: string[];
}

export interface RestaurantItemsResponse {
  restaurant_id: string;
  filter: FilterSummary;
  items: FilteredItem[];
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
  /** Override the server's chosen profile with a preset slug. */
  presetSlug?: string;
  /** Override the server's chosen strictness for this request. */
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

/**
 * Group filtered items by their menu section. Items with no
 * `menu_section_id` end up in the catch-all "Other" group at the end.
 * Within each section, items are ordered visible-first, hidden-last
 * (the server already orders by popularity); the screen flattens the
 * groups and renders an expander around the hidden tail.
 */
export interface ItemSection {
  id: string | null;
  name: string;
  visible: FilteredItem[];
  hidden: FilteredItem[];
}

export function groupItemsBySection(items: FilteredItem[]): ItemSection[] {
  const order: (string | null)[] = [];
  const lookup = new Map<string | null, ItemSection>();

  for (const item of items) {
    const sectionId = item.menu_section_id;
    let section = lookup.get(sectionId);
    if (!section) {
      section = {
        id: sectionId,
        name: item.menu_section_name ?? 'Other',
        visible: [],
        hidden: [],
      };
      lookup.set(sectionId, section);
      order.push(sectionId);
    }
    if (item.status === 'visible') section.visible.push(item);
    else section.hidden.push(item);
  }

  return order.map((id) => lookup.get(id)!);
}
