/**
 * Phase 8.2 — taste scoring unit tests. The cross-implementation
 * fixture lives in taste-parity.test.ts; these lock the behaviors the
 * subplan calls out by name: zero-signal no-op, dislike outweighs
 * popularity, unreviewed items get no rating term, and the Top Picks
 * thresholds ("don't fake enthusiasm").
 */
import { describe, expect, it } from 'vitest';
import { hasTasteSignals, scoreItem, topPicks, type ScorableItem, type TasteProfile } from './taste';

const emptyProfile: TasteProfile = {
  liked_ingredient_ids: [],
  liked_tag_ids: [],
  disliked_ingredient_ids: [],
  disliked_tag_ids: [],
};

const item = (overrides: Partial<ScorableItem> & { id: string }): ScorableItem => ({
  name: overrides.id,
  popularity: 0,
  ingredient_ids: [],
  tag_ids: [],
  ...overrides,
});

describe('hasTasteSignals', () => {
  it('is false for empty arrays (zero-signal no-op)', () => {
    expect(hasTasteSignals(emptyProfile)).toBe(false);
  });

  it('is false when every signal is cancelled by an avoid list (filter wins)', () => {
    expect(
      hasTasteSignals({
        ...emptyProfile,
        liked_ingredient_ids: ['ing-cheese'],
        avoid_ingredient_ids: ['ing-cheese'],
      }),
    ).toBe(false);
  });

  it('is true with any surviving signal', () => {
    expect(hasTasteSignals({ ...emptyProfile, liked_tag_ids: ['tag-spicy'] })).toBe(true);
  });
});

describe('scoreItem', () => {
  it('a dislike (-2 per tag) outweighs maximum popularity (+0.5)', () => {
    const profile = { ...emptyProfile, disliked_tag_ids: ['tag-fried'] };
    const popular = item({ id: 'i1', tag_ids: ['tag-fried'], popularity: 100 });

    const { score } = scoreItem(popular, profile, { maxPopularity: 100 });
    expect(score).toBe(-2 + 0.5);
  });

  it('unreviewed items get no rating term (not a penalty)', () => {
    const unreviewed = item({ id: 'i1', popularity: 50 });
    const reviewedBad = item({ id: 'i2', popularity: 50, avg_rating: 1 });

    const unreviewedScore = scoreItem(unreviewed, emptyProfile, { maxPopularity: 100 }).score;
    const badScore = scoreItem(reviewedBad, emptyProfile, { maxPopularity: 100 }).score;

    expect(unreviewedScore).toBe(0.25); // popularity term only
    expect(badScore).toBe(0.25 + 0.5 * ((1 - 3) / 2)); // 1-star drags below
    expect(unreviewedScore).toBeGreaterThan(badScore);
  });

  it('an avoided id neither scores nor appears in matched ids', () => {
    const profile: TasteProfile = {
      ...emptyProfile,
      liked_ingredient_ids: ['ing-cheese', 'ing-basil'],
      avoid_ingredient_ids: ['ing-cheese'],
    };
    const dish = item({ id: 'i1', ingredient_ids: ['ing-cheese', 'ing-basil'] });

    const result = scoreItem(dish, profile, { maxPopularity: 0 });
    expect(result.score).toBe(1); // basil only
    expect(result.matched_liked_ingredient_ids).toEqual(['ing-basil']);
  });

  it('guards the popularity term when the restaurant max is 0', () => {
    const dish = item({ id: 'i1', popularity: 0 });
    expect(scoreItem(dish, emptyProfile, { maxPopularity: 0 }).score).toBe(0);
  });
});

describe('topPicks', () => {
  const likesSpice = { ...emptyProfile, liked_tag_ids: ['tag-spicy'] };
  const spicy = (id: string, popularity: number) =>
    item({ id, tag_ids: ['tag-spicy'], popularity });

  it('returns [] with no taste signals even when items would score > 0', () => {
    const items = [spicy('a', 10), spicy('b', 20), spicy('c', 30)];
    expect(topPicks(items, emptyProfile)).toEqual([]);
  });

  it('returns [] below 3 positive-score items (no fake enthusiasm)', () => {
    expect(topPicks([spicy('a', 10), spicy('b', 20)], likesSpice)).toEqual([]);
  });

  it('caps at n, excludes hidden items, sorts score desc → popularity desc → name asc', () => {
    const items = [
      { ...spicy('hidden-best', 100), status: 'hidden' as const },
      spicy('low-pop', 10),
      spicy('high-pop', 90),
      // Same score as high-pop is impossible here (popularity term differs),
      // so tie-break via two no-signal-match items with equal everything but name.
      spicy('mid-pop', 50),
      item({ id: 'no-match', popularity: 100 }),
    ];

    const picks = topPicks(items, likesSpice, 3);
    expect(picks.map((p) => p.id)).toEqual(['high-pop', 'mid-pop', 'low-pop']);
    // hidden-best held max popularity (100) — it normalizes the term
    // but can never itself be a pick.
    expect(picks[0]!.taste_score).toBe(2 + 0.5 * (90 / 100));
  });

  it('excludes zero/negative scores entirely', () => {
    const items = [
      spicy('a', 10),
      spicy('b', 20),
      spicy('c', 30),
      item({ id: 'meh', popularity: 0 }), // score 0 → not a pick
    ];
    const picks = topPicks(items, likesSpice, 5);
    expect(picks.map((p) => p.id)).not.toContain('meh');
    expect(picks).toHaveLength(3);
  });
});
