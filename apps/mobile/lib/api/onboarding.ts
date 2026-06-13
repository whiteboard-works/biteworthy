/**
 * Phase 3.2 — read-side helpers for the onboarding flow.
 *
 * `fetchDietaryProfiles()` powers the preset chip picker.
 * `searchIngredients(q)` powers the "Anything else?" free-text step.
 * `saveProfile(payload, jwt)` PATCHes /api/v1/profile when the user
 * taps Done (Phase 1.3 endpoint, wholesale-replace semantics).
 */

import type { DietaryPreset } from '@biteworthy/filter-engine';

const API_BASE = process.env.EXPO_PUBLIC_API_BASE ?? 'http://localhost:3000';

export interface IngredientSearchResult {
  id: string;
  slug: string;
  name: string;
  path: string;
  aliases: string[];
  allergen: boolean;
}

export interface FetchOptions {
  fetchImpl?: typeof fetch;
}

export async function fetchDietaryProfiles(opts: FetchOptions = {}): Promise<DietaryPreset[]> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`${API_BASE}/api/v1/dietary_profiles`);
  if (!res.ok) throw new Error(`fetchDietaryProfiles failed: ${res.status}`);
  const json = (await res.json()) as { dietary_profiles: DietaryPreset[] };
  return json.dietary_profiles;
}

export async function searchIngredients(
  q: string,
  opts: FetchOptions = {},
): Promise<IngredientSearchResult[]> {
  const { fetchImpl = fetch } = opts;
  const url = new URL(`${API_BASE}/api/v1/ingredients`);
  if (q.trim().length > 0) url.searchParams.set('q', q);
  url.searchParams.set('limit', '20');
  const res = await fetchImpl(url.toString());
  if (!res.ok) throw new Error(`searchIngredients failed: ${res.status}`);
  const json = (await res.json()) as { ingredients: IngredientSearchResult[] };
  return json.ingredients;
}

/** A taste-onboarding chip. Mirrors GET /api/v1/tags rows. */
export interface TasteTag {
  id: string;
  slug: string;
  name: string;
  family: string;
}

/**
 * Phase 8.5 — tag chips for the "What do you love?" step. Narrows to
 * the taste-relevant families; the server whitelists unknown names.
 */
export async function fetchTags(
  families: string[] = ['cuisine', 'flavor'],
  opts: FetchOptions = {},
): Promise<TasteTag[]> {
  const { fetchImpl = fetch } = opts;
  const url = new URL(`${API_BASE}/api/v1/tags`);
  if (families.length > 0) url.searchParams.set('families', families.join(','));
  const res = await fetchImpl(url.toString());
  if (!res.ok) throw new Error(`fetchTags failed: ${res.status}`);
  const json = (await res.json()) as { tags: TasteTag[] };
  return json.tags;
}

export interface SaveProfilePayload {
  avoid_ingredient_ids: string[];
  avoid_tag_ids: string[];
  prefer_tag_ids: string[];
  strictness: 'relaxed' | 'balanced' | 'strict';
  liked_tag_ids?: string[];
  disliked_tag_ids?: string[];
  liked_ingredient_ids?: string[];
  disliked_ingredient_ids?: string[];
}

export interface SaveTastePayload {
  liked_tag_ids: string[];
  disliked_tag_ids: string[];
  liked_ingredient_ids: string[];
  disliked_ingredient_ids: string[];
}

export async function saveProfile(
  payload: SaveProfilePayload,
  jwt: string,
  opts: FetchOptions = {},
): Promise<void> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`${API_BASE}/api/v1/profile`, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${jwt}`,
      'Content-Type': 'application/json',
    },
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
 * arrays. The endpoint replaces arrays wholesale, so a save carrying
 * the (empty) avoid lists would wipe the user's safety filter — this
 * payload omits them entirely.
 */
export async function saveTaste(
  payload: SaveTastePayload,
  jwt: string,
  opts: FetchOptions = {},
): Promise<void> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`${API_BASE}/api/v1/profile`, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${jwt}`,
      'Content-Type': 'application/json',
    },
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
