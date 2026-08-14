/**
 * Phase 8.4 — Top Picks selection over SERVER-supplied taste scores.
 *
 * Scoring itself is `apps/api/app/services/taste_scoring.rb` and lives
 * only there; the items endpoint emits `taste_score` / `taste_reasons`
 * per item and these helpers just pick and phrase. `TasteScoring`'s
 * regression fixture is `fixtures/taste-parity.json`, asserted by
 * `apps/api/spec/services/taste_scoring_spec.rb`.
 *
 * Design principle: **safety filters, taste ranks.** Scores reorder
 * and highlight the items the filter already allowed; they never
 * hide anything. If a change here is about to hide an item, stop.
 */

import type { ItemStatus } from './index';

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
  status: ItemStatus;
  taste_score?: number | null;
  taste_reasons?: TasteReason[];
}

/**
 * Select Top Picks from SERVER-scored items — the UI path (web +
 * mobile both render from this; neither recomputes scores). The n
 * highest-scoring visible items with score > 0, and nothing at all
 * below MIN_POSITIVE_PICKS ("don't fake enthusiasm"). Null scores
 * (anonymous / zero-signal payloads) never qualify, so legacy pages
 * render unchanged.
 */
export function topPicksFromScores<T extends ScoredWireItem>(
  items: T[],
  n = TOP_PICKS_COUNT,
): T[] {
  const positive = items.filter(
    (i) => i.status === 'visible' && typeof i.taste_score === 'number' && i.taste_score > 0,
  );
  if (positive.length < MIN_POSITIVE_PICKS) return [];
  // Score, then name. There was a `popularity DESC` tie-break between the
  // two; the server never wrote that field, so it tied on every pair it
  // was asked about, and the column is gone. Removing it changes no
  // ordering that has ever been rendered.
  return [...positive]
    .sort((a, b) => b.taste_score! - a.taste_score! || a.name.localeCompare(b.name))
    .slice(0, n);
}

/**
 * "Because you like Spicy & Basil" — the one-line explainer per
 * pick, built from the names the server enriched into taste_reasons.
 * Null when there are no named reasons (the pick scored on its
 * rating alone).
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
