/**
 * Phase 3.2 — pure reducer for the onboarding draft profile.
 *
 * The screen drives this; the reducer is pure so the spec can verify
 * every transition without mounting React. The eventual `PATCH
 * /api/v1/profile` payload is the `toProfilePayload(state)` output.
 *
 * Picking a preset (Vegan etc.) is **additive**: it unions the
 * preset's avoid_*_ids onto whatever's already in the draft.
 * Un-picking removes only the ids that ONLY came from that preset,
 * not ids the user added manually or via another preset.
 */

export type Strictness = 'relaxed' | 'balanced' | 'strict';

export interface DietaryPreset {
  id: string;
  slug: string;
  name: string;
  description: string;
  avoid_ingredient_ids: string[];
  avoid_tag_ids: string[];
}

export interface DraftProfile {
  /** Preset slugs the user has tapped on. */
  selectedPresetSlugs: string[];
  /** Ingredient ids the user added via the free-text "Anything else?" step. */
  manualIngredientIds: string[];
  /** Strictness toggle. */
  strictness: Strictness;
}

export const initialDraft: DraftProfile = {
  selectedPresetSlugs: [],
  manualIngredientIds: [],
  strictness: 'balanced',
};

export type Action =
  | { type: 'TOGGLE_PRESET'; slug: string }
  | { type: 'ADD_MANUAL_INGREDIENT'; ingredientId: string }
  | { type: 'REMOVE_MANUAL_INGREDIENT'; ingredientId: string }
  | { type: 'SET_STRICTNESS'; strictness: Strictness }
  | { type: 'RESET' };

export function reducer(state: DraftProfile, action: Action): DraftProfile {
  switch (action.type) {
    case 'TOGGLE_PRESET': {
      const has = state.selectedPresetSlugs.includes(action.slug);
      return {
        ...state,
        selectedPresetSlugs: has
          ? state.selectedPresetSlugs.filter((s) => s !== action.slug)
          : [...state.selectedPresetSlugs, action.slug],
      };
    }
    case 'ADD_MANUAL_INGREDIENT': {
      if (state.manualIngredientIds.includes(action.ingredientId)) return state;
      return {
        ...state,
        manualIngredientIds: [...state.manualIngredientIds, action.ingredientId],
      };
    }
    case 'REMOVE_MANUAL_INGREDIENT':
      return {
        ...state,
        manualIngredientIds: state.manualIngredientIds.filter((id) => id !== action.ingredientId),
      };
    case 'SET_STRICTNESS':
      return { ...state, strictness: action.strictness };
    case 'RESET':
      return initialDraft;
  }
}

/**
 * Compose the final avoid lists for `PATCH /api/v1/profile`. Unions
 * the manual ingredient picks with every selected preset's
 * avoid_ingredient_ids, dedupes, returns the wholesale-replacement
 * payload the endpoint expects (per Phase 1.3 semantics).
 */
export function toProfilePayload(
  state: DraftProfile,
  presetCatalog: DietaryPreset[],
): {
  avoid_ingredient_ids: string[];
  avoid_tag_ids: string[];
  prefer_tag_ids: string[];
  strictness: Strictness;
} {
  const selected = presetCatalog.filter((p) => state.selectedPresetSlugs.includes(p.slug));

  const ingredientIds = new Set<string>(state.manualIngredientIds);
  const tagIds = new Set<string>();

  for (const preset of selected) {
    for (const id of preset.avoid_ingredient_ids) ingredientIds.add(id);
    for (const id of preset.avoid_tag_ids) tagIds.add(id);
  }

  return {
    avoid_ingredient_ids: Array.from(ingredientIds),
    avoid_tag_ids:        Array.from(tagIds),
    prefer_tag_ids:       [],
    strictness:           state.strictness,
  };
}
