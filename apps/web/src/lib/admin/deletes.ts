/**
 * The admin delete surface, in one module for the same reason the
 * server keeps it in one concern (`Api::V1::Admin::Deletable`): the rule
 * is one rule applied to six resources, and splitting it across six
 * domain files would hide that.
 *
 * The rule:
 *
 *   archive*(id)  → the row is hidden, and comes back
 *   destroy*(id)  → the row is gone. Super admins only; anyone else
 *                   gets a 404, which `deleteErrorCopy` translates.
 *
 * Only restaurants and runs archive. Items, reviews and suggestions
 * already had a soft delete before this existed (`status: "removed"`,
 * hide-with-a-reason, reject), so they expose only the destroy half —
 * calling their bare DELETE is a documented 422, not a feature.
 */
import type { paths } from '@biteworthy/api-types';
import { deleteAdminJson, postAdminJson } from './shared';

type DeleteResponse<P extends keyof paths> = paths[P] extends {
  delete: { responses: { 200: { content: { 'application/json': infer R } } } };
}
  ? R
  : never;

export type RestaurantDeleteResult = DeleteResponse<'/api/v1/admin/restaurants/{id}'>;
export type RunDeleteResult = DeleteResponse<'/api/v1/admin/ingestion_runs/{id}'>;

/** `{ id, deleted: true }` — every destroy answers this. */
export type DestroyedResult = { id: string; deleted: boolean };

const path = (resource: string, id: string) => `/api/admin/${resource}/${encodeURIComponent(id)}`;

export function archiveAdminRestaurant(
  id: string,
  fetchImpl?: typeof fetch,
): Promise<RestaurantDeleteResult> {
  return deleteAdminJson(path('restaurants', id), {}, fetchImpl);
}

export function restoreAdminRestaurant(id: string, fetchImpl?: typeof fetch): Promise<unknown> {
  return postAdminJson(`${path('restaurants', id)}/restore`, {}, fetchImpl);
}

export function destroyAdminRestaurant(
  id: string,
  fetchImpl?: typeof fetch,
): Promise<DestroyedResult> {
  return deleteAdminJson(path('restaurants', id), { hard: true }, fetchImpl);
}

export function archiveAdminRun(id: string, fetchImpl?: typeof fetch): Promise<RunDeleteResult> {
  return deleteAdminJson(path('ingestion_runs', id), {}, fetchImpl);
}

export function restoreAdminRun(id: string, fetchImpl?: typeof fetch): Promise<unknown> {
  return postAdminJson(`${path('ingestion_runs', id)}/restore`, {}, fetchImpl);
}

export function destroyAdminRun(id: string, fetchImpl?: typeof fetch): Promise<DestroyedResult> {
  return deleteAdminJson(path('ingestion_runs', id), { hard: true }, fetchImpl);
}

export function destroyAdminItem(id: string, fetchImpl?: typeof fetch): Promise<DestroyedResult> {
  return deleteAdminJson(path('items', id), { hard: true }, fetchImpl);
}

export function destroyAdminReview(id: string, fetchImpl?: typeof fetch): Promise<DestroyedResult> {
  return deleteAdminJson(path('reviews', id), { hard: true }, fetchImpl);
}

export function destroyAdminSuggestion(
  id: string,
  fetchImpl?: typeof fetch,
): Promise<DestroyedResult> {
  return deleteAdminJson(path('suggestions', id), { hard: true }, fetchImpl);
}

export function destroyAdminUser(id: string, fetchImpl?: typeof fetch): Promise<DestroyedResult> {
  return deleteAdminJson(path('users', id), { hard: true }, fetchImpl);
}
