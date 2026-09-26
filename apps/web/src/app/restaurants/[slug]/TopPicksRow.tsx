'use client';

import { useState } from 'react';
import { tasteReasonLine, topPicksFromScores } from '@biteworthy/filter-engine';
import type { RestaurantItem } from '../../../lib/restaurants';

/**
 * Phase 8.3 — "Your best bets here", rendered above the menu sections.
 *
 * Uses the SERVER's taste_score/taste_reasons (Phase 8.2) — the
 * client never recomputes scores here, it just selects via
 * filter-engine's shared `topPicksFromScores` (Phase 8.4 moved the
 * selector there so web + mobile can't drift).
 *
 * Copy rule: taste ≠ safety. Nothing here may imply a low-scored
 * item is unsafe — the picks are "more likely to enjoy", the rest of
 * the menu is exactly as safe as the filter says.
 *
 * Menu-page hierarchy pass — Top Picks is the page's visual payoff
 * now (bigger accented cards, prominent heading), and the empty case
 * explains itself instead of silently rendering nothing: signed-out
 * visitors get pointed at sign-in, signed-in visitors with no taste
 * signals anywhere get pointed at rating dishes, and visitors already
 * partway there get a quiet nudge rather than either message.
 */

export { tasteReasonLine, topPicksFromScores };

function EmptyState({
  items,
  restaurantSlug,
  signedIn,
}: {
  items: RestaurantItem[];
  restaurantSlug: string;
  signedIn: boolean;
}) {
  if (!signedIn) {
    return (
      <p
        data-testid="top-picks-signed-out"
        className="mt-bw-6 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark"
      >
        <a
          href={`/login?next=${encodeURIComponent(`/restaurants/${restaurantSlug}`)}`}
          data-testid="top-picks-sign-in-link"
          className="font-semibold underline hover:text-bite"
        >
          Sign in
        </a>{' '}
        and save a few dishes you like to see your best bets here.
      </p>
    );
  }

  const hasAnyScore = items.some((i) => typeof i.taste_score === 'number');
  if (!hasAnyScore) {
    return (
      <p
        data-testid="top-picks-no-signals"
        className="mt-bw-6 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark"
      >
        Save or rate dishes you like and we&rsquo;ll pick your best bets.
      </p>
    );
  }

  // Signed in with some taste signal, just not enough positive scores
  // yet to clear MIN_POSITIVE_PICKS — a quiet nudge, not a full banner.
  return (
    <p data-testid="top-picks-almost" className="mt-bw-4 text-bw-xs text-zinc-400">
      Rate a couple more dishes you like and we&rsquo;ll surface your best bets here.
    </p>
  );
}

export function TopPicksRow({
  items,
  restaurantSlug,
  presetSlug = null,
  signedIn = false,
}: {
  items: RestaurantItem[];
  restaurantSlug: string;
  /** Carried onto pick links so the diet survives the hop, like the grid's. */
  presetSlug?: string | null;
  /** Picks which empty-state message applies — see EmptyState above. */
  signedIn?: boolean;
}) {
  const [whyOpen, setWhyOpen] = useState(false);
  const picks = topPicksFromScores(items);
  if (picks.length === 0) {
    return <EmptyState items={items} restaurantSlug={restaurantSlug} signedIn={signedIn} />;
  }

  return (
    <section
      data-testid="top-picks"
      className="mt-bw-6 rounded-bw-lg border-2 border-bite bg-bite-light/50 p-bw-4"
    >
      <div className="flex items-baseline gap-bw-2">
        <h2 className="text-bw-2xl font-bold text-bite-dark">Your best bets here</h2>
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
        <p data-testid="why-these-explainer" className="mt-bw-1 text-bw-sm text-bite-dark/80">
          Ranked from the tags and ingredients you said you love in your taste profile. Everything
          below passed your dietary filter too — these are just the dishes you&rsquo;re most likely
          to enjoy.
        </p>
      )}
      <ul className="mt-bw-3 flex gap-bw-3 overflow-x-auto pb-bw-2">
        {picks.map((item) => {
          const reason = tasteReasonLine(item.taste_reasons);
          return (
            <li
              key={item.id}
              data-testid={`top-pick-${item.id}`}
              className="w-48 shrink-0 rounded-bw-lg border border-bite bg-white p-bw-3 shadow-sm"
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
                <p className="text-bw-base font-bold text-zinc-900">{item.name}</p>
                {reason && (
                  <p
                    data-testid={`pick-reason-${item.id}`}
                    className="mt-1 text-bw-xs font-semibold text-bite-dark"
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
