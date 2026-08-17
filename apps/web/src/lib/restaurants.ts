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
  FilterSource,
  HideReason,
  ItemSection,
  Strictness,
  TasteReason,
} from '@biteworthy/filter-engine';
import { api } from './api';

export type {
  FilteredItem,
  HideReason,
  ItemSection,
  Strictness,
  TasteReason,
} from '@biteworthy/filter-engine';

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
  /** Phase 4.9 — set when an owner has verified the claim. */
  claimed_at: string | null;
  claimed_by_user_id: string | null;
  city: RestaurantCity;
  /** Set by GET show when the caller is authed; false anonymously. */
  favorited?: boolean;
}

/** The lighter shape `GET /api/v1/restaurants` returns for browse/discovery. */
export interface RestaurantSummary {
  id: string;
  slug: string;
  name: string;
  status: string;
  city: { slug: string; name: string; region: string };
  street: string | null;
  latitude: number | null;
  longitude: number | null;
}

/**
 * Items endpoint payload. `status` and `reasons` are the server's
 * decision, rendered as received — the client never recomputes them.
 * The server enriches each reason with name + family so a chip is a
 * pure render with no second roundtrip.
 */
export interface RestaurantItem extends FilterableItem {
  restaurant_id: string;
  name: string;
  description: string;
  status: 'visible' | 'hidden';
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
  /**
   * Phase 8.2 — taste ranks, never hides. Null unless the signed-in
   * caller's profile carries taste signals (Phase 8.1 arrays).
   */
  taste_score?: number | null;
  /** Which liked tags/ingredients matched — the "because you like…" line. */
  taste_reasons?: TasteReason[];
  /** Set by GET show when the caller is authed; false anonymously. */
  favorited?: boolean;
  /**
   * Detail (`#show`) payload only — every ingredient/tag association
   * with its provenance, same rows as the `explain_item` MCP tool.
   * `confidence` + `source` are the honest-disclosure columns; the
   * dish page renders them verbatim and never summarizes them away.
   */
  detected_ingredients?: DetectedIngredient[];
  detected_tags?: DetectedAssociation[];
}

/** One ingredient/tag association with the columns strict mode rests on. */
export interface DetectedAssociation {
  slug: string | null;
  name: string | null;
  confidence: 'confirmed' | 'suggested' | 'inferred';
  source: 'human' | 'ai' | 'owner';
}

export interface DetectedIngredient extends DetectedAssociation {
  allergen: boolean;
}

export interface FilterSummary {
  source: FilterSource;
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
  /** Bearer token — pass on the server so `favorited` reflects the caller. */
  jwt?: string;
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
  const headers: Record<string, string> = {};
  if (opts.jwt) headers.Authorization = `Bearer ${opts.jwt}`;
  return api<Restaurant>(`/restaurants/${encodeURIComponent(slugOrId)}`, {
    headers,
    fetchImpl: opts.fetchImpl,
  });
}

/**
 * The published-restaurants list for the homepage + /restaurants browse
 * surfaces. Optional `q` filters by name (server-side ILIKE). Server-side
 * callers can pass a `revalidate` window for ISR caching.
 */
export async function fetchRestaurants(
  opts: FetchOptions & { q?: string; revalidate?: number } = {},
): Promise<RestaurantSummary[]> {
  const qs = opts.q ? `?q=${encodeURIComponent(opts.q)}` : '';
  const init =
    opts.revalidate !== undefined ? { next: { revalidate: opts.revalidate } } : {};
  const body = await api<{ restaurants: RestaurantSummary[] }>(`/restaurants${qs}`, {
    fetchImpl: opts.fetchImpl,
    ...init,
  });
  return body.restaurants;
}

/** Phase 4.5 — fetch a single item by id under a restaurant. */
export async function fetchItem(
  restaurantSlugOrId: string,
  itemId: string,
  opts: FetchOptions = {},
): Promise<RestaurantItem> {
  const headers: Record<string, string> = {};
  if (opts.jwt) headers.Authorization = `Bearer ${opts.jwt}`;
  return api<RestaurantItem>(
    `/restaurants/${encodeURIComponent(restaurantSlugOrId)}/items/${encodeURIComponent(itemId)}`,
    { headers, fetchImpl: opts.fetchImpl },
  );
}

function itemsQuery(opts: FetchItemsOptions): string {
  const params = new URLSearchParams();
  if (opts.profileToken) params.set('profile_token', opts.profileToken);
  if (opts.presetSlug) params.set('profile', opts.presetSlug);
  if (opts.strictness) params.set('strictness', opts.strictness);
  const qs = params.toString();
  return qs ? `?${qs}` : '';
}

/**
 * Server-side only. Pass `jwt` whenever the caller has one — the menu is
 * filtered by who is asking, so omitting it silently returns the anonymous
 * menu (`filter.source === 'none'`, no taste scores, no overrides).
 */
export async function fetchRestaurantItems(
  slugOrId: string,
  opts: FetchItemsOptions = {},
): Promise<RestaurantItemsResponse> {
  const path = `/restaurants/${encodeURIComponent(slugOrId)}/items${itemsQuery(opts)}`;
  const headers: Record<string, string> = {};
  if (opts.jwt) headers.Authorization = `Bearer ${opts.jwt}`;
  return api<RestaurantItemsResponse>(path, { headers, fetchImpl: opts.fetchImpl });
}

/**
 * Browser-side twin, through the Next proxy at `/api/restaurants/:slug/items`.
 *
 * A direct call to Rails from the browser is cross-origin and carries no
 * credential — `bw_session` is HttpOnly and belongs to this origin. So a
 * signed-in reader's refetch has to go through the proxy or it drops their
 * profile, which is what a strictness toggle used to do.
 *
 * Anonymous readers go straight to Rails instead of through the proxy, and
 * that is deliberate rather than an optimization. A proxied call reaches
 * Rails from the Next server's IP, and rack-attack keys its ceiling on
 * `req.ip` — so every proxied caller shares one bucket. Routing the
 * product's highest-volume read through it unconditionally would let
 * ordinary browsing exhaust a limit meant to catch scrapers. The proxy
 * exists to carry a credential; with no credential to carry there is
 * nothing to route through it.
 */
export async function fetchRestaurantItemsClient(
  slug: string,
  opts: Omit<FetchItemsOptions, 'jwt'> & { signedIn?: boolean } = {},
): Promise<RestaurantItemsResponse> {
  const { fetchImpl = fetch, signedIn = false } = opts;
  if (!signedIn) return fetchRestaurantItems(slug, opts);

  const res = await fetchImpl(
    `/api/restaurants/${encodeURIComponent(slug)}/items${itemsQuery(opts)}`,
    { credentials: 'same-origin' },
  );
  if (!res.ok) {
    // The proxy relays with `new NextResponse(body, { status })`, which
    // carries no statusText — so echoing it would render "404 " with
    // nothing after it. The upstream body has the real reason.
    throw new Error(await errorMessage(res));
  }
  return (await res.json()) as RestaurantItemsResponse;
}

/** Upstream's `error` field when it sent one, else a plain status line. */
async function errorMessage(res: Response): Promise<string> {
  try {
    const body = (await res.json()) as { error?: string };
    if (body.error) return body.error;
  } catch {
    // Non-JSON body — fall through to the status.
  }
  return `Request failed (${res.status})`;
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

/**
 * Save/unsave a dish via the Next proxy at /api/items/:id/favorite.
 * `favorite` is true to save, false to unsave; returns the new state.
 */
export async function setItemFavorite(
  itemId: string,
  favorite: boolean,
  opts: { fetchImpl?: typeof fetch } = {},
): Promise<{ item_id: string; favorited: boolean }> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`/api/items/${encodeURIComponent(itemId)}/favorite`, {
    method: favorite ? 'POST' : 'DELETE',
    credentials: 'same-origin',
  });
  if (!res.ok) throw new Error(`setItemFavorite failed: ${res.status}`);
  return (await res.json()) as { item_id: string; favorited: boolean };
}

/** Save/unsave a restaurant via /api/restaurants/:slug/favorite. */
export async function setRestaurantFavorite(
  slug: string,
  favorite: boolean,
  opts: { fetchImpl?: typeof fetch } = {},
): Promise<{ restaurant_id: string; favorited: boolean }> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`/api/restaurants/${encodeURIComponent(slug)}/favorite`, {
    method: favorite ? 'POST' : 'DELETE',
    credentials: 'same-origin',
  });
  if (!res.ok) throw new Error(`setRestaurantFavorite failed: ${res.status}`);
  return (await res.json()) as { restaurant_id: string; favorited: boolean };
}
