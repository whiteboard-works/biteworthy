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
 * Now renders as a card (photo on top, content below) so the menu
 * lays out as a grid. Items with no `photo_url` get a deterministic
 * monogram placeholder so the grid never has empty photo slots.
 */
export interface ItemRowProps {
  item: RestaurantItem;
  restaurantSlug: string;
  hidden?: boolean;
  overridden: boolean;
  onToggleOverride: (itemId: string) => void;
  onSetPersistentOverride: (itemId: string, next: boolean) => void;
}

/**
 * Deterministic hue (0–359) from a stable string (the item id), so a
 * given dish always gets the same placeholder tint and the grid reads
 * as varied rather than a wall of identical gray boxes.
 */
function placeholderHue(seed: string): number {
  let hash = 0;
  for (let i = 0; i < seed.length; i++) {
    hash = (hash * 31 + seed.charCodeAt(i)) % 360;
  }
  return hash;
}

/**
 * The dish photo, or a monogram placeholder when the item has none.
 * Real photos keep the `item-photo-<id>` testid + `<img>` contract
 * from Phase 4.11.4; the placeholder uses a distinct testid so the
 * "no <img> when photo_url is null" contract still holds.
 */
function ItemPhoto({ item }: { item: RestaurantItem }): ReactElement {
  if (item.photo_url) {
    // Cropped dish photo from the source menu page. Plain <img> (not
    // next/image) since the URL is a Rails signed blob URL whose host
    // varies per env; loader config would have to learn each one.
    return (
      <img
        src={item.photo_url}
        alt={item.name}
        loading="lazy"
        data-testid={`item-photo-${item.id}`}
        className="h-40 w-full object-cover"
      />
    );
  }

  const hue = placeholderHue(item.id);
  const initial = (item.name.trim()[0] ?? '·').toUpperCase();
  return (
    <div
      role="img"
      aria-label={`${item.name} — no photo yet`}
      data-testid={`item-photo-placeholder-${item.id}`}
      className="flex h-40 w-full select-none items-center justify-center"
      style={{ backgroundColor: `hsl(${hue} 40% 90%)` }}
    >
      <span className="text-bw-4xl font-bold" style={{ color: `hsl(${hue} 32% 45%)` }}>
        {initial}
      </span>
    </div>
  );
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
      className={[
        'flex flex-col overflow-hidden rounded-bw-lg border border-zinc-200 bg-white',
        hidden ? 'opacity-60' : '',
      ].join(' ')}
    >
      <ItemPhoto item={item} />
      <div className="flex flex-1 flex-col p-bw-3">
        <p className={['font-semibold', hidden ? 'text-hide' : 'text-zinc-900'].join(' ')}>
          {item.name}
        </p>
        {item.description && <p className="mt-1 text-bw-sm text-zinc-500">{item.description}</p>}
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
      </div>
    </li>
  );
}
