/**
 * The visible/hidden decision itself is the server's, and is specced
 * directly in `apps/api/spec/services/menus/filter_spec.rb` (plus end to
 * end in `spec/requests/api/v1/restaurants/items_spec.rb` and
 * `spec/services/tools/discovery/get_menu_spec.rb`). These cover only what
 * this package still owns: chip strings, section grouping, and the
 * session-only "show anyway" override.
 */
import { describe, expect, it } from 'vitest';
import {
  applyOverrides,
  groupItemsBySection,
  hiddenReasonLabel,
  type FilteredItem,
  type HideReason,
  type ItemSection,
} from './index';

describe('hiddenReasonLabel', () => {
  it('formats avoid_ingredient', () => {
    const r: HideReason = {
      kind: 'avoid_ingredient',
      ingredient_id: 'i',
      ingredient_name: 'Cheese',
      ingredient_family: 'dairy',
    };
    expect(hiddenReasonLabel(r)).toBe('Contains dairy (Cheese)');
  });

  it('humanizes snake_case families', () => {
    const r: HideReason = {
      kind: 'avoid_ingredient',
      ingredient_id: 'i',
      ingredient_name: 'Almond',
      ingredient_family: 'tree_nut',
    };
    expect(hiddenReasonLabel(r)).toBe('Contains tree nut (Almond)');
  });

  it('formats avoid_tag', () => {
    const r: HideReason = {
      kind: 'avoid_tag',
      tag_id: 't',
      tag_name: 'Contains Dairy',
      tag_family: 'allergen',
    };
    expect(hiddenReasonLabel(r)).toBe('Tagged allergen: Contains Dairy');
  });

  it('formats unconfirmed_strict', () => {
    const r: HideReason = { kind: 'unconfirmed_strict', confidence: 'suggested' };
    expect(hiddenReasonLabel(r)).toBe('AI confidence: suggested (strict mode)');
  });

  it('falls back when family is null', () => {
    const r: HideReason = {
      kind: 'avoid_ingredient',
      ingredient_id: 'i',
      ingredient_name: 'Mystery',
      ingredient_family: null,
    };
    expect(hiddenReasonLabel(r)).toBe('Contains restricted (Mystery)');
  });
});

describe('groupItemsBySection', () => {
  function fItem(overrides: Partial<FilteredItem>): FilteredItem {
    return {
      id: overrides.id ?? 'item-?',
      ingredient_ids: [],
      tag_ids: [],
      confidence: 'confirmed',
      menu_section_id: null,
      menu_section_name: null,
      status: 'visible',
      reasons: [],
      ...overrides,
    };
  }

  it('groups by menu_section_id, preserves first-seen order', () => {
    const sections = groupItemsBySection([
      fItem({ id: 'a', menu_section_id: 'tacos', menu_section_name: 'Tacos' }),
      fItem({ id: 'b', menu_section_id: 'bowls', menu_section_name: 'Bowls' }),
      fItem({ id: 'c', menu_section_id: 'tacos', menu_section_name: 'Tacos' }),
    ]);
    expect(sections.map((s) => s.name)).toEqual(['Tacos', 'Bowls']);
    expect(sections[0]!.visible.map((i) => i.id)).toEqual(['a', 'c']);
  });

  it('drops null-section items into "Other"', () => {
    const sections = groupItemsBySection([fItem({ id: 'a' })]);
    expect(sections[0]!.name).toBe('Other');
  });

  it('separates visible vs hidden within a section', () => {
    const sections = groupItemsBySection([
      fItem({ id: 'v', status: 'visible', menu_section_id: 's', menu_section_name: 'S' }),
      fItem({
        id: 'h',
        status: 'hidden',
        menu_section_id: 's',
        menu_section_name: 'S',
        reasons: [
          {
            kind: 'avoid_ingredient',
            ingredient_id: 'ing-x',
            ingredient_name: null,
            ingredient_family: null,
          },
        ],
      }),
    ]);
    expect(sections[0]!.visible.map((i) => i.id)).toEqual(['v']);
    expect(sections[0]!.hidden.map((i) => i.id)).toEqual(['h']);
  });
});

describe('applyOverrides', () => {
  function fItem(id: string, status: FilteredItem['status']): FilteredItem {
    return {
      id,
      ingredient_ids: [],
      tag_ids: [],
      confidence: 'confirmed',
      menu_section_id: null,
      menu_section_name: null,
      status,
      reasons: [],
    };
  }

  it('returns input unchanged with no overrides', () => {
    const sections: ItemSection[] = [
      {
        id: 'tacos',
        name: 'Tacos',
        visible: [fItem('v', 'visible')],
        hidden: [fItem('h', 'hidden')],
      },
    ];
    expect(applyOverrides(sections, new Set())).toBe(sections);
  });

  it('promotes overridden items into visible bucket', () => {
    const sections: ItemSection[] = [
      {
        id: 'tacos',
        name: 'Tacos',
        visible: [fItem('v', 'visible')],
        hidden: [fItem('h1', 'hidden'), fItem('h2', 'hidden')],
      },
    ];
    const out = applyOverrides(sections, new Set(['h1']));
    expect(out[0]!.visible.map((i) => i.id)).toEqual(['v', 'h1']);
    expect(out[0]!.hidden.map((i) => i.id)).toEqual(['h2']);
  });

  it('preserves untouched section identity', () => {
    const tacos: ItemSection = {
      id: 'tacos',
      name: 'Tacos',
      visible: [],
      hidden: [fItem('h', 'hidden')],
    };
    const bowls: ItemSection = { id: 'bowls', name: 'Bowls', visible: [], hidden: [] };
    const result = applyOverrides([tacos, bowls], new Set(['h']));
    expect(result[1]).toBe(bowls);
  });

  describe('persistent overrides (Phase 4.2)', () => {
    function persistentlyOverridden(id: string): FilteredItem {
      return {
        id,
        ingredient_ids: [],
        tag_ids: [],
        confidence: 'confirmed',
        menu_section_id: null,
        menu_section_name: null,
        status: 'hidden',
        reasons: [],
        overridden_by_user: true,
      };
    }

    it('promotes items flagged overridden_by_user without an explicit shownAnyway entry', () => {
      const sections: ItemSection[] = [
        {
          id: 'tacos',
          name: 'Tacos',
          visible: [fItem('v', 'visible')],
          hidden: [persistentlyOverridden('p1'), fItem('h1', 'hidden')],
        },
      ];
      const out = applyOverrides(sections, new Set());
      expect(out[0]!.visible.map((i) => i.id)).toEqual(['v', 'p1']);
      expect(out[0]!.hidden.map((i) => i.id)).toEqual(['h1']);
    });

    it('unions session + persistent overrides into one bucket', () => {
      const sections: ItemSection[] = [
        {
          id: 'tacos',
          name: 'Tacos',
          visible: [],
          hidden: [persistentlyOverridden('p1'), fItem('s1', 'hidden')],
        },
      ];
      const out = applyOverrides(sections, new Set(['s1']));
      expect(out[0]!.visible.map((i) => i.id)).toEqual(['p1', 's1']);
      expect(out[0]!.hidden).toEqual([]);
    });

    it('preserves identity when neither override kind hits', () => {
      const sections: ItemSection[] = [
        { id: 'tacos', name: 'Tacos', visible: [], hidden: [fItem('h', 'hidden')] },
      ];
      expect(applyOverrides(sections, new Set())).toBe(sections);
    });
  });
});
