'use client';

import { useState } from 'react';
import type { RestaurantItem, TasteReason } from '../../../lib/restaurants';

/**
 * Phase 8.3 — "Top picks for you", rendered above the menu sections.
 *
 * Uses the SERVER's taste_score/taste_reasons (Phase 8.2) — the
 * client never recomputes scores here, it just selects. Thresholds
 * mirror filter-engine's topPicks: the 5 highest-scoring visible
 * items with score > 0, and nothing at all below 3 positive items
 * (don't fake enthusiasm). Anonymous and zero-signal users have
 * taste_score = null on every item, so this renders nothing and the
 * page is byte-identical to the pre-8.3 layout.
 *
 * Copy rule: taste ≠ safety. Nothing here may imply a low-scored
 * item is unsafe — the picks are "more likely to enjoy", the rest of
 * the menu is exactly as safe as the filter says.
 */

const TOP_PICKS_COUNT = 5;
const MIN_POSITIVE_PICKS = 3;

export function topPicksFromScores(items: RestaurantItem[]): RestaurantItem[] {
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
    .slice(0, TOP_PICKS_COUNT);
}

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

export function TopPicksRow({
  items,
  restaurantSlug,
}: {
  items: RestaurantItem[];
  restaurantSlug: string;
}) {
  const [whyOpen, setWhyOpen] = useState(false);
  const picks = topPicksFromScores(items);
  if (picks.length === 0) return null;

  return (
    <section data-testid="top-picks" className="mt-bw-6">
      <div className="flex items-baseline gap-bw-2">
        <h2 className="text-bw-lg font-bold">Top picks for you</h2>
        <button
          type="button"
          data-testid="why-these"
          aria-expanded={whyOpen}
          onClick={() => setWhyOpen((v) => !v)}
          className="text-bw-xs font-semibold text-bite hover:text-bite-dark"
        >
          Why these?
        </button>
      </div>
      {whyOpen && (
        <p data-testid="why-these-explainer" className="mt-bw-1 text-bw-sm text-zinc-500">
          Ranked from the tags and ingredients you said you love in your taste profile.
          Everything below passed your dietary filter too — these are just the dishes
          you&rsquo;re most likely to enjoy.
        </p>
      )}
      <ul className="mt-bw-2 flex gap-bw-3 overflow-x-auto pb-bw-2">
        {picks.map((item) => {
          const reason = tasteReasonLine(item.taste_reasons);
          return (
            <li
              key={item.id}
              data-testid={`top-pick-${item.id}`}
              className="w-44 shrink-0 rounded-bw-md border border-zinc-200 p-bw-2"
            >
              <a
                href={`/restaurants/${encodeURIComponent(restaurantSlug)}/items/${encodeURIComponent(item.id)}`}
                className="block"
              >
                {item.photo_url && (
                  <img
                    src={item.photo_url}
                    alt={item.name}
                    loading="lazy"
                    className="mb-bw-2 h-28 w-full rounded-bw-md object-cover"
                  />
                )}
                <p className="text-bw-sm font-semibold text-zinc-900">{item.name}</p>
                {reason && (
                  <p
                    data-testid={`pick-reason-${item.id}`}
                    className="mt-1 text-bw-xs text-bite-dark"
                  >
                    {reason}
                  </p>
                )}
              </a>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
