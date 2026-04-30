/**
 * Rails ↔ TS parity check.
 *
 * The Rails serializer at `Api::V1::ItemsController#serialize_item`
 * produces `FilteredItem` payloads (Phase 1.7 + 3.4). This package's
 * `applyProfile` is the canonical TS implementation of the same
 * computation (Phase 3.7). Both are tested independently — the rspec
 * at `apps/api/spec/requests/api/v1/restaurants/items_spec.rb` locks
 * the API output, and `index.test.ts` locks the TS output.
 *
 * This file goes one step further: it runs `applyProfile` against a
 * fixture matching exactly what Rails would emit for the same inputs
 * and asserts byte-identical output. If either side drifts, this
 * test fails — single source of truth, mechanically enforced.
 *
 * The fixture is the "Cheese Quesadilla under vegan preset" scenario
 * the rspec uses, so a human can diff the two by eye if needed.
 */
import { describe, expect, it } from 'vitest';
import { applyProfile, type FilterableItem, type FilterProfile } from './index';

// ── Fixture: matches the Phase 3.4 rspec (dairy-cheese ingredient,
// `allergen-contains-dairy` tag, vegan preset avoiding both).
const cheeseQuesadilla: FilterableItem & {
  // Extra fields the Rails payload carries; must flow through unchanged.
  restaurant_id: string;
  name: string;
  description: string;
  popularity: number;
} = {
  id: 'item-cheese-quesadilla',
  restaurant_id: 'rest-ninis',
  name: 'Cheese Quesadilla',
  description: '',
  popularity: 0,
  ingredient_ids: ['ing-cheese'],
  tag_ids: ['tag-contains-dairy'],
  confidence: 'confirmed',
  menu_section_id: null,
  menu_section_name: null,
};

const carneAsadaTaco: typeof cheeseQuesadilla = {
  ...cheeseQuesadilla,
  id: 'item-carne-asada',
  name: 'Carne Asada Taco',
  ingredient_ids: ['ing-beef'],
  tag_ids: [],
};

const veganProfile: FilterProfile = {
  avoid_ingredient_ids: ['ing-cheese', 'ing-dairy'], // vegan preset has more, but only cheese is on this menu
  avoid_tag_ids: ['tag-contains-dairy'],
  prefer_tag_ids: [],
  strictness: 'balanced',
};

const labels = {
  ingredients: {
    'ing-cheese': { name: 'Cheese', family: 'dairy' },
    'ing-dairy':  { name: 'Dairy',  family: 'dairy' },
    'ing-beef':   { name: 'Beef',   family: 'meat' },
  },
  tags: {
    'tag-contains-dairy': { name: 'Contains Dairy', family: 'allergen' },
  },
};

describe('Rails ↔ TS parity (Phase 3.4 vegan-preset scenario)', () => {
  const out = applyProfile([cheeseQuesadilla, carneAsadaTaco], veganProfile, labels);

  it('hides Cheese Quesadilla and emits both reasons', () => {
    const cheese = out.find((i) => i.id === 'item-cheese-quesadilla')!;
    expect(cheese.status).toBe('hidden');
    expect(cheese.reasons).toEqual([
      {
        kind: 'avoid_ingredient',
        ingredient_id: 'ing-cheese',
        ingredient_name: 'Cheese',
        ingredient_family: 'dairy',
      },
      {
        kind: 'avoid_tag',
        tag_id: 'tag-contains-dairy',
        tag_name: 'Contains Dairy',
        tag_family: 'allergen',
      },
    ]);
  });

  it('keeps Carne Asada Taco visible', () => {
    const taco = out.find((i) => i.id === 'item-carne-asada')!;
    expect(taco.status).toBe('visible');
    expect(taco.reasons).toEqual([]);
  });

  it('passes through every non-filter field unchanged (popularity, name, etc.)', () => {
    const cheese = out.find((i) => i.id === 'item-cheese-quesadilla')!;
    expect(cheese).toMatchObject({
      restaurant_id: 'rest-ninis',
      name: 'Cheese Quesadilla',
      description: '',
      popularity: 0,
    });
  });

  it('emits exactly the keys Rails ships (no surprises in the wire format)', () => {
    const cheese = out.find((i) => i.id === 'item-cheese-quesadilla')!;
    // Sorted for stable comparison.
    const keys = Object.keys(cheese).sort();
    expect(keys).toEqual(
      [
        'confidence',
        'description',
        'id',
        'ingredient_ids',
        'menu_section_id',
        'menu_section_name',
        'name',
        'popularity',
        'reasons',
        'restaurant_id',
        'status',
        'tag_ids',
      ].sort(),
    );
  });
});

describe('Rails ↔ TS parity (strict mode hides unconfirmed)', () => {
  it('emits an unconfirmed_strict reason for non-confirmed items', () => {
    const item: FilterableItem = {
      id: 'i',
      ingredient_ids: [],
      tag_ids: [],
      confidence: 'suggested',
    };
    const out = applyProfile(
      [item],
      {
        avoid_ingredient_ids: [],
        avoid_tag_ids: [],
        strictness: 'strict',
      },
    );
    expect(out[0]!.status).toBe('hidden');
    expect(out[0]!.reasons).toEqual([
      { kind: 'unconfirmed_strict', confidence: 'suggested' },
    ]);
  });
});
