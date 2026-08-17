/**
 * Restaurant / item / user management fetchers (the last Avo-parity
 * surface). Slug and confidence are immutable server-side; this layer
 * never sends them.
 */
import type { paths } from '@biteworthy/api-types';
import { AdminError, getAdminJson, patchAdminJson } from './shared';

export type AdminRestaurantsResponse =
  paths['/api/v1/admin/restaurants']['get']['responses']['200']['content']['application/json'];
export type AdminRestaurantRow = AdminRestaurantsResponse['restaurants'][number];
export type AdminRestaurantDetail =
  paths['/api/v1/admin/restaurants/{id}']['get']['responses']['200']['content']['application/json'];

export type AdminItemsResponse =
  paths['/api/v1/admin/restaurants/{restaurant_id}/items']['get']['responses']['200']['content']['application/json'];
export type AdminItemRow = AdminItemsResponse['items'][number];

export type AdminUsersResponse =
  paths['/api/v1/admin/users']['get']['responses']['200']['content']['application/json'];
export type AdminUserRow = AdminUsersResponse['users'][number];

function qs(params: URLSearchParams): string {
  const s = params.toString();
  return s ? `?${s}` : '';
}

export function fetchAdminRestaurants(
  query: {
    q?: string;
    status?: string;
    community?: boolean;
    archived?: boolean;
    limit?: number;
    offset?: number;
  } = {},
  fetchImpl?: typeof fetch,
): Promise<AdminRestaurantsResponse> {
  const params = new URLSearchParams();
  if (query.q) params.set('q', query.q);
  if (query.status) params.set('status', query.status);
  if (query.community) params.set('filter', 'community_published');
  if (query.archived) params.set('archived', 'true');
  if (query.limit != null) params.set('limit', String(query.limit));
  if (query.offset != null) params.set('offset', String(query.offset));
  return getAdminJson(`/api/admin/restaurants${qs(params)}`, fetchImpl);
}

export function fetchAdminRestaurant(
  id: string,
  fetchImpl?: typeof fetch,
): Promise<AdminRestaurantDetail> {
  return getAdminJson(`/api/admin/restaurants/${encodeURIComponent(id)}`, fetchImpl);
}

export function updateAdminRestaurant(
  id: string,
  // null clears an optional field server-side; sending '' would store
  // an empty string over NULL.
  body: {
    name?: string;
    about?: string | null;
    website?: string | null;
    phone?: string | null;
    status?: string;
  },
  fetchImpl?: typeof fetch,
): Promise<AdminRestaurantDetail> {
  return patchAdminJson(`/api/admin/restaurants/${encodeURIComponent(id)}`, body, fetchImpl);
}

export function fetchAdminRestaurantItems(
  restaurantId: string,
  query: { status?: string; limit?: number; offset?: number } = {},
  fetchImpl?: typeof fetch,
): Promise<AdminItemsResponse> {
  const params = new URLSearchParams();
  if (query.status) params.set('status', query.status);
  if (query.limit != null) params.set('limit', String(query.limit));
  if (query.offset != null) params.set('offset', String(query.offset));
  return getAdminJson(
    `/api/admin/restaurants/${encodeURIComponent(restaurantId)}/items${qs(params)}`,
    fetchImpl,
  );
}

/**
 * Deep-edit a live dish. Absent keys are left alone; an explicit empty
 * array clears that facet. Joins are synced from slug lists and land
 * confirmed/human server-side — `confidence` is deliberately not
 * settable here (it moves only through promote / confirm-community).
 */
export type AdminItemEdits = NonNullable<
  paths['/api/v1/admin/items/{id}']['patch']['requestBody']
>['content']['application/json'];

/** The modifier kinds the server accepts, from the same generated contract. */
export type AdminModifierKind = NonNullable<
  NonNullable<AdminItemEdits['modifiers']>[number]['kind']
>;

export function updateAdminItem(
  id: string,
  body: AdminItemEdits,
  fetchImpl?: typeof fetch,
): Promise<AdminItemRow> {
  return patchAdminJson(`/api/admin/items/${encodeURIComponent(id)}`, body, fetchImpl);
}

/** Human copy for the deep-edit endpoint's structured refusals. */
export function itemEditErrorCopy(err: unknown): string | null {
  if (!(err instanceof AdminError)) return null;
  const body = err.body as { error?: string; slugs?: string[] } | undefined;
  switch (body?.error) {
    case 'unknown_ingredient_slugs':
    case 'unknown_tag_slugs':
      return `Not in the taxonomy: ${(body.slugs ?? []).join(', ')}. Add it under Taxonomy first.`;
    case 'foreign_menu_section':
      return 'That section belongs to a different restaurant.';
    case 'invalid_price_cents':
      return 'Prices must be a plain amount like 8.95.';
    case 'invalid_status':
      return 'Unknown status.';
    default:
      // A rejected write must not fall through to the generic "went
      // wrong loading admin data" copy — this is a save, and the 401/
      // 403/404 cases still want that shared auth wording.
      return err.status === 422
        ? 'The server rejected that edit. Check the fields and retry.'
        : null;
  }
}

export function fetchAdminUsers(
  query: { q?: string; adminOnly?: boolean; limit?: number; offset?: number } = {},
  fetchImpl?: typeof fetch,
): Promise<AdminUsersResponse> {
  const params = new URLSearchParams();
  if (query.q) params.set('q', query.q);
  if (query.adminOnly) params.set('is_admin', 'true');
  if (query.limit != null) params.set('limit', String(query.limit));
  if (query.offset != null) params.set('offset', String(query.offset));
  return getAdminJson(`/api/admin/users${qs(params)}`, fetchImpl);
}

export function setUserAdmin(
  id: string,
  isAdmin: boolean,
  fetchImpl?: typeof fetch,
): Promise<AdminUserRow> {
  return patchAdminJson(
    `/api/admin/users/${encodeURIComponent(id)}`,
    { is_admin: isAdmin },
    fetchImpl,
  );
}

/** Support-fixing a squatted or offensive handle; stored lowercase. */
export function setUserHandle(
  id: string,
  handle: string,
  fetchImpl?: typeof fetch,
): Promise<AdminUserRow> {
  return patchAdminJson(`/api/admin/users/${encodeURIComponent(id)}`, { handle }, fetchImpl);
}
