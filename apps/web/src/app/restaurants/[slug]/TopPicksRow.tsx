'use client';

import { useState } from 'react';
import { tasteReasonLine, topPicksFromScores } from '@biteworthy/filter-engine';
import type { RestaurantItem } from '../../../lib/restaurants';

/**
 * Phase 8.3 — "Top picks for you", rendered above the menu sections.
 *
 * Uses the SERVER's taste_score/taste_reasons (Phase 8.2) — the
 * client never recomputes scores here, it just selects via
 * filter-engine's shared `topPicksFromScores` (Phase 8.4 moved the
 * selector there so web + mobile can't drift). Anonymous and
 * zero-signal users have taste_score = null on every item, so this
 * renders nothing and the page is byte-identical to the pre-8.3
 * layout.
 *
 * Copy rule: taste ≠ safety. Nothing here may imply a low-scored
 * item is unsafe — the picks are "more likely to enjoy", the rest of
 * the menu is exactly as safe as the filter says.
 */

export { tasteReasonLine, topPicksFromScores };

export function TopPicksRow({
  items,
  restaurantSlug,
  presetSlug = null,
}: {
  items: RestaurantItem[];
  restaurantSlug: string;
  /** Carried onto pick links so the diet survives the hop, like the grid's. */
  presetSlug?: string | null;
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
        <a
          href="/onboarding?step=taste"
          data-testid="improve-picks"
          className="ml-auto text-bw-xs font-semibold text-bite hover:text-bite-dark"
        >
          Improve my picks
        </a>
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
                href={`/restaurants/${encodeURIComponent(restaurantSlug)}/items/${encodeURIComponent(item.id)}${presetSlug ? `?profile=${encodeURIComponent(presetSlug)}` : ''}`}
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
