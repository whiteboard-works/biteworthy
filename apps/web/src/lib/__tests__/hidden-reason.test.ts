import { describe, expect, it } from 'vitest';
import { hiddenReasonLabel } from '../hidden-reason';
import type { HideReason } from '../restaurants';

describe('hiddenReasonLabel (web mirror)', () => {
  it('formats avoid_ingredient as "Contains <family> (<name>)"', () => {
    const r: HideReason = {
      kind: 'avoid_ingredient',
      ingredient_id: 'i-1',
      ingredient_name: 'Cheese',
      ingredient_family: 'dairy',
    };
    expect(hiddenReasonLabel(r)).toBe('Contains dairy (Cheese)');
  });

  it('humanizes snake_case families (tree_nut → tree nut)', () => {
    const r: HideReason = {
      kind: 'avoid_ingredient',
      ingredient_id: 'i-1',
      ingredient_name: 'Almond',
      ingredient_family: 'tree_nut',
    };
    expect(hiddenReasonLabel(r)).toBe('Contains tree nut (Almond)');
  });

  it('formats avoid_tag as "Tagged <family>: <name>"', () => {
    const r: HideReason = {
      kind: 'avoid_tag',
      tag_id: 't-1',
      tag_name: 'Contains Dairy',
      tag_family: 'allergen',
    };
    expect(hiddenReasonLabel(r)).toBe('Tagged allergen: Contains Dairy');
  });

  it('formats unconfirmed_strict with the confidence + strict-mode note', () => {
    const r: HideReason = { kind: 'unconfirmed_strict', confidence: 'inferred' };
    expect(hiddenReasonLabel(r)).toBe('AI confidence: inferred (strict mode)');
  });

  it('falls back when family is null', () => {
    const r: HideReason = {
      kind: 'avoid_ingredient',
      ingredient_id: 'i-x',
      ingredient_name: 'Mystery',
      ingredient_family: null,
    };
    expect(hiddenReasonLabel(r)).toBe('Contains restricted (Mystery)');
  });
});
