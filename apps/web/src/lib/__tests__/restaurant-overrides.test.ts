import { describe, expect, it } from 'vitest';
import { applyOverrides } from '../restaurant-overrides';
import type { FilteredItem, ItemSection } from '../restaurants';

function item(overrides: Partial<FilteredItem>): FilteredItem {
  return {
    id: overrides.id ?? 'item-?',
    restaurant_id: 'rest-1',
    name: 'Item',
    description: '',
    confidence: 'confirmed',
    popularity: 0,
    ingredient_ids: [],
    tag_ids: [],
    menu_section_id: null,
    menu_section_name: null,
    status: 'visible',
    reasons: [],
    ...overrides,
  };
}

const visible = item({ id: 'v', status: 'visible' });
const hiddenA = item({
  id: 'h1',
  status: 'hidden',
  reasons: [
    {
      kind: 'avoid_ingredient',
      ingredient_id: 'i-x',
      ingredient_name: 'Cheese',
      ingredient_family: 'dairy',
    },
  ],
});
const hiddenB = item({
  id: 'h2',
  status: 'hidden',
  reasons: [
    {
      kind: 'avoid_tag',
      tag_id: 't-y',
      tag_name: 'Contains Dairy',
      tag_family: 'allergen',
    },
  ],
});

function section(visibleItems: FilteredItem[], hiddenItems: FilteredItem[]): ItemSection {
  return { id: 'tacos', name: 'Tacos', visible: visibleItems, hidden: hiddenItems };
}

describe('applyOverrides (web mirror)', () => {
  it('returns input unchanged when no overrides', () => {
    const sections = [section([visible], [hiddenA])];
    expect(applyOverrides(sections, new Set())).toBe(sections);
  });

  it('promotes overridden items into the visible bucket', () => {
    const sections = [section([visible], [hiddenA, hiddenB])];
    const result = applyOverrides(sections, new Set(['h1']));
    expect(result[0]!.visible.map((i) => i.id)).toEqual(['v', 'h1']);
    expect(result[0]!.hidden.map((i) => i.id)).toEqual(['h2']);
  });

  it('preserves untouched section identity', () => {
    const tacos = section([visible], [hiddenA]);
    const bowls: ItemSection = { id: 'bowls', name: 'Bowls', visible: [], hidden: [] };
    const result = applyOverrides([tacos, bowls], new Set(['h1']));
    expect(result[1]).toBe(bowls);
  });
});
