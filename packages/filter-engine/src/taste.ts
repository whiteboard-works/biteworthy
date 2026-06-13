/**
 * Phase 8.2 — the taste scoring engine (TS side).
 *
 * Mirrors `apps/api/app/services/taste_scoring.rb` EXACTLY — both
 * implementations assert against the shared fixture at
 * `fixtures/taste-parity.json`, and the repo rule is they change in
 * the same PR or not at all.
 *
 * Design principle: **safety filters, taste ranks.** Scores reorder
 * and highlight the items the filter already allowed; they never
 * hide anything. If a change here is about to hide an item, stop.
 */

import type { ItemStatus } from './index';

/** One place per implementation — the Ruby twin is TasteScoring::WEIGHTS. */
export const TASTE_WEIGHTS = {
  liked_tag: 2.0,
  liked_ingredient: 1.0,
  disliked_tag: 2.0, // subtracted
  disliked_ingredient: 1.0, // subtracted
  popularity: 0.5,
  rating: 0.5,
} as const;

/**
 * The four Phase 8.1 profile arrays, plus the avoid lists so scoring
 * can honor "filter wins": an id present in an avoid list is
 * subtracted from the taste signals before any intersection — it
 * neither scores nor shows up in matched ids.
 */
export interface TasteProfile {
  liked_ingredient_ids: string[];
  liked_tag_ids: string[];
  disliked_ingredient_ids: string[];
  disliked_tag_ids: string[];
  avoid_ingredient_ids?: string[];
  avoid_tag_ids?: string[];
}

/** Minimum item shape scoring needs. `avg_rating` is the visible-review
 * average (null/omitted when unreviewed — the rating term is then 0). */
export interface ScorableItem {
  id: string;
  name?: string;
  popularity: number;
  ingredient_ids: string[];
  tag_ids: string[];
  avg_rating?: number | null;
}

export interface TasteScore {
  score: number;
  /** Sorted ascending — same ORDER BY the SQL emits. */
  matched_liked_tag_ids: string[];
  matched_liked_ingredient_ids: string[];
}

export function hasTasteSignals(profile: TasteProfile): boolean {
  const effective = effectiveSignals(profile);
  return (
    effective.likedTags.size > 0 ||
    effective.likedIngredients.size > 0 ||
    effective.dislikedTags.size > 0 ||
    effective.dislikedIngredients.size > 0
  );
}

function effectiveSignals(profile: TasteProfile) {
  const avoidIngredients = new Set(profile.avoid_ingredient_ids ?? []);
  const avoidTags = new Set(profile.avoid_tag_ids ?? []);
  const minus = (ids: string[], avoid: Set<string>) => new Set(ids.filter((id) => !avoid.has(id)));
  return {
    likedTags: minus(profile.liked_tag_ids, avoidTags),
    likedIngredients: minus(profile.liked_ingredient_ids, avoidIngredients),
    dislikedTags: minus(profile.disliked_tag_ids, avoidTags),
    dislikedIngredients: minus(profile.disliked_ingredient_ids, avoidIngredients),
  };
}

/**
 * Score one item. `maxPopularity` must be the max popularity across
 * ALL published items at the restaurant (visible and hidden) — the
 * SQL computes it as a window over the whole restaurant; pass the
 * same scope or parity breaks. `topPicks` handles this for you.
 */
export function scoreItem(
  item: ScorableItem,
  profile: TasteProfile,
  opts: { maxPopularity: number },
): TasteScore {
  const { likedTags, likedIngredients, dislikedTags, dislikedIngredients } =
    effectiveSignals(profile);

  const matchedLikedTagIds = item.tag_ids.filter((t) => likedTags.has(t)).sort();
  const matchedLikedIngredientIds = item.ingredient_ids
    .filter((i) => likedIngredients.has(i))
    .sort();
  const dislikedTagCount = item.tag_ids.filter((t) => dislikedTags.has(t)).length;
  const dislikedIngredientCount = item.ingredient_ids.filter((i) =>
    dislikedIngredients.has(i),
  ).length;

  const popularityTerm =
    opts.maxPopularity > 0 ? item.popularity / opts.maxPopularity : 0;
  const ratingTerm = item.avg_rating == null ? 0 : (item.avg_rating - 3) / 2;

  const score =
    TASTE_WEIGHTS.liked_tag * matchedLikedTagIds.length +
    TASTE_WEIGHTS.liked_ingredient * matchedLikedIngredientIds.length -
    TASTE_WEIGHTS.disliked_tag * dislikedTagCount -
    TASTE_WEIGHTS.disliked_ingredient * dislikedIngredientCount +
    TASTE_WEIGHTS.popularity * popularityTerm +
    TASTE_WEIGHTS.rating * ratingTerm;

  return {
    score,
    matched_liked_tag_ids: matchedLikedTagIds,
    matched_liked_ingredient_ids: matchedLikedIngredientIds,
  };
}

/**
 * Top Picks = the n highest-scoring VISIBLE items with score > 0.
 * Fewer than 3 positive-score items → empty array (don't fake
 * enthusiasm). `items` should be every published item at the
 * restaurant — hidden items don't qualify as picks but they DO count
 * toward max popularity, matching the SQL window.
 */
export function topPicks<T extends ScorableItem & { status?: ItemStatus }>(
  items: T[],
  profile: TasteProfile,
  n = 5,
): Array<T & { taste_score: number }> {
  if (!hasTasteSignals(profile)) return [];

  const maxPopularity = items.reduce((max, i) => Math.max(max, i.popularity), 0);
  const positive = items
    .filter((i) => i.status !== 'hidden')
    .map((i) => ({ ...i, taste_score: scoreItem(i, profile, { maxPopularity }).score }))
    .filter((i) => i.taste_score > 0);

  if (positive.length < 3) return [];

  positive.sort(
    (a, b) =>
      b.taste_score - a.taste_score ||
      b.popularity - a.popularity ||
      (a.name ?? '').localeCompare(b.name ?? ''),
  );
  return positive.slice(0, n);
}
