'use client';

import type { ReactElement } from 'react';
import type { RestaurantItem } from '../../../lib/restaurants';
import { HiddenReasonChip } from './RestaurantClient';

/**
 * Phase 4.11.4 / post-5 — single menu-item row, extracted from
 * RestaurantClient so render tests can target it directly.
 *
 * The original Phase 4.11.4 PR (#169) deferred a render snapshot
 * for the dish-photo `<img>` because the test infra wasn't wired
 * yet. PR #189 wired `@testing-library/react` + jsdom; this PR
 * extracts ItemRow + ships the deferred snapshot.
 *
 * Behavior is byte-identical to the previous in-file version of
 * ItemRow — no logic changes, just a file boundary.
 */
export interface ItemRowProps {
  item: RestaurantItem;
  restaurantSlug: string;
  hidden?: boolean;
  overridden: boolean;
  onToggleOverride: (itemId: string) => void;
  onSetPersistentOverride: (itemId: string, next: boolean) => void;
}

export function ItemRow({
  item,
  restaurantSlug,
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
  return (
    <li
      data-testid={`item-${item.id}`}
      className={['py-bw-3', hidden ? 'opacity-60' : ''].join(' ')}
    >
      {item.photo_url && (
        // Phase 4.11.4 — cropped dish photo from the source menu page.
        // Plain <img> (not next/image) since the URL is a Rails signed
        // blob URL whose host varies per env; loader config would have
        // to learn each one. Lazy-load + fixed max-height avoid CLS.
        <img
          src={item.photo_url}
          alt={item.name}
          loading="lazy"
          data-testid={`item-photo-${item.id}`}
          className="mb-bw-2 h-48 w-full rounded-bw-md object-cover"
        />
      )}
      <p className={['font-semibold', hidden ? 'text-hide' : 'text-zinc-900'].join(' ')}>
        {item.name}
      </p>
      {item.description && (
        <p className="mt-1 text-bw-sm text-zinc-500">{item.description}</p>
      )}
      <a
        href={`/restaurants/${encodeURIComponent(restaurantSlug)}/items/${encodeURIComponent(item.id)}`}
        data-testid={`open-item-${item.id}`}
        className="mt-1 inline-block text-bw-xs font-semibold text-bite hover:text-bite-dark"
      >
        {reviewsCount === 0
          ? 'Be the first to review'
          : `${reviewsCount} review${reviewsCount === 1 ? '' : 's'} →`}
      </a>

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
    </li>
  );
}
