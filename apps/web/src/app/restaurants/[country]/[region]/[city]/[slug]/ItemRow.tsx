'use client';

import type { ReactElement } from 'react';
import type { RestaurantItem } from '../../../../../../lib/restaurants';
import { HiddenReasonChip } from './SectionList';

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
 * compact text cards, unless `photoPlaceholder` is set: in a grid where
 * other dishes have photos, a lone text card breaks the rows up, so it
 * gets a same-height placeholder tile instead. A grid with no photos at
 * all stays compact rather than becoming a wall of empty tiles, and so
 * does the single-column phone layout, where there are no rows to align.
 */
export function hasDishPhoto(item: RestaurantItem): boolean {
  return Boolean(item.photo_urls?.card || item.photo_url);
}

/** Decorative stand-in for a missing dish photo: a plate, set for a meal. */
export function DishPhotoPlaceholder({
  className,
  testId,
}: {
  className: string;
  testId: string;
}): ReactElement {
  return (
    <div
      aria-hidden="true"
      data-testid={testId}
      className={`items-center justify-center bg-zinc-100 text-zinc-300 ${className}`}
    >
      <svg
        viewBox="0 0 48 48"
        className="h-12 w-12"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
      >
        <circle cx="24" cy="24" r="11" />
        <circle cx="24" cy="24" r="6" />
        <path d="M6 12v8a3 3 0 0 0 3 3v13M9 12v8M12 12v8" />
        <path d="M40 12c-2 0-3 4-3 9h3v15" />
      </svg>
    </div>
  );
}

export interface ItemRowProps {
  item: RestaurantItem;
  basePath: string;
  /** Carried onto the item link so the diet survives the hop + back. */
  presetSlug?: string | null;
  hidden?: boolean;
  /** Show a placeholder tile when this dish has no photo. */
  photoPlaceholder?: boolean;
  overridden: boolean;
  onToggleOverride: (itemId: string) => void;
  onSetPersistentOverride: (itemId: string, next: boolean) => void;
}

export function ItemRow({
  item,
  basePath,
  presetSlug = null,
  hidden = false,
  photoPlaceholder = false,
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
  const itemHref = `${basePath}/items/${encodeURIComponent(item.id)}${presetSlug ? `?profile=${encodeURIComponent(presetSlug)}` : ''}`;
  return (
    <li
      data-testid={`item-${item.id}`}
      className={[
        'flex flex-col overflow-hidden rounded-bw-lg border border-zinc-200 bg-white',
        hidden ? 'opacity-60' : '',
      ].join(' ')}
    >
      {!hasDishPhoto(item) && photoPlaceholder && (
        <DishPhotoPlaceholder
          className="hidden h-40 w-full sm:flex"
          testId={`item-photo-placeholder-${item.id}`}
        />
      )}
      {hasDishPhoto(item) && (
        // Cropped dish photo from the source menu page. Plain <img> (not
        // next/image) since the URL is a Rails signed blob URL whose host
        // varies per env; loader config would have to learn each one.
        // Use WebP card variant with fallback to original on error.
        <img
          src={item.photo_urls?.card || item.photo_url || undefined}
          srcSet={
            item.photo_urls
              ? `${item.photo_urls.thumb} 200w, ${item.photo_urls.card} 600w`
              : undefined
          }
          sizes="(max-width: 640px) 100vw, 600px"
          alt={item.name}
          loading="lazy"
          data-testid={`item-photo-${item.id}`}
          className="h-40 w-full object-cover"
          onError={(e) => {
            // Fall back to original photo_url if variant fails
            if (item.photo_url && e.currentTarget.src !== item.photo_url) {
              e.currentTarget.src = item.photo_url;
              e.currentTarget.srcset = '';
            }
          }}
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
        {!hasDishPhoto(item) && (
          <p className="mt-2">
            <a
              href={`${itemHref}${itemHref.includes('?') ? '&' : '?'}addPhoto=1`}
              data-testid={`add-photo-${item.id}`}
              className="inline-flex min-h-[44px] items-center gap-2 rounded-bw-md border border-zinc-200 bg-white px-3 text-bw-sm font-semibold text-bite hover:border-bite hover:text-bite-dark"
            >
              <svg
                viewBox="0 0 24 24"
                className="h-4 w-4"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                aria-hidden="true"
              >
                <path d="M4 7h3l2-2h6l2 2h3v12H4z" />
                <circle cx="12" cy="13" r="3.5" />
              </svg>
              Add a photo
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
