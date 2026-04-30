/**
 * Phase 3.2 — read-side helpers for the onboarding flow.
 *
 * `fetchDietaryProfiles()` powers the preset chip picker.
 * `searchIngredients(q)` powers the "Anything else?" free-text step.
 * `saveProfile(payload, jwt)` PATCHes /api/v1/profile when the user
 * taps Done (Phase 1.3 endpoint, wholesale-replace semantics).
 */

import type { DietaryPreset } from '../onboarding-reducer';

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

export interface SaveProfilePayload {
  avoid_ingredient_ids: string[];
  avoid_tag_ids: string[];
  prefer_tag_ids: string[];
  strictness: 'relaxed' | 'balanced' | 'strict';
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
