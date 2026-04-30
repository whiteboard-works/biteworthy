import { hiddenReasonHeadline, hiddenReasonLabel } from '../../lib/hidden-reason';
import type { HideReason } from '../../lib/api/restaurants';

const dairyCheese: HideReason = {
  kind: 'avoid_ingredient',
  ingredient_id: 'ing-cheese',
  ingredient_name: 'Cheese',
  ingredient_family: 'dairy',
};

const treeNutAlmond: HideReason = {
  kind: 'avoid_ingredient',
  ingredient_id: 'ing-almond',
  ingredient_name: 'Almond',
  ingredient_family: 'tree_nut',
};

const containsDairyTag: HideReason = {
  kind: 'avoid_tag',
  tag_id: 'tag-cd',
  tag_name: 'Contains Dairy',
  tag_family: 'allergen',
};

const strict: HideReason = {
  kind: 'unconfirmed_strict',
  confidence: 'suggested',
};

describe('hiddenReasonLabel', () => {
  it('formats avoid_ingredient as "Contains <family> (<name>)"', () => {
    expect(hiddenReasonLabel(dairyCheese)).toBe('Contains dairy (Cheese)');
  });

  it('humanizes snake_case families (tree_nut → tree nut)', () => {
    expect(hiddenReasonLabel(treeNutAlmond)).toBe('Contains tree nut (Almond)');
  });

  it('formats avoid_tag as "Tagged <family>: <name>"', () => {
    expect(hiddenReasonLabel(containsDairyTag)).toBe('Tagged allergen: Contains Dairy');
  });

  it('formats unconfirmed_strict with the AI confidence + strict-mode note', () => {
    expect(hiddenReasonLabel(strict)).toBe('AI confidence: suggested (strict mode)');
  });

  it('falls back gracefully when family is missing', () => {
    const noFamily: HideReason = {
      kind: 'avoid_ingredient',
      ingredient_id: 'ing-x',
      ingredient_name: 'Mystery',
      ingredient_family: null,
    };
    expect(hiddenReasonLabel(noFamily)).toBe('Contains restricted (Mystery)');
  });

  it('falls back gracefully when name is missing (ingredient deleted server-side)', () => {
    const noName: HideReason = {
      kind: 'avoid_ingredient',
      ingredient_id: 'ing-gone',
      ingredient_name: null,
      ingredient_family: 'dairy',
    };
    expect(hiddenReasonLabel(noName)).toBe('Contains dairy (ingredient)');
  });
});

describe('hiddenReasonHeadline', () => {
  it('returns empty string for no reasons', () => {
    expect(hiddenReasonHeadline([])).toBe('');
  });

  it('shows the first reason for a single reason', () => {
    expect(hiddenReasonHeadline([dairyCheese])).toBe('Hidden — Contains dairy (Cheese)');
  });

  it('appends "(+N more)" for multi-reason items', () => {
    expect(hiddenReasonHeadline([dairyCheese, containsDairyTag, strict])).toBe(
      'Hidden — Contains dairy (Cheese) (+2 more)',
    );
  });
});
