/**
 * Phase 3.8 — read-side helpers for the web onboarding flow.
 *
 * Mirrors apps/mobile/lib/api/onboarding.ts. Both apps drive the
 * same `onboardingReducer` from `@biteworthy/filter-engine`, so the
 * fetcher shapes have to line up too.
 */

import type { DietaryPreset } from '@biteworthy/filter-engine';
import { api, type ApiOptions } from './api';

export interface IngredientSearchResult {
  id: string;
  slug: string;
  name: string;
  path: string;
  aliases: string[];
  allergen: boolean;
}

export interface SaveProfilePayload {
  avoid_ingredient_ids: string[];
  avoid_tag_ids: string[];
  prefer_tag_ids: string[];
  strictness: 'relaxed' | 'balanced' | 'strict';
}

export async function fetchDietaryProfiles(opts: ApiOptions = {}): Promise<DietaryPreset[]> {
  const json = await api<{ dietary_profiles: DietaryPreset[] }>('/dietary_profiles', opts);
  return json.dietary_profiles;
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
