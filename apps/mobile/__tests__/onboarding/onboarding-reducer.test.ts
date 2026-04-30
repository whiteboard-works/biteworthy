import {
  reducer,
  initialDraft,
  toProfilePayload,
  type DietaryPreset,
  type DraftProfile,
} from '../../lib/onboarding-reducer';

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

describe('onboarding reducer', () => {
  describe('TOGGLE_PRESET', () => {
    it('adds a preset slug when not selected', () => {
      const next = reducer(initialDraft, { type: 'TOGGLE_PRESET', slug: 'vegan' });
      expect(next.selectedPresetSlugs).toEqual(['vegan']);
    });

    it('removes a preset slug when already selected', () => {
      const seeded: DraftProfile = { ...initialDraft, selectedPresetSlugs: ['vegan', 'celiac'] };
      const next = reducer(seeded, { type: 'TOGGLE_PRESET', slug: 'vegan' });
      expect(next.selectedPresetSlugs).toEqual(['celiac']);
    });

    it('preserves other state', () => {
      const seeded: DraftProfile = {
        selectedPresetSlugs: [],
        manualIngredientIds: ['ing-cilantro'],
        strictness: 'strict',
      };
      const next = reducer(seeded, { type: 'TOGGLE_PRESET', slug: 'vegan' });
      expect(next.manualIngredientIds).toEqual(['ing-cilantro']);
      expect(next.strictness).toBe('strict');
    });
  });

  describe('ADD_MANUAL_INGREDIENT', () => {
    it('appends a new id', () => {
      const next = reducer(initialDraft, {
        type: 'ADD_MANUAL_INGREDIENT',
        ingredientId: 'ing-cilantro',
      });
      expect(next.manualIngredientIds).toEqual(['ing-cilantro']);
    });

    it('is idempotent — adding the same id twice keeps one entry', () => {
      const once = reducer(initialDraft, {
        type: 'ADD_MANUAL_INGREDIENT',
        ingredientId: 'ing-cilantro',
      });
      const twice = reducer(once, {
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
      const next = reducer(seeded, {
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
      const next = reducer(seeded, {
        type: 'REMOVE_MANUAL_INGREDIENT',
        ingredientId: 'ing-zzz',
      });
      expect(next.manualIngredientIds).toEqual(['ing-a']);
    });
  });

  describe('SET_STRICTNESS', () => {
    it('updates strictness', () => {
      const next = reducer(initialDraft, { type: 'SET_STRICTNESS', strictness: 'strict' });
      expect(next.strictness).toBe('strict');
    });
  });

  describe('RESET', () => {
    it('returns the initial draft', () => {
      const seeded: DraftProfile = {
        selectedPresetSlugs: ['vegan'],
        manualIngredientIds: ['ing-x'],
        strictness: 'strict',
      };
      expect(reducer(seeded, { type: 'RESET' })).toEqual(initialDraft);
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
    });
  });

  it('unions a single preset onto manual ingredients', () => {
    const draft: DraftProfile = {
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
      selectedPresetSlugs: ['vegan', 'dairy-free'], // both include ing-dairy + tag-contains-dairy
      manualIngredientIds: [],
      strictness: 'balanced',
    };
    const payload = toProfilePayload(draft, catalog);
    expect(payload.avoid_ingredient_ids).toEqual(['ing-dairy', 'ing-egg', 'ing-meat']);
    expect(payload.avoid_tag_ids).toEqual(['tag-contains-dairy']);
  });

  it('combines presets, manual ingredients, and the strictness toggle', () => {
    const draft: DraftProfile = {
      selectedPresetSlugs: ['vegan', 'tree-nut-allergy'],
      manualIngredientIds: ['ing-cilantro'],
      strictness: 'strict',
    };
    const payload = toProfilePayload(draft, catalog);
    expect(payload.avoid_ingredient_ids.sort()).toEqual(
      [
        'ing-almond',
        'ing-cashew',
        'ing-cilantro',
        'ing-dairy',
        'ing-egg',
        'ing-meat',
      ].sort(),
    );
    expect(payload.avoid_tag_ids.sort()).toEqual(
      ['tag-contains-dairy', 'tag-contains-tree-nut'].sort(),
    );
    expect(payload.strictness).toBe('strict');
    expect(payload.prefer_tag_ids).toEqual([]);
  });

  it('ignores selected slugs missing from the catalog (stale draft)', () => {
    const draft: DraftProfile = {
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
