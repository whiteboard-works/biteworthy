/**
 * Phase 3.6 — restaurant + filtered-items fetchers (web mirror).
 *
 * Same surface as the mobile client at apps/mobile/lib/api/restaurants.ts
 * but uses the existing `api()` helper from src/lib/api.ts so the web
 * app's API_BASE env var is honored. Server-callable for SSR.
 *
 * Types stay co-located with the fetchers (rather than in
 * @biteworthy/api-types) until the items endpoint gets its own rswag
 * spec — for now, hand-written + spec-locked is the same pattern the
 * mobile side uses.
 */

import { api } from './api';

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

export type Strictness = 'relaxed' | 'balanced' | 'strict';

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
  items: FilteredItem[];
}

export interface FetchOptions {
  fetchImpl?: typeof fetch;
}

export interface FetchItemsOptions extends FetchOptions {
  jwt?: string;
  presetSlug?: string;
  strictness?: Strictness;
}

export async function fetchRestaurant(
  slugOrId: string,
  opts: FetchOptions = {},
): Promise<Restaurant> {
  return api<Restaurant>(`/restaurants/${encodeURIComponent(slugOrId)}`, {
    fetchImpl: opts.fetchImpl,
  });
}

export async function fetchRestaurantItems(
  slugOrId: string,
  opts: FetchItemsOptions = {},
): Promise<RestaurantItemsResponse> {
  const params = new URLSearchParams();
  if (opts.presetSlug) params.set('profile', opts.presetSlug);
  if (opts.strictness) params.set('strictness', opts.strictness);
  const qs = params.toString();
  const path = `/restaurants/${encodeURIComponent(slugOrId)}/items${qs ? `?${qs}` : ''}`;
  const headers: Record<string, string> = {};
  if (opts.jwt) headers.Authorization = `Bearer ${opts.jwt}`;
  return api<RestaurantItemsResponse>(path, { headers, fetchImpl: opts.fetchImpl });
}

/**
 * Group filtered items by their menu section. Same shape as the
 * mobile helper — kept duplicated rather than extracted because the
 * surface is small and consolidating into a shared package is its
 * own followup (mobile lives outside the pnpm workspace's TS-import
 * graph in some configurations).
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
