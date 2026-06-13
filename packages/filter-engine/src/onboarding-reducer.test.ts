import { describe, expect, it } from 'vitest';
import {
  initialDraft,
  onboardingReducer,
  toProfilePayload,
  toTastePayload,
  type DietaryPreset,
  type DraftProfile,
} from './onboarding-reducer';

const vegan: DietaryPreset = {
  id: 'p-vegan',
  slug: 'vegan',
  name: 'Vegan',
  description: 'No animal products.',
  avoid_ingredient_ids: ['ing-dairy', 'ing-egg', 'ing-meat'],
  avoid_tag_ids: ['tag-contains-dairy'],
};

const treeNut: DietaryPreset = {
  id: 'p-treenut',
  slug: 'tree-nut-allergy',
  name: 'Tree-nut allergy',
  description: 'No tree nuts.',
  avoid_ingredient_ids: ['ing-almond', 'ing-cashew'],
  avoid_tag_ids: ['tag-contains-tree-nut'],
};

const dairyFree: DietaryPreset = {
  id: 'p-dairy-free',
  slug: 'dairy-free',
  name: 'Dairy-free',
  description: 'No dairy.',
  avoid_ingredient_ids: ['ing-dairy'], // overlaps with vegan on purpose
  avoid_tag_ids: ['tag-contains-dairy'],
};

describe('onboardingReducer', () => {
  describe('TOGGLE_PRESET', () => {
    it('adds a preset slug when not selected', () => {
      const next = onboardingReducer(initialDraft, { type: 'TOGGLE_PRESET', slug: 'vegan' });
      expect(next.selectedPresetSlugs).toEqual(['vegan']);
    });

    it('removes a preset slug when already selected', () => {
      const seeded: DraftProfile = { ...initialDraft, selectedPresetSlugs: ['vegan', 'celiac'] };
      const next = onboardingReducer(seeded, { type: 'TOGGLE_PRESET', slug: 'vegan' });
      expect(next.selectedPresetSlugs).toEqual(['celiac']);
    });

    it('preserves other state', () => {
      const seeded: DraftProfile = {
        ...initialDraft,
        selectedPresetSlugs: [],
        manualIngredientIds: ['ing-cilantro'],
        strictness: 'strict',
      };
      const next = onboardingReducer(seeded, { type: 'TOGGLE_PRESET', slug: 'vegan' });
      expect(next.manualIngredientIds).toEqual(['ing-cilantro']);
      expect(next.strictness).toBe('strict');
    });
  });

  describe('ADD_MANUAL_INGREDIENT', () => {
    it('appends a new id', () => {
      const next = onboardingReducer(initialDraft, {
        type: 'ADD_MANUAL_INGREDIENT',
        ingredientId: 'ing-cilantro',
      });
      expect(next.manualIngredientIds).toEqual(['ing-cilantro']);
    });

    it('is idempotent — adding the same id twice keeps one entry', () => {
      const once = onboardingReducer(initialDraft, {
        type: 'ADD_MANUAL_INGREDIENT',
        ingredientId: 'ing-cilantro',
      });
      const twice = onboardingReducer(once, {
        type: 'ADD_MANUAL_INGREDIENT',
        ingredientId: 'ing-cilantro',
      });
      expect(twice).toBe(once); // same reference — short-circuits
      expect(twice.manualIngredientIds).toEqual(['ing-cilantro']);
    });
  });

  describe('REMOVE_MANUAL_INGREDIENT', () => {
    it('removes the matching id', () => {
      const seeded: DraftProfile = {
        ...initialDraft,
        manualIngredientIds: ['ing-a', 'ing-b', 'ing-c'],
      };
      const next = onboardingReducer(seeded, {
        type: 'REMOVE_MANUAL_INGREDIENT',
        ingredientId: 'ing-b',
      });
      expect(next.manualIngredientIds).toEqual(['ing-a', 'ing-c']);
    });

    it('is a no-op when id is not present', () => {
      const seeded: DraftProfile = {
        ...initialDraft,
        manualIngredientIds: ['ing-a'],
      };
      const next = onboardingReducer(seeded, {
        type: 'REMOVE_MANUAL_INGREDIENT',
        ingredientId: 'ing-zzz',
      });
      expect(next.manualIngredientIds).toEqual(['ing-a']);
    });
  });

  describe('SET_STRICTNESS', () => {
    it('updates strictness', () => {
      const next = onboardingReducer(initialDraft, { type: 'SET_STRICTNESS', strictness: 'strict' });
      expect(next.strictness).toBe('strict');
    });
  });

  describe('RESET', () => {
    it('returns the initial draft', () => {
      const seeded: DraftProfile = {
        ...initialDraft,
        selectedPresetSlugs: ['vegan'],
        manualIngredientIds: ['ing-x'],
        strictness: 'strict',
      };
      expect(onboardingReducer(seeded, { type: 'RESET' })).toEqual(initialDraft);
    });
  });
});

describe('toProfilePayload', () => {
  const catalog = [vegan, treeNut, dairyFree];

  it('returns an empty avoid list when no presets and no manual picks', () => {
    const payload = toProfilePayload(initialDraft, catalog);
    expect(payload).toEqual({
      avoid_ingredient_ids: [],
      avoid_tag_ids: [],
      prefer_tag_ids: [],
      strictness: 'balanced',
      // Phase 8.5 — skipping the taste step leaves all four empty.
      liked_tag_ids: [],
      disliked_tag_ids: [],
      liked_ingredient_ids: [],
      disliked_ingredient_ids: [],
    });
  });

  it('unions a single preset onto manual ingredients', () => {
    const draft: DraftProfile = {
      ...initialDraft,
      selectedPresetSlugs: ['vegan'],
      manualIngredientIds: ['ing-cilantro'],
      strictness: 'balanced',
    };
    const payload = toProfilePayload(draft, catalog);
    expect(payload.avoid_ingredient_ids.sort()).toEqual(
      ['ing-cilantro', 'ing-dairy', 'ing-egg', 'ing-meat'].sort(),
    );
    expect(payload.avoid_tag_ids).toEqual(['tag-contains-dairy']);
  });

  it('dedupes ids that appear in multiple selected presets', () => {
    const draft: DraftProfile = {
      ...initialDraft,
      selectedPresetSlugs: ['vegan', 'dairy-free'],
      manualIngredientIds: [],
      strictness: 'balanced',
    };
    const payload = toProfilePayload(draft, catalog);
    expect(payload.avoid_ingredient_ids).toEqual(['ing-dairy', 'ing-egg', 'ing-meat']);
    expect(payload.avoid_tag_ids).toEqual(['tag-contains-dairy']);
  });

  it('combines presets, manual ingredients, and the strictness toggle', () => {
    const draft: DraftProfile = {
      ...initialDraft,
      selectedPresetSlugs: ['vegan', 'tree-nut-allergy'],
      manualIngredientIds: ['ing-cilantro'],
      strictness: 'strict',
    };
    const payload = toProfilePayload(draft, catalog);
    expect(payload.avoid_ingredient_ids.sort()).toEqual(
      ['ing-almond', 'ing-cashew', 'ing-cilantro', 'ing-dairy', 'ing-egg', 'ing-meat'].sort(),
    );
    expect(payload.avoid_tag_ids.sort()).toEqual(
      ['tag-contains-dairy', 'tag-contains-tree-nut'].sort(),
    );
    expect(payload.strictness).toBe('strict');
    expect(payload.prefer_tag_ids).toEqual([]);
  });

  it('ignores selected slugs missing from the catalog (stale draft)', () => {
    const draft: DraftProfile = {
      ...initialDraft,
      selectedPresetSlugs: ['ghost-preset', 'vegan'],
      manualIngredientIds: [],
      strictness: 'balanced',
    };
    const payload = toProfilePayload(draft, catalog);
    expect(payload.avoid_ingredient_ids.sort()).toEqual(
      ['ing-dairy', 'ing-egg', 'ing-meat'].sort(),
    );
  });
});

// Phase 8.5 — taste chips cycle neutral → liked → disliked → neutral
// so one tap target covers both polarities; standalone saves use
// toTastePayload so they can never wipe the avoid lists.
describe('taste signals (Phase 8.5)', () => {
  it('CYCLE_TASTE_TAG walks neutral → liked → disliked → neutral', () => {
    const a = onboardingReducer(initialDraft, { type: 'CYCLE_TASTE_TAG', tagId: 't1' });
    expect(a.likedTagIds).toEqual(['t1']);
    expect(a.dislikedTagIds).toEqual([]);

    const b = onboardingReducer(a, { type: 'CYCLE_TASTE_TAG', tagId: 't1' });
    expect(b.likedTagIds).toEqual([]);
    expect(b.dislikedTagIds).toEqual(['t1']);

    const c = onboardingReducer(b, { type: 'CYCLE_TASTE_TAG', tagId: 't1' });
    expect(c.likedTagIds).toEqual([]);
    expect(c.dislikedTagIds).toEqual([]);
  });

  it('CYCLE_TASTE_INGREDIENT cycles independently of tags', () => {
    const a = onboardingReducer(initialDraft, {
      type: 'CYCLE_TASTE_INGREDIENT',
      ingredientId: 'i1',
    });
    expect(a.likedIngredientIds).toEqual(['i1']);
    expect(a.likedTagIds).toEqual([]);
  });

  it('toProfilePayload carries the four arrays; toTastePayload carries ONLY them', () => {
    let draft = onboardingReducer(initialDraft, { type: 'CYCLE_TASTE_TAG', tagId: 't1' });
    draft = onboardingReducer(draft, { type: 'CYCLE_TASTE_TAG', tagId: 't2' });
    draft = onboardingReducer(draft, { type: 'CYCLE_TASTE_TAG', tagId: 't2' }); // → disliked

    const full = toProfilePayload(draft, []);
    expect(full.liked_tag_ids).toEqual(['t1']);
    expect(full.disliked_tag_ids).toEqual(['t2']);

    const standalone = toTastePayload(draft);
    expect(standalone).toEqual({
      liked_tag_ids: ['t1'],
      disliked_tag_ids: ['t2'],
      liked_ingredient_ids: [],
      disliked_ingredient_ids: [],
    });
    // No avoid keys — a standalone PATCH cannot wipe the safety filter.
    expect(Object.keys(standalone)).not.toContain('avoid_ingredient_ids');
  });
});
