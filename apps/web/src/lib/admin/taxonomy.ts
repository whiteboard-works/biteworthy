/**
 * Taxonomy editor fetchers. The server enforces the safety rails
 * (slug/path/family immutable, referenced deletes 409 with per-source
 * counts) — this layer just never SENDS immutable fields on update,
 * and surfaces the 409 reference counts via AdminError.body.
 */
import type { paths } from '@biteworthy/api-types';
import { deleteAdmin, getAdminJson, patchAdminJson, postAdminJson } from './shared';

export type AdminIngredientsResponse =
  paths['/api/v1/admin/ingredients']['get']['responses']['200']['content']['application/json'];
export type AdminIngredient = AdminIngredientsResponse['ingredients'][number];

export type AdminTagsResponse =
  paths['/api/v1/admin/tags']['get']['responses']['200']['content']['application/json'];
export type AdminTag = AdminTagsResponse['tags'][number];

export interface TaxonomyQuery {
  q?: string;
  family?: string;
  limit?: number;
  offset?: number;
}

function toQueryString(query: TaxonomyQuery): string {
  const params = new URLSearchParams();
  if (query.q) params.set('q', query.q);
  if (query.family) params.set('family', query.family);
  if (query.limit != null) params.set('limit', String(query.limit));
  if (query.offset != null) params.set('offset', String(query.offset));
  const qs = params.toString();
  return qs ? `?${qs}` : '';
}

export function fetchAdminIngredients(
  query: TaxonomyQuery = {},
  fetchImpl?: typeof fetch,
): Promise<AdminIngredientsResponse> {
  return getAdminJson(`/api/admin/ingredients${toQueryString(query)}`, fetchImpl);
}

export function createIngredient(
  body: { slug: string; name: string; path: string; aliases?: string[]; allergen?: boolean },
  fetchImpl?: typeof fetch,
): Promise<AdminIngredient> {
  return postAdminJson('/api/admin/ingredients', { body }, fetchImpl);
}

export function updateIngredient(
  id: string,
  body: { name?: string; aliases?: string[]; allergen?: boolean },
  fetchImpl?: typeof fetch,
): Promise<AdminIngredient> {
  return patchAdminJson(`/api/admin/ingredients/${encodeURIComponent(id)}`, body, fetchImpl);
}

export function deleteIngredient(id: string, fetchImpl?: typeof fetch): Promise<void> {
  return deleteAdmin(`/api/admin/ingredients/${encodeURIComponent(id)}`, fetchImpl);
}

export function fetchAdminTags(
  query: TaxonomyQuery = {},
  fetchImpl?: typeof fetch,
): Promise<AdminTagsResponse> {
  return getAdminJson(`/api/admin/tags${toQueryString(query)}`, fetchImpl);
}

export function createTag(
  body: { slug: string; name: string; path: string; family: string; description?: string },
  fetchImpl?: typeof fetch,
): Promise<AdminTag> {
  return postAdminJson('/api/admin/tags', { body }, fetchImpl);
}

export function updateTag(
  id: string,
  body: { name?: string; description?: string },
  fetchImpl?: typeof fetch,
): Promise<AdminTag> {
  return patchAdminJson(`/api/admin/tags/${encodeURIComponent(id)}`, body, fetchImpl);
}

export function deleteTag(id: string, fetchImpl?: typeof fetch): Promise<void> {
  return deleteAdmin(`/api/admin/tags/${encodeURIComponent(id)}`, fetchImpl);
}

/** "still referenced" counts from a 409 delete refusal, or null. */
export function deleteRefusalCounts(err: unknown): Record<string, number> | null {
  if (
    err instanceof Error &&
    'body' in err &&
    typeof (err as { body?: unknown }).body === 'object'
  ) {
    const body = (err as { body?: { error?: string; references?: Record<string, number> } }).body;
    if (body?.error === 'in_use' && body.references) return body.references;
  }
  return null;
}
