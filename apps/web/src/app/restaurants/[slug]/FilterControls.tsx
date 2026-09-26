'use client';

import { useState } from 'react';
import { encodeProfileToken, filterSourceLabel, type Strictness } from '@biteworthy/filter-engine';
import type { FilterSummary } from '../../../lib/restaurants';
import { useTracker } from '../../_PostHogProvider';

/**
 * Extracted from RestaurantClient (menu-page hierarchy pass) — the
 * filter summary line, strictness toggle, share button, and the
 * strict-mode unconfirmed-count line, moved out unchanged except for
 * that last addition.
 */

const STRICTNESSES: Strictness[] = ['relaxed', 'balanced', 'strict'];

export function FilterBadge({ filter }: { filter: FilterSummary }) {
  const label = filterSourceLabel(filter);
  return (
    <span
      data-testid="filter-badge"
      className="rounded-bw-pill bg-bite-light px-bw-3 py-bw-1 text-bw-sm font-semibold text-bite-dark"
    >
      {label} · {filter.strictness}
    </span>
  );
}

export function StrictnessToggle({
  active,
  loading,
  onChange,
}: {
  active: Strictness;
  loading: boolean;
  onChange: (next: Strictness) => void;
}) {
  return (
    <div data-testid="strictness-toggle" className="flex items-center gap-bw-2">
      {STRICTNESSES.map((s) => {
        const selected = s === active;
        return (
          <button
            key={s}
            type="button"
            aria-pressed={selected}
            disabled={loading}
            onClick={() => {
              if (!loading && !selected) onChange(s);
            }}
            className={[
              'rounded-bw-pill border px-bw-3 py-bw-1 text-bw-sm font-semibold transition',
              selected
                ? 'border-bite bg-bite-light text-bite-dark'
                : 'border-zinc-200 bg-zinc-50 text-zinc-500 hover:border-zinc-300',
              loading ? 'opacity-60' : '',
            ].join(' ')}
          >
            {capitalize(s)}
          </button>
        );
      })}
      {loading && <span className="text-bw-xs text-zinc-400">refreshing…</span>}
    </div>
  );
}

export function ShareLinkButton({
  slug,
  filter,
  tracker,
}: {
  slug: string;
  filter: FilterSummary;
  tracker?: ReturnType<typeof useTracker>;
}) {
  const ctxTracker = useTracker();
  const t = tracker ?? ctxTracker;
  const [copied, setCopied] = useState(false);

  const handleClick = async () => {
    const origin = typeof window !== 'undefined' ? window.location.origin : '';
    // A preset filter shares as its slug, not as a token: the token would
    // carry the preset's pre-expanded avoid lists (hundreds of UUIDs —
    // ~14KB encoded, past Puma's 10KB query-string cap), arriving dead.
    // A signed-in viewer's own avoids ride on top of a preset for them
    // (Menus::Filter.build) but aren't put in the link: a diet link shares
    // the diet, not the sharer's allergies, and a signed-in recipient gets
    // their own avoids added the same way.
    // No filter shares the bare URL: an empty-list token is VALID to the
    // API, and the recipient would see "Shared filter" over a menu
    // nothing was filtered out of.
    const url =
      filter.source === 'preset' && filter.preset_slug
        ? `${origin}/r/${encodeURIComponent(slug)}?profile=${encodeURIComponent(filter.preset_slug)}`
        : filter.source === 'none'
          ? `${origin}/r/${encodeURIComponent(slug)}`
          : `${origin}/r/${encodeURIComponent(slug)}?p=${encodeProfileToken({
              avoid_ingredient_ids: filter.avoid_ingredient_ids,
              avoid_tag_ids: filter.avoid_tag_ids,
              strictness: filter.strictness,
            })}`;
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      setTimeout(() => setCopied(false), 2_000);
      t.track('share_link_copied', { restaurant_slug: slug, via: 'clipboard' });
    } catch {
      // Clipboard blocked (rare in modern browsers, common in iframes).
      // Fall back to a prompt so the user can copy manually.
      window.prompt('Copy this share link', url);
      t.track('share_link_copied', { restaurant_slug: slug, via: 'prompt_fallback' });
    }
  };

  return (
    <button
      type="button"
      onClick={handleClick}
      data-testid="share-link"
      className="rounded-bw-pill border border-zinc-200 bg-zinc-50 px-bw-3 py-bw-1 text-bw-sm font-semibold text-zinc-700 hover:border-zinc-300"
    >
      {copied ? '✓ Copied' : '🔗 Share filter'}
    </button>
  );
}

/**
 * Menu-page hierarchy pass — a strict-mode menu can look broken when
 * most items are hidden for lack of confirmed ingredients rather than
 * an actual avoid-list match. Naming the count keeps a near-empty
 * strict menu from reading as a bug. Only items hidden for THAT reason
 * alone count — an item also caught by an avoid list is hidden for a
 * real reason too, so it isn't part of this honesty line.
 */
export function UnconfirmedStrictNotice({ count }: { count: number }) {
  if (count <= 0) return null;
  return (
    <p data-testid="unconfirmed-strict-notice" className="mt-bw-2 text-bw-sm text-zinc-500">
      {count} dish{count === 1 ? '' : 'es'} hidden because nobody has confirmed{' '}
      {count === 1 ? 'its' : 'their'} ingredients yet.
    </p>
  );
}

/**
 * The filter badge + strictness toggle + share button row, plus the
 * strict-mode unconfirmed-count line beneath it.
 */
export function FilterControls({
  filter,
  strictnessOverride,
  isPending,
  onStrictnessChange,
  slug,
  unconfirmedStrictCount,
}: {
  filter: FilterSummary;
  strictnessOverride: Strictness | null;
  isPending: boolean;
  onStrictnessChange: (next: Strictness) => void;
  slug: string;
  /** Only rendered when the active strictness is 'strict'. */
  unconfirmedStrictCount: number;
}) {
  const active = strictnessOverride ?? filter.strictness;
  return (
    <>
      <div className="mt-bw-3 flex flex-wrap items-center gap-bw-2">
        <FilterBadge filter={filter} />
        <StrictnessToggle active={active} loading={isPending} onChange={onStrictnessChange} />
        <ShareLinkButton slug={slug} filter={filter} />
        <a
          href={`/restaurants/${encodeURIComponent(slug)}/scan`}
          data-testid="scan-menu-link"
          className="rounded-bw-pill border border-bite px-bw-3 py-bw-1 text-bw-sm font-semibold text-bite hover:bg-bite-light"
        >
          Scan this menu
        </a>
      </div>
      {active === 'strict' && <UnconfirmedStrictNotice count={unconfirmedStrictCount} />}
    </>
  );
}

/**
 * Shown when the URL's share token was refused. The fallback fetch may
 * still apply a filter (the caller's saved profile, or a riding preset)
 * — say what IS applied rather than claiming "unfiltered" when it isn't.
 */
export function ShareTokenNotice({ filter }: { filter: FilterSummary }) {
  const applied =
    filter.source === 'none' && filter.strictness !== 'strict' ? (
      <>
        the menu below is <strong>unfiltered</strong>
      </>
    ) : (
      <>
        the menu below shows <strong>{filterSourceLabel(filter)}</strong> instead
      </>
    );
  return (
    <p
      role="note"
      data-testid="share-token-notice"
      className="mt-bw-3 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark"
    >
      This share link is invalid or has expired, so {applied}. Ask whoever sent it for a fresh link.
    </p>
  );
}

function capitalize(s: string) {
  return s.charAt(0).toUpperCase() + s.slice(1);
}
