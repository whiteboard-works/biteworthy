/**
 * Admin cross-restaurant suggestion queue. Accept/reject reuses
 * `decideSuggestion` from lib/suggestions.ts — the existing PATCH
 * endpoint admits admins through gate_owner!.
 */
import type { paths } from '@biteworthy/api-types';
import { getAdminJson } from './shared';

export type AdminSuggestionsResponse =
  paths['/api/v1/admin/suggestions']['get']['responses']['200']['content']['application/json'];
export type AdminSuggestionRow = AdminSuggestionsResponse['suggestions'][number];

export function fetchAdminSuggestions(
  query: { status?: string; restaurantId?: string; limit?: number; offset?: number } = {},
  fetchImpl?: typeof fetch,
): Promise<AdminSuggestionsResponse> {
  const params = new URLSearchParams();
  if (query.status) params.set('status', query.status);
  if (query.restaurantId) params.set('restaurant_id', query.restaurantId);
  if (query.limit != null) params.set('limit', String(query.limit));
  if (query.offset != null) params.set('offset', String(query.offset));
  const qs = params.toString();
  return getAdminJson<AdminSuggestionsResponse>(
    `/api/admin/suggestions${qs ? `?${qs}` : ''}`,
    fetchImpl,
  );
}
