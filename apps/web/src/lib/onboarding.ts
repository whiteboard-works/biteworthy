/**
 * Phase 3.8 — read-side helpers for the web onboarding flow.
 *
 * Mirrors apps/mobile/lib/api/onboarding.ts. Both apps drive the
 * same `onboardingReducer` from `@biteworthy/filter-engine`, so the
 * fetcher shapes have to line up too.
 */

import type { DietaryPreset, Strictness } from '@biteworthy/filter-engine';
import { api, type ApiOptions } from './api';

export interface IngredientSearchResult {
  id: string;
  slug: string;
  name: string;
  path: string;
  aliases: string[];
  allergen: boolean;
}

/**
 * Phase 8.5 — taste signals ride on the same PATCH /api/profile as
 * the avoid lists, so they're optional on the full-onboarding
 * payload. The standalone "Improve my picks" save uses
 * `SaveTastePayload` (taste-only) so it can't wipe avoid lists.
 */
export interface SaveProfilePayload {
  avoid_ingredient_ids: string[];
  avoid_tag_ids: string[];
  prefer_tag_ids: string[];
  strictness: Strictness;
  liked_tag_ids?: string[];
  disliked_tag_ids?: string[];
  liked_ingredient_ids?: string[];
  disliked_ingredient_ids?: string[];
  /**
   * Legal remediation E1 — when true, the server stamps
   * `disclaimer_acknowledged_at`. Onboarding sends it on the final
   * save once the user checks the allergen-disclaimer box.
   */
  acknowledge_disclaimer?: boolean;
}

export interface SaveTastePayload {
  liked_tag_ids: string[];
  disliked_tag_ids: string[];
  liked_ingredient_ids: string[];
  disliked_ingredient_ids: string[];
}

/** A taste-onboarding chip. Mirrors GET /api/v1/tags rows. */
export interface TasteTag {
  id: string;
  slug: string;
  name: string;
  family: string;
}

export async function fetchDietaryProfiles(opts: ApiOptions = {}): Promise<DietaryPreset[]> {
  const json = await api<{ dietary_profiles: DietaryPreset[] }>('/dietary_profiles', opts);
  return json.dietary_profiles;
}

/**
 * Phase 8.5 — tag chips for the "What do you love?" step. `families`
 * narrows to the taste-relevant families (cuisine, flavor); the
 * server whitelists unknown names away.
 */
export async function fetchTags(
  families: string[] = ['cuisine', 'flavor'],
  opts: ApiOptions = {},
): Promise<TasteTag[]> {
  const params = new URLSearchParams();
  if (families.length > 0) params.set('families', families.join(','));
  const json = await api<{ tags: TasteTag[] }>(`/tags?${params.toString()}`, opts);
  return json.tags;
}

export async function searchIngredients(
  q: string,
  opts: ApiOptions = {},
): Promise<IngredientSearchResult[]> {
  const params = new URLSearchParams();
  if (q.trim().length > 0) params.set('q', q);
  params.set('limit', '20');
  const json = await api<{ ingredients: IngredientSearchResult[] }>(
    `/ingredients?${params.toString()}`,
    opts,
  );
  return json.ingredients;
}

/**
 * PATCH /api/profile via the Next API route at
 * `apps/web/src/app/api/profile/route.ts`. The proxy reads the
 * HttpOnly `bw_session` cookie and forwards to Rails as a Bearer
 * header — the client never sees the JWT (Phase 4.1).
 *
 * Throws on non-2xx; 401 means the session expired and the caller
 * should redirect to `/login`.
 */
export async function saveProfile(
  payload: SaveProfilePayload,
  opts: { fetchImpl?: typeof fetch } = {},
): Promise<void> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl('/api/profile', {
    method: 'PATCH',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    let body: unknown = null;
    try {
      body = await res.json();
    } catch {
      // ignore
    }
    throw new Error(`saveProfile failed: ${res.status} ${JSON.stringify(body)}`);
  }
}

/**
 * Phase 8.5 standalone "Improve my picks": PATCH ONLY the four taste
 * arrays. The profile endpoint replaces arrays wholesale, so a save
 * that carried the (empty) avoid lists would wipe the user's safety
 * filter — this payload omits them entirely.
 */
export async function saveTaste(
  payload: SaveTastePayload,
  opts: { fetchImpl?: typeof fetch } = {},
): Promise<void> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl('/api/profile', {
    method: 'PATCH',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    let body: unknown = null;
    try {
      body = await res.json();
    } catch {
      // ignore
    }
    throw new Error(`saveTaste failed: ${res.status} ${JSON.stringify(body)}`);
  }
}
