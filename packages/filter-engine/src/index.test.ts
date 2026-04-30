import { describe, expect, it } from 'vitest';
import {
  applyOverrides,
  applyProfile,
  buildLabelLookup,
  groupItemsBySection,
  hiddenReasonHeadline,
  hiddenReasonLabel,
  type FilterableItem,
  type FilterProfile,
  type FilteredItem,
  type HideReason,
  type ItemSection,
  type LabelLookup,
} from './index';

const item = (overrides: Partial<FilterableItem> = {}): FilterableItem => ({
  id: 'i1',
  ingredient_ids: [],
  tag_ids: [],
  confidence: 'confirmed',
  ...overrides,
});

const profile = (overrides: Partial<FilterProfile> = {}): FilterProfile => ({
  avoid_ingredient_ids: [],
  avoid_tag_ids: [],
  prefer_tag_ids: [],
  strictness: 'balanced',
  ...overrides,
});

const labels: LabelLookup = {
  ingredients: {
    'ing-cheese':  { name: 'Cheese', family: 'dairy' },
    'ing-almond':  { name: 'Almond', family: 'tree_nut' },
    'ing-anonymous': { name: null, family: null }, // catalog gap
  },
  tags: {
    'tag-cd': { name: 'Contains Dairy', family: 'allergen' },
  },
};

describe('applyProfile', () => {
  it('marks every item visible when no avoid lists hit', () => {
    const out = applyProfile([item({ id: 'a' }), item({ id: 'b' })], profile(), labels);
    expect(out.map((i) => i.status)).toEqual(['visible', 'visible']);
    expect(out.flatMap((i) => i.reasons)).toEqual([]);
  });

  it('hides items containing an avoided ingredient and enriches the reason', () => {
    const items = [
      item({ id: 'a', ingredient_ids: ['ing-cheese'] }),
      item({ id: 'b' }),
    ];
    const out = applyProfile(
      items,
      profile({ avoid_ingredient_ids: ['ing-cheese'] }),
      labels,
    );
    expect(out[0]).toMatchObject({
      status: 'hidden',
      reasons: [
        {
          kind: 'avoid_ingredient',
          ingredient_id: 'ing-cheese',
          ingredient_name: 'Cheese',
          ingredient_family: 'dairy',
        },
      ],
    });
    expect(out[1]!.status).toBe('visible');
  });

  it('hides items with an avoided tag', () => {
    const items = [item({ tag_ids: ['tag-cd'] })];
    const out = applyProfile(items, profile({ avoid_tag_ids: ['tag-cd'] }), labels);
    expect(out[0]!.status).toBe('hidden');
    expect(out[0]!.reasons[0]).toMatchObject({
      kind: 'avoid_tag',
      tag_name: 'Contains Dairy',
      tag_family: 'allergen',
    });
  });

  it('strict mode hides unconfirmed items even with no allergens', () => {
    const items = [item({ confidence: 'suggested' })];
    const out = applyProfile(items, profile({ strictness: 'strict' }), labels);
    expect(out[0]!.status).toBe('hidden');
    expect(out[0]!.reasons).toEqual([
      { kind: 'unconfirmed_strict', confidence: 'suggested' },
    ]);
  });

  it('balanced mode keeps unconfirmed items visible', () => {
    const items = [item({ confidence: 'suggested' })];
    const out = applyProfile(items, profile({ strictness: 'balanced' }), labels);
    expect(out[0]!.status).toBe('visible');
  });

  it('emits multiple reasons when an item hits both ingredient + tag avoid', () => {
    const items = [item({ ingredient_ids: ['ing-cheese'], tag_ids: ['tag-cd'] })];
    const out = applyProfile(
      items,
      profile({ avoid_ingredient_ids: ['ing-cheese'], avoid_tag_ids: ['tag-cd'] }),
      labels,
    );
    expect(out[0]!.reasons.map((r) => r.kind)).toEqual([
      'avoid_ingredient',
      'avoid_tag',
    ]);
  });

  it('falls back to nulls when the label lookup is missing the id', () => {
    const items = [item({ ingredient_ids: ['ing-anonymous'] })];
    const out = applyProfile(
      items,
      profile({ avoid_ingredient_ids: ['ing-anonymous'] }),
      labels,
    );
    expect(out[0]!.reasons[0]).toMatchObject({
      ingredient_name: null,
      ingredient_family: null,
    });
  });

  it('works without any labels (raw ids only)', () => {
    const items = [item({ ingredient_ids: ['ing-cheese'] })];
    const out = applyProfile(items, profile({ avoid_ingredient_ids: ['ing-cheese'] }));
    expect(out[0]!.reasons[0]).toMatchObject({
      ingredient_id: 'ing-cheese',
      ingredient_name: null,
      ingredient_family: null,
    });
  });

  it('preserves extra fields on the input item (passthrough)', () => {
    interface RichItem extends FilterableItem {
      name: string;
      popularity: number;
    }
    const items: RichItem[] = [
      { ...item({ id: 'a' }), name: 'Carne Asada', popularity: 5 },
    ];
    const out = applyProfile(items, profile());
    expect(out[0]!.name).toBe('Carne Asada');
    expect(out[0]!.popularity).toBe(5);
  });
});

describe('buildLabelLookup', () => {
  it('derives ingredient family from ltree path first segment', () => {
    const lookup = buildLabelLookup({
      ingredients: [
        { id: 'ing-1', name: 'Cheddar', path: 'dairy.cheddar' },
        { id: 'ing-2', name: 'Almond', path: 'tree_nut.almond' },
      ],
    });
    expect(lookup.ingredients!['ing-1']).toEqual({ name: 'Cheddar', family: 'dairy' });
    expect(lookup.ingredients!['ing-2']).toEqual({ name: 'Almond', family: 'tree_nut' });
  });

  it('takes tag family verbatim from the tag column', () => {
    const lookup = buildLabelLookup({
      tags: [{ id: 't-1', name: 'Vegan', family: 'diet' }],
    });
    expect(lookup.tags!['t-1']).toEqual({ name: 'Vegan', family: 'diet' });
  });

  it('handles missing path gracefully', () => {
    const lookup = buildLabelLookup({
      ingredients: [{ id: 'ing-x', name: 'Mystery' }],
    });
    expect(lookup.ingredients!['ing-x']).toEqual({ name: 'Mystery', family: null });
  });
});

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

describe('hiddenReasonHeadline', () => {
  const dairy: HideReason = {
    kind: 'avoid_ingredient',
    ingredient_id: 'i',
    ingredient_name: 'Cheese',
    ingredient_family: 'dairy',
  };
  const tag: HideReason = {
    kind: 'avoid_tag',
    tag_id: 't',
    tag_name: 'Contains Dairy',
    tag_family: 'allergen',
  };

  it('returns empty for no reasons', () => {
    expect(hiddenReasonHeadline([])).toBe('');
  });

  it('shows just the first reason for a single reason', () => {
    expect(hiddenReasonHeadline([dairy])).toBe('Hidden — Contains dairy (Cheese)');
  });

  it('appends "+N more" suffix', () => {
    expect(hiddenReasonHeadline([dairy, tag])).toBe(
      'Hidden — Contains dairy (Cheese) (+1 more)',
    );
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
