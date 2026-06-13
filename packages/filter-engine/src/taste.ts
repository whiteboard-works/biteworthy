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

/** Minimum positive-score items before a Top Picks row may render. */
export const MIN_POSITIVE_PICKS = 3;
/** Default Top Picks length. */
export const TOP_PICKS_COUNT = 5;

/**
 * The wire shape the items endpoint emits per item (Phase 8.2) —
 * what the Top Picks UIs (web + mobile) select from. `taste_score`
 * is null/absent for anonymous and zero-signal callers.
 */
export type TasteReason =
  | { kind: 'liked_tag'; tag_id: string; tag_name: string | null }
  | { kind: 'liked_ingredient'; ingredient_id: string; ingredient_name: string | null };

export interface ScoredWireItem {
  id: string;
  name: string;
  popularity: number;
  status: ItemStatus;
  taste_score?: number | null;
  taste_reasons?: TasteReason[];
}

/**
 * Select Top Picks from SERVER-scored items — the UI path (web +
 * mobile both render from this; neither recomputes scores). Same
 * thresholds as `topPicks`: the n highest-scoring visible items with
 * score > 0, and nothing at all below MIN_POSITIVE_PICKS ("don't
 * fake enthusiasm"). Null scores (anonymous / zero-signal payloads)
 * never qualify, so legacy pages render unchanged.
 */
export function topPicksFromScores<T extends ScoredWireItem>(
  items: T[],
  n = TOP_PICKS_COUNT,
): T[] {
  const positive = items.filter(
    (i) => i.status === 'visible' && typeof i.taste_score === 'number' && i.taste_score > 0,
  );
  if (positive.length < MIN_POSITIVE_PICKS) return [];
  return [...positive]
    .sort(
      (a, b) =>
        b.taste_score! - a.taste_score! ||
        b.popularity - a.popularity ||
        a.name.localeCompare(b.name),
    )
    .slice(0, n);
}

/**
 * "Because you like Spicy & Basil" — the one-line explainer per
 * pick, built from the names the server enriched into taste_reasons.
 * Null when there are no named reasons (the pick scored on
 * popularity/rating alone).
 */
export function tasteReasonLine(reasons: TasteReason[] | undefined): string | null {
  const names = (reasons ?? [])
    .map((r) => (r.kind === 'liked_tag' ? r.tag_name : r.ingredient_name))
    .filter((n): n is string => !!n);
  if (names.length === 0) return null;
  const list =
    names.length === 1
      ? names[0]
      : `${names.slice(0, -1).join(', ')} & ${names[names.length - 1]}`;
  return `Because you like ${list}`;
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
  n = TOP_PICKS_COUNT,
): Array<T & { taste_score: number }> {
  if (!hasTasteSignals(profile)) return [];

  const maxPopularity = items.reduce((max, i) => Math.max(max, i.popularity), 0);
  const positive = items
    .filter((i) => i.status !== 'hidden')
    .map((i) => ({ ...i, taste_score: scoreItem(i, profile, { maxPopularity }).score }))
    .filter((i) => i.taste_score > 0);

  if (positive.length < MIN_POSITIVE_PICKS) return [];

  positive.sort(
    (a, b) =>
      b.taste_score - a.taste_score ||
      b.popularity - a.popularity ||
      (a.name ?? '').localeCompare(b.name ?? ''),
  );
  return positive.slice(0, n);
}
