'use client';

import { useState } from 'react';
import { tasteReasonLine, topPicksFromScores } from '@biteworthy/filter-engine';
import type { RestaurantItem } from '../../../../../../lib/restaurants';
import { DishPhotoPlaceholder, hasDishPhoto } from './ItemRow';

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
  basePath,
  signedIn,
  returnQuery,
}: {
  items: RestaurantItem[];
  basePath: string;
  signedIn: boolean;
  returnQuery: string;
}) {
  if (!signedIn) {
    return (
      <p
        data-testid="top-picks-signed-out"
        className="mt-bw-6 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark"
      >
        <a
          href={`/login?next=${encodeURIComponent(`${basePath}${returnQuery}`)}`}
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
  basePath,
  presetSlug = null,
  profileToken = null,
  signedIn = false,
}: {
  items: RestaurantItem[];
  /** Current (canonical) restaurant path — see RestaurantClient. */
  basePath: string;
  /** Carried onto pick links so the diet survives the hop, like the grid's. */
  presetSlug?: string | null;
  /** A share link's token; kept on the sign-in round trip like the preset. */
  profileToken?: string | null;
  /** Picks which empty-state message applies — see EmptyState above. */
  signedIn?: boolean;
}) {
  const [whyOpen, setWhyOpen] = useState(false);
  const picks = topPicksFromScores(items);
  const pickPlaceholders = picks.some(hasDishPhoto);
  if (picks.length === 0) {
    // Sign-in must bring them back to the menu as they were viewing it —
    // dropping the diet or share filter would show dishes it hid.
    const returnQuery = profileToken
      ? `?p=${encodeURIComponent(profileToken)}`
      : presetSlug
        ? `?profile=${encodeURIComponent(presetSlug)}`
        : '';
    return (
      <EmptyState items={items} basePath={basePath} signedIn={signedIn} returnQuery={returnQuery} />
    );
  }

  return (
    <section
      data-testid="top-picks"
      className="mt-bw-6 rounded-bw-lg border-2 border-bite bg-bite-light/50 p-bw-4"
    >
      <div className="flex flex-col gap-bw-1 sm:flex-row sm:items-baseline sm:gap-bw-3">
        <h2 className="text-bw-xl font-bold leading-tight text-bite-dark sm:text-bw-2xl">
          Your best bets here
        </h2>
        <div className="flex flex-wrap items-baseline gap-x-bw-4 sm:flex-1">
          <button
            type="button"
            data-testid="why-these"
            aria-expanded={whyOpen}
            onClick={() => setWhyOpen((v) => !v)}
            className="py-bw-1 text-bw-xs font-semibold text-bite hover:text-bite-dark"
          >
            Why these?
          </button>
          <a
            href="/onboarding?step=taste"
            data-testid="improve-picks"
            className="ml-auto py-bw-1 text-bw-xs font-semibold text-bite hover:text-bite-dark"
          >
            Improve my picks
          </a>
        </div>
      </div>
      {whyOpen && (
        <p data-testid="why-these-explainer" className="mt-bw-2 text-bw-sm text-bite-dark/80">
          Ranked from the tags and ingredients you said you love in your taste profile. Everything
          below passed your dietary filter too — these are just the dishes you&rsquo;re most likely
          to enjoy.
        </p>
      )}
      <ul className="-mx-bw-4 mt-bw-4 flex snap-x snap-proximity scroll-px-bw-4 gap-bw-3 overflow-x-auto px-bw-4 pb-bw-2">
        {picks.map((item) => {
          const reason = tasteReasonLine(item.taste_reasons);
          return (
            <li
              key={item.id}
              data-testid={`top-pick-${item.id}`}
              className="w-44 shrink-0 snap-start rounded-bw-lg border border-bite/40 bg-white p-bw-3 shadow-sm sm:w-48"
            >
              <a
                href={`${basePath}/items/${encodeURIComponent(item.id)}${presetSlug ? `?profile=${encodeURIComponent(presetSlug)}` : ''}`}
                className="block"
              >
                {!hasDishPhoto(item) && pickPlaceholders && (
                  <DishPhotoPlaceholder
                    className="mb-bw-2 flex h-24 w-full rounded-bw-md sm:h-28"
                    testId={`pick-photo-placeholder-${item.id}`}
                  />
                )}
                {hasDishPhoto(item) && (
                  <img
                    src={item.photo_urls?.card || item.photo_url || undefined}
                    srcSet={
                      item.photo_urls
                        ? `${item.photo_urls.thumb} 200w, ${item.photo_urls.card} 600w`
                        : undefined
                    }
                    sizes="(min-width: 640px) 168px, 152px"
                    alt={item.name}
                    loading="lazy"
                    className="mb-bw-2 h-24 w-full rounded-bw-md object-cover sm:h-28"
                    onError={(e) => {
                      // Fall back to original photo_url if variant fails
                      if (item.photo_url && e.currentTarget.src !== item.photo_url) {
                        e.currentTarget.src = item.photo_url;
                        e.currentTarget.srcset = '';
                      }
                    }}
                  />
                )}
                <p className="text-bw-sm font-bold leading-snug text-zinc-900 sm:text-bw-base">
                  {item.name}
                </p>
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
