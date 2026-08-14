/**
 * Phase 8.4 — the UI-side Top Picks selector (web + mobile both import
 * these, so the thresholds can't drift between surfaces). Scoring is
 * `TasteScoring` on the server; these only pick and phrase.
 */
import { describe, expect, it } from 'vitest';
import { tasteReasonLine, topPicksFromScores, type ScoredWireItem } from './taste';

describe('topPicksFromScores (server-scored wire items)', () => {
  const wire = (
    id: string,
    taste_score: number | null | undefined,
    status: 'visible' | 'hidden' = 'visible',
  ): ScoredWireItem => ({ id, name: id, status, taste_score });

  it('returns [] when scores are null (anonymous / zero-signal payload)', () => {
    expect(topPicksFromScores([wire('a', null), wire('b', null), wire('c', null)])).toEqual([]);
  });

  it('returns [] below 3 positive-score items', () => {
    expect(topPicksFromScores([wire('a', 2), wire('b', 1), wire('c', 0)])).toEqual([]);
  });

  it('excludes hidden items, caps at 5, sorts score → name', () => {
    const items = [
      wire('hidden-best', 9, 'hidden'),
      wire('f', 1),
      wire('e', 2),
      wire('d', 3),
      wire('tie-z', 4),
      wire('tie-a', 4),
      wire('best', 5),
    ];
    expect(topPicksFromScores(items).map((i) => i.id)).toEqual([
      'best',
      'tie-a',
      'tie-z',
      'd',
      'e',
    ]);
  });
});

describe('tasteReasonLine', () => {
  it('joins names across kinds with commas and an ampersand', () => {
    expect(
      tasteReasonLine([
        { kind: 'liked_tag', tag_id: 't1', tag_name: 'Spicy' },
        { kind: 'liked_tag', tag_id: 't2', tag_name: 'Thai' },
        { kind: 'liked_ingredient', ingredient_id: 'i1', ingredient_name: 'Basil' },
      ]),
    ).toBe('Because you like Spicy, Thai & Basil');
  });

  it('single name, null names, and undefined all behave', () => {
    expect(tasteReasonLine([{ kind: 'liked_tag', tag_id: 't1', tag_name: 'Spicy' }])).toBe(
      'Because you like Spicy',
    );
    expect(tasteReasonLine([{ kind: 'liked_tag', tag_id: 't1', tag_name: null }])).toBeNull();
    expect(tasteReasonLine(undefined)).toBeNull();
  });
});
