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
 * PATCH /api/v1/profile (Phase 1.3) with the assembled draft. The
 * endpoint replaces the whole avoid list — the reducer's
 * `toProfilePayload` returns the wholesale-replacement payload.
 */
export async function saveProfile(
  payload: SaveProfilePayload,
  jwt: string,
  opts: ApiOptions = {},
): Promise<void> {
  await api<unknown>('/profile', {
    ...opts,
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${jwt}`,
      ...(opts.headers ?? {}),
    },
    body: JSON.stringify(payload),
  });
}
