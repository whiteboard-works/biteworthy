/**
 * Admin ingestion moderation: the cross-user runs queue plus the two
 * admin-only actions (re-extract, confirm-community). Per-run item
 * review deliberately reuses `lib/ingestion.ts` — the existing verify
 * endpoints are creator-OR-ADMIN gated, so the admin detail page calls
 * the same fetchRun/fetchRunItems/decideRunItem/acceptAllRunItems the
 * verify page uses.
 */
import type { paths } from '@biteworthy/api-types';
import { getAdminJson, postAdminJson } from './shared';

export type AdminRunsResponse =
  paths['/api/v1/admin/ingestion_runs']['get']['responses']['200']['content']['application/json'];
export type AdminRunRow = AdminRunsResponse['runs'][number];

export type ConfirmCommunityResponse =
  paths['/api/v1/admin/restaurants/{id}/confirm_community']['post']['responses']['200']['content']['application/json'];

export interface AdminRunsQuery {
  status?: string;
  /** Show the archived runs instead of the live queue. */
  archived?: boolean;
  community?: boolean;
  restaurantId?: string;
  limit?: number;
  offset?: number;
}

export function fetchAdminRuns(
  query: AdminRunsQuery = {},
  fetchImpl?: typeof fetch,
): Promise<AdminRunsResponse> {
  const params = new URLSearchParams();
  if (query.status) params.set('status', query.status);
  if (query.community) params.set('community', 'true');
  if (query.archived) params.set('archived', 'true');
  if (query.restaurantId) params.set('restaurant_id', query.restaurantId);
  if (query.limit != null) params.set('limit', String(query.limit));
  if (query.offset != null) params.set('offset', String(query.offset));
  const qs = params.toString();
  return getAdminJson<AdminRunsResponse>(
    `/api/admin/ingestion_runs${qs ? `?${qs}` : ''}`,
    fetchImpl,
  );
}

export function reExtractRun(
  runId: string,
  fetchImpl?: typeof fetch,
): Promise<{ id: string; status: string }> {
  return postAdminJson(
    `/api/admin/ingestion_runs/${encodeURIComponent(runId)}/re_extract`,
    {},
    fetchImpl,
  );
}

export function confirmCommunity(
  restaurantId: string,
  fetchImpl?: typeof fetch,
): Promise<ConfirmCommunityResponse> {
  return postAdminJson(
    `/api/admin/restaurants/${encodeURIComponent(restaurantId)}/confirm_community`,
    {},
    fetchImpl,
  );
}
