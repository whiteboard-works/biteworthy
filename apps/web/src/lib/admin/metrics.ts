/**
 * Ops-dashboard fetcher. The payload type comes from the generated
 * OpenAPI types (rswag spec → docs/openapi.json → api-types), so the
 * web build breaks loudly if the contract drifts. Latency fields are
 * nullable (no runs in the window yet) — renderers must handle null.
 */
import type { paths } from '@biteworthy/api-types';
import { getAdminJson } from './shared';

export type AdminDashboardPayload =
  paths['/api/v1/admin/dashboard']['get']['responses']['200']['content']['application/json'];
export type DashboardBucket = AdminDashboardPayload['periods']['today'];

export function fetchDashboard(fetchImpl?: typeof fetch): Promise<AdminDashboardPayload> {
  return getAdminJson<AdminDashboardPayload>('/api/admin/dashboard', fetchImpl);
}
