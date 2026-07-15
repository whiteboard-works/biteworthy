/**
 * Phase 3.2 + 3.8 — pure reducer for the onboarding draft profile.
 * Phase 8.5 — taste step ("What do you love?") joins the flow.
 *
 * Drives the onboarding flow on both mobile (Phase 3.2) and
 * web (Phase 3.8). The reducer is pure so the spec verifies every
 * transition without mounting React, and the eventual
 * `PATCH /api/v1/profile` payload is the `toProfilePayload(state)`
 * output.
 *
 * Picking a preset (Vegan etc.) is **additive**: it unions the
 * preset's avoid_*_ids onto whatever's already in the draft. The
 * union+dedupe is what `toProfilePayload` does — the reducer just
 * remembers which slugs the user tapped on.
 *
 * Taste signals are SOFT (Phase 8 design principle: safety filters,
 * taste ranks). Each chip cycles neutral → liked → disliked →
 * neutral so one tap target covers both polarities. Skipping the
 * step leaves all four arrays empty — taste is optional, safety is
 * not.
 */
import type { Strictness } from './index';

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
  /** Phase 8.5 — taste signals (rank, never hide). */
  likedTagIds: string[];
  dislikedTagIds: string[];
  likedIngredientIds: string[];
  dislikedIngredientIds: string[];
}

export const initialDraft: DraftProfile = {
  selectedPresetSlugs: [],
  manualIngredientIds: [],
  strictness: 'balanced',
  likedTagIds: [],
  dislikedTagIds: [],
  likedIngredientIds: [],
  dislikedIngredientIds: [],
};

export type TasteState = 'neutral' | 'liked' | 'disliked';

export type OnboardingAction =
  | { type: 'TOGGLE_PRESET'; slug: string }
  | { type: 'ADD_MANUAL_INGREDIENT'; ingredientId: string }
  | { type: 'REMOVE_MANUAL_INGREDIENT'; ingredientId: string }
  | { type: 'SET_STRICTNESS'; strictness: Strictness }
  | { type: 'CYCLE_TASTE_TAG'; tagId: string }
  | { type: 'CYCLE_TASTE_INGREDIENT'; ingredientId: string }
  /** Replace the whole draft — used to restore a persisted draft (e.g. after
   *  an anonymous user is bounced through sign-up mid-onboarding). */
  | { type: 'HYDRATE'; draft: DraftProfile }
  | { type: 'RESET' };

export function tasteStateOf(
  id: string,
  liked: string[],
  disliked: string[],
): TasteState {
  if (liked.includes(id)) return 'liked';
  if (disliked.includes(id)) return 'disliked';
  return 'neutral';
}

/** neutral → liked → disliked → neutral. */
function cycle(
  id: string,
  liked: string[],
  disliked: string[],
): { liked: string[]; disliked: string[] } {
  switch (tasteStateOf(id, liked, disliked)) {
    case 'neutral':
      return { liked: [...liked, id], disliked };
    case 'liked':
      return { liked: liked.filter((x) => x !== id), disliked: [...disliked, id] };
    case 'disliked':
      return { liked, disliked: disliked.filter((x) => x !== id) };
  }
}

export function onboardingReducer(state: DraftProfile, action: OnboardingAction): DraftProfile {
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
    case 'CYCLE_TASTE_TAG': {
      const next = cycle(action.tagId, state.likedTagIds, state.dislikedTagIds);
      return { ...state, likedTagIds: next.liked, dislikedTagIds: next.disliked };
    }
    case 'CYCLE_TASTE_INGREDIENT': {
      const next = cycle(
        action.ingredientId,
        state.likedIngredientIds,
        state.dislikedIngredientIds,
      );
      return { ...state, likedIngredientIds: next.liked, dislikedIngredientIds: next.disliked };
    }
    case 'HYDRATE':
      return action.draft;
    case 'RESET':
      return initialDraft;
  }
}

/**
 * Compose the final avoid lists for `PATCH /api/v1/profile`. Unions
 * the manual ingredient picks with every selected preset's
 * avoid_ingredient_ids, dedupes, returns the wholesale-replacement
 * payload the endpoint expects (per Phase 1.3 semantics). Phase 8.5
 * adds the four taste arrays — empty when the step was skipped.
 */
export function toProfilePayload(
  state: DraftProfile,
  presetCatalog: DietaryPreset[],
): {
  avoid_ingredient_ids: string[];
  avoid_tag_ids: string[];
  prefer_tag_ids: string[];
  strictness: Strictness;
  liked_tag_ids: string[];
  disliked_tag_ids: string[];
  liked_ingredient_ids: string[];
  disliked_ingredient_ids: string[];
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
    liked_tag_ids:           state.likedTagIds,
    disliked_tag_ids:        state.dislikedTagIds,
    liked_ingredient_ids:    state.likedIngredientIds,
    disliked_ingredient_ids: state.dislikedIngredientIds,
  };
}

/**
 * Phase 8.5 standalone mode ("Improve my picks"): PATCH ONLY the
 * four taste fields. The profile endpoint replaces arrays wholesale,
 * so a standalone save that included the (empty) draft avoid lists
 * would WIPE the user's existing safety filter — this payload can't.
 */
export function toTastePayload(state: DraftProfile): {
  liked_tag_ids: string[];
  disliked_tag_ids: string[];
  liked_ingredient_ids: string[];
  disliked_ingredient_ids: string[];
} {
  return {
    liked_tag_ids:           state.likedTagIds,
    disliked_tag_ids:        state.dislikedTagIds,
    liked_ingredient_ids:    state.likedIngredientIds,
    disliked_ingredient_ids: state.dislikedIngredientIds,
  };
}
