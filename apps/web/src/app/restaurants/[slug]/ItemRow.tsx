'use client';

import type { ReactElement } from 'react';
import type { RestaurantItem } from '../../../lib/restaurants';
import { HiddenReasonChip } from './RestaurantClient';

/**
 * Phase 4.11.4 / post-5 — single menu-item card, extracted from
 * RestaurantClient so render tests can target it directly.
 *
 * The original Phase 4.11.4 PR (#169) deferred a render snapshot
 * for the dish-photo `<img>` because the test infra wasn't wired
 * yet. PR #189 wired `@testing-library/react` + jsdom; this PR
 * extracts ItemRow + ships the deferred snapshot.
 *
 * Renders as a card. The dish name links to the detail page; a photo,
 * when one exists, sits above the text. Photo-less items render as
 * compact text cards — a media block has to be earned by a real photo.
 */
export interface ItemRowProps {
  item: RestaurantItem;
  restaurantSlug: string;
  /** Carried onto the item link so the diet survives the hop + back. */
  presetSlug?: string | null;
  hidden?: boolean;
  overridden: boolean;
  onToggleOverride: (itemId: string) => void;
  onSetPersistentOverride: (itemId: string, next: boolean) => void;
}

export function ItemRow({
  item,
  restaurantSlug,
  presetSlug = null,
  hidden = false,
  overridden,
  onToggleOverride,
  onSetPersistentOverride,
}: ItemRowProps): ReactElement {
  // Item shown in the visible list but with reasons[] = the user
  // tapped "Show anyway" (session) or set "never hide" (persistent).
  // Keep chips visible as a transparency cue.
  const showChips = hidden || overridden;
  const persistent = item.overridden_by_user === true;
  const reviewsCount = item.reviews_count ?? 0;
  const itemHref = `/restaurants/${encodeURIComponent(restaurantSlug)}/items/${encodeURIComponent(item.id)}${presetSlug ? `?profile=${encodeURIComponent(presetSlug)}` : ''}`;
  return (
    <li
      data-testid={`item-${item.id}`}
      className={[
        'flex flex-col overflow-hidden rounded-bw-lg border border-zinc-200 bg-white',
        hidden ? 'opacity-60' : '',
      ].join(' ')}
    >
      {item.photo_url && (
        // Cropped dish photo from the source menu page. Plain <img> (not
        // next/image) since the URL is a Rails signed blob URL whose host
        // varies per env; loader config would have to learn each one.
        <img
          src={item.photo_url}
          alt={item.name}
          loading="lazy"
          data-testid={`item-photo-${item.id}`}
          className="h-40 w-full object-cover"
        />
      )}
      <div className="flex flex-1 flex-col p-bw-3">
        <p className="font-semibold">
          {/* The name is the card's way into the dish page. The underline
              is always on: hover styling alone leaves no visible link
              affordance on touch screens or under keyboard focus. */}
          <a
            href={itemHref}
            data-testid={`open-item-${item.id}`}
            className={`underline decoration-zinc-300 underline-offset-2 hover:decoration-bite ${hidden ? 'text-hide' : 'text-zinc-900 hover:text-bite-dark'}`}
          >
            {item.name}
          </a>
        </p>
        {item.description && <p className="mt-1 text-bw-sm text-zinc-500">{item.description}</p>}
        {reviewsCount > 0 && (
          <p className="mt-1 text-bw-xs">
            <a href={itemHref} className="text-zinc-500 hover:text-bite-dark hover:underline">
              {reviewsCount} review{reviewsCount === 1 ? '' : 's'}
            </a>
          </p>
        )}

        {showChips && item.reasons.length > 0 && (
          <div className="mt-bw-2 flex flex-wrap gap-bw-1">
            {item.reasons.map((r, idx) => (
              <HiddenReasonChip key={idx} reason={r} />
            ))}
          </div>
        )}

        {item.reasons.length > 0 && (
          <div className="mt-bw-2 flex flex-wrap gap-bw-3 text-bw-sm font-semibold">
            {persistent ? (
              <button
                type="button"
                onClick={() => onSetPersistentOverride(item.id, false)}
                data-testid={`undo-never-hide-${item.id}`}
                className="text-bite hover:text-bite-dark"
              >
                Always shown — undo
              </button>
            ) : (
              <>
                <button
                  type="button"
                  onClick={() => onToggleOverride(item.id)}
                  className="text-bite hover:text-bite-dark"
                >
                  {overridden ? 'Hide again' : 'Show anyway'}
                </button>
                {overridden && (
                  <button
                    type="button"
                    onClick={() => onSetPersistentOverride(item.id, true)}
                    data-testid={`set-never-hide-${item.id}`}
                    className="text-zinc-600 hover:text-zinc-800"
                  >
                    Never hide this dish
                  </button>
                )}
              </>
            )}
          </div>
        )}
      </div>
    </li>
  );
}
