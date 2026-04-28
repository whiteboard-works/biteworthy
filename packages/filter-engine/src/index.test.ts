import { describe, expect, it } from 'vitest';
import { applyProfile, sortFiltered } from './index';
import type { Item, UserProfile } from '@biteworthy/api-types';

const item = (overrides: Partial<Item> = {}): Item => ({
  id: 'i1',
  restaurantId: 'r1',
  name: 'Sample',
  description: null,
  ingredientIds: [],
  tagIds: [],
  confidence: 'confirmed',
  ...overrides,
});

const profile = (overrides: Partial<UserProfile> = {}): UserProfile => ({
  avoidIngredientIds: [],
  avoidTagIds: [],
  preferTagIds: [],
  strictness: 'balanced',
  ...overrides,
});

describe('applyProfile', () => {
  it('hides items containing an avoided ingredient and reports why', () => {
    const items = [item({ id: 'a', ingredientIds: ['dairy'] }), item({ id: 'b' })];
    const out = applyProfile(items, profile({ avoidIngredientIds: ['dairy'] }));
    expect(out[0]).toMatchObject({
      hidden: true,
      reasons: [{ kind: 'avoid-ingredient', ingredientId: 'dairy' }],
    });
    expect(out[1]?.hidden).toBe(false);
  });

  it('hides items with an avoided tag', () => {
    const items = [item({ tagIds: ['fried'] })];
    const out = applyProfile(items, profile({ avoidTagIds: ['fried'] }));
    expect(out[0]?.hidden).toBe(true);
  });

  it('strict mode hides unconfirmed items even when no allergens hit', () => {
    const items = [item({ confidence: 'suggested' })];
    const out = applyProfile(items, profile({ strictness: 'strict' }));
    expect(out[0]?.hidden).toBe(true);
    expect(out[0]?.reasons).toEqual([{ kind: 'unconfirmed-strict' }]);
  });

  it('balanced mode keeps unconfirmed items visible', () => {
    const items = [item({ confidence: 'suggested' })];
    const out = applyProfile(items, profile({ strictness: 'balanced' }));
    expect(out[0]?.hidden).toBe(false);
  });

  it('counts preferred-tag matches without hiding', () => {
    const items = [item({ tagIds: ['vegan', 'spicy'] }), item({ tagIds: ['vegan'] })];
    const out = applyProfile(items, profile({ preferTagIds: ['vegan', 'spicy'] }));
    expect(out[0]?.preferMatchCount).toBe(2);
    expect(out[1]?.preferMatchCount).toBe(1);
  });
});

describe('sortFiltered', () => {
  it('puts visible items first, then ranks by prefer-match count', () => {
    const items = [
      item({ id: 'hidden', ingredientIds: ['x'] }),
      item({ id: 'one-match', tagIds: ['vegan'] }),
      item({ id: 'two-match', tagIds: ['vegan', 'spicy'] }),
    ];
    const filtered = applyProfile(
      items,
      profile({ avoidIngredientIds: ['x'], preferTagIds: ['vegan', 'spicy'] }),
    );
    const sorted = sortFiltered(filtered);
    expect(sorted.map((f) => f.item.id)).toEqual(['two-match', 'one-match', 'hidden']);
  });
});
