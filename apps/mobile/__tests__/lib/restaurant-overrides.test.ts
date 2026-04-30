import { applyOverrides } from '../../lib/restaurant-overrides';
import type { FilteredItem, ItemSection } from '../../lib/api/restaurants';

function item(overrides: Partial<FilteredItem>): FilteredItem {
  return {
    id: overrides.id ?? 'item-?',
    restaurant_id: 'rest-1',
    name: overrides.name ?? 'Item',
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

function section(visible: FilteredItem[], hidden: FilteredItem[]): ItemSection {
  return {
    id: 'tacos',
    name: 'Tacos',
    visible,
    hidden,
  };
}

describe('applyOverrides', () => {
  const visible = item({ id: 'v1', status: 'visible' });
  const hiddenA = item({
    id: 'h1',
    status: 'hidden',
    reasons: [
      {
        kind: 'avoid_ingredient',
        ingredient_id: 'ing-x',
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
        tag_id: 'tag-y',
        tag_name: 'Contains Dairy',
        tag_family: 'allergen',
      },
    ],
  });

  it('returns the input unchanged when no overrides are active', () => {
    const sections = [section([visible], [hiddenA, hiddenB])];
    expect(applyOverrides(sections, new Set())).toBe(sections);
  });

  it('promotes overridden items into the visible bucket of their section', () => {
    const sections = [section([visible], [hiddenA, hiddenB])];
    const result = applyOverrides(sections, new Set(['h1']));
    expect(result[0]!.visible.map((i) => i.id)).toEqual(['v1', 'h1']);
    expect(result[0]!.hidden.map((i) => i.id)).toEqual(['h2']);
  });

  it('leaves other sections untouched (referential equality preserved)', () => {
    const tacos = section([visible], [hiddenA]);
    const bowls: ItemSection = { id: 'bowls', name: 'Bowls', visible: [], hidden: [] };
    const result = applyOverrides([tacos, bowls], new Set(['h1']));
    expect(result[1]).toBe(bowls); // untouched section keeps identity
  });

  it('promotes multiple items across one section in one pass', () => {
    const sections = [section([visible], [hiddenA, hiddenB])];
    const result = applyOverrides(sections, new Set(['h1', 'h2']));
    expect(result[0]!.visible.map((i) => i.id)).toEqual(['v1', 'h1', 'h2']);
    expect(result[0]!.hidden).toEqual([]);
  });
});
