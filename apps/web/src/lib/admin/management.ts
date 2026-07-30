/**
 * Restaurant / item / user management fetchers (the last Avo-parity
 * surface). Slug and confidence are immutable server-side; this layer
 * never sends them.
 */
import type { paths } from '@biteworthy/api-types';
import { getAdminJson, patchAdminJson } from './shared';

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
  query: { q?: string; status?: string; community?: boolean; limit?: number; offset?: number } = {},
  fetchImpl?: typeof fetch,
): Promise<AdminRestaurantsResponse> {
  const params = new URLSearchParams();
  if (query.q) params.set('q', query.q);
  if (query.status) params.set('status', query.status);
  if (query.community) params.set('filter', 'community_published');
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
  body: { name?: string; about?: string; website?: string; phone?: string; status?: string },
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

export function updateAdminItem(
  id: string,
  body: { name?: string; description?: string; status?: string },
  fetchImpl?: typeof fetch,
): Promise<AdminItemRow> {
  return patchAdminJson(`/api/admin/items/${encodeURIComponent(id)}`, body, fetchImpl);
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
  return patchAdminJson(`/api/admin/users/${encodeURIComponent(id)}`, { is_admin: isAdmin }, fetchImpl);
}
