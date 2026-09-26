'use client';

import { useEffect, useMemo, useState, useTransition } from 'react';
import {
  applyOverrides,
  groupItemsBySection,
  type ItemSection,
  type Strictness,
} from '@biteworthy/filter-engine';
import {
  clearNeverHide,
  fetchRestaurantItemsClient,
  setNeverHide,
  setRestaurantFavorite,
  type FilterSummary,
  type Restaurant,
  type RestaurantItem,
  type RestaurantItemsResponse,
} from '../../../lib/restaurants';
import { ClaimSection } from './ClaimSection';
import { FilterControls, ShareTokenNotice } from './FilterControls';
import { PageHeader } from './PageHeader';
import { SectionList } from './SectionList';
import { TopPicksRow } from './TopPicksRow';
import { useTracker } from '../../_PostHogProvider';

/**
 * Phase 3.6 — client island for the SSR-rendered restaurant page.
 *
 * Mirrors the mobile screen's interactivity: strictness toggle that
 * triggers a refetch, "show anyway" per-item override (session-only),
 * and translated <HiddenReasonChip> per reason. SSR renders the
 * initial items with the server's default filter; the client takes
 * over for re-filtering and overrides without a full page navigation.
 *
 * Menu-page hierarchy pass — this file now composes PageHeader,
 * FilterControls, ClaimSection, TopPicksRow and SectionList rather
 * than rendering all of it inline. Each piece kept its own
 * data-testids and behavior; nothing here changed except the split
 * and the two additions called out below (the strict-mode
 * unconfirmed-count line and passing `signedIn` into TopPicksRow).
 */

export function RestaurantClient({
  slug,
  restaurant,
  initialItems,
  profileToken = null,
  presetSlug = null,
  presetInvalid = false,
  shareTokenInvalid = false,
  signedIn = false,
}: {
  slug: string;
  restaurant: Restaurant;
  initialItems: RestaurantItemsResponse;
  /** Phase 3.9 — passed from SSR when the URL had ?p=<token>. */
  profileToken?: string | null;
  /** Passed from SSR when the URL had ?profile=<preset> (diet-page links). */
  presetSlug?: string | null;
  /** The URL carried a preset slug the API didn't recognize. */
  presetInvalid?: boolean;
  /** The URL carried a share token Rails refused (malformed/expired). */
  shareTokenInvalid?: boolean;
  /** Gates the save button — the favorite endpoint is authed. */
  signedIn?: boolean;
}) {
  const tracker = useTracker();
  const [filter, setFilter] = useState<FilterSummary>(initialItems.filter);
  // Phase 8.3 — the raw (server-sorted) items feed the Top Picks row;
  // the section state below still drives the main menu + overrides.
  const [rawItems, setRawItems] = useState<RestaurantItem[]>(initialItems.items);
  const [sections, setSections] = useState<ItemSection<RestaurantItem>[]>(() =>
    groupItemsBySection(initialItems.items),
  );
  const [strictnessOverride, setStrictnessOverride] = useState<Strictness | null>(null);
  const [shownAnyway, setShownAnyway] = useState<Set<string>>(() => new Set());
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  const isInitialRender = strictnessOverride === null;

  // A refused token shouldn't survive in the address bar: reloads re-pay
  // the failed fetch, and anyone re-sharing from the URL propagates a
  // dead link.
  useEffect(() => {
    if (!shareTokenInvalid) return;
    const url = new URL(window.location.href);
    if (url.searchParams.has('p')) {
      url.searchParams.delete('p');
      window.history.replaceState(null, '', `${url.pathname}${url.search}`);
    }
  }, [shareTokenInvalid]);

  // Phase 5.8 — fire menu_filtered + restaurant_tap once on first
  // paint with the SSR-delivered items, then again whenever the
  // strictness override triggers a refetch (handled below).
  useEffect(() => {
    const totalVisible = initialItems.items.filter((it) => it.status === 'visible').length;
    const totalHidden = initialItems.items.length - totalVisible;
    tracker.track('menu_filtered', {
      restaurant_slug: slug,
      visible_count: totalVisible,
      hidden_count: totalHidden,
      filter_source: initialItems.filter.source,
      // Lets the dashboards separate failed share opens from direct visits.
      ...(shareTokenInvalid ? { share_token_invalid: true } : {}),
    });
    tracker.track('restaurant_tap', {
      restaurant_slug: slug,
      // The analytics taxonomy documents 'durango_diet' for the SEO-page
      // funnel — a preset in the URL is that click-through.
      from: presetSlug ? 'durango_diet' : 'direct',
    });
    // Mount-only — slug + initialItems are stable across the
    // RestaurantClient's lifetime (a new restaurant remounts the
    // component).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (isInitialRender) return;
    let cancelled = false;
    startTransition(() => {
      // `signedIn` picks the route: a cross-origin fetch carries no
      // `bw_session`, so a signed-in reader has to go through the proxy
      // or get the anonymous menu back. Anonymous readers go direct —
      // see fetchRestaurantItemsClient for why that matters.
      //
      // Keep the share-link token and the diet-page preset in play across
      // refetches so the strictness override doesn't silently drop them.
      fetchRestaurantItemsClient(slug, {
        signedIn,
        strictness: strictnessOverride ?? undefined,
        profileToken: profileToken ?? undefined,
        presetSlug: presetSlug ?? undefined,
      })
        .then((res) => {
          if (cancelled) return;
          setFilter(res.filter);
          setRawItems(res.items);
          setSections(groupItemsBySection(res.items));
          setShownAnyway(new Set());
          const totalVisible = res.items.filter((it) => it.status === 'visible').length;
          tracker.track('menu_filtered', {
            restaurant_slug: slug,
            visible_count: totalVisible,
            hidden_count: res.items.length - totalVisible,
            filter_source: res.filter.source,
          });
        })
        .catch((e) => {
          if (!cancelled) setError((e as Error).message);
        });
    });
    return () => {
      cancelled = true;
    };
  }, [slug, strictnessOverride, isInitialRender, profileToken, presetSlug]);

  const overriddenSections = useMemo(
    () => applyOverrides(sections, shownAnyway),
    [sections, shownAnyway],
  );

  const toggleOverride = (itemId: string) => {
    setShownAnyway((prev) => {
      const next = new Set(prev);
      if (next.has(itemId)) next.delete(itemId);
      else next.add(itemId);
      return next;
    });
  };

  // Phase 4.2 — flip an item's persistent override and patch local
  // state in place so the UI updates without a full refetch.
  const setPersistentOverride = async (itemId: string, next: boolean) => {
    try {
      if (next) await setNeverHide(itemId);
      else await clearNeverHide(itemId);
    } catch (e) {
      setError((e as Error).message);
      return;
    }
    setSections((prev) =>
      prev.map((section) => ({
        ...section,
        visible: section.visible.map((it) =>
          it.id === itemId ? { ...it, overridden_by_user: next } : it,
        ),
        hidden: section.hidden.map((it) =>
          it.id === itemId ? { ...it, overridden_by_user: next } : it,
        ),
      })),
    );
  };

  const totalHidden = overriddenSections.reduce((acc, s) => acc + s.hidden.length, 0);
  const totalVisible = overriddenSections.reduce((acc, s) => acc + s.visible.length, 0);
  const unconfirmedStrictCount = countUnconfirmedStrictHidden(overriddenSections);

  return (
    <main className="mx-auto max-w-3xl px-bw-6 py-bw-12">
      <PageHeader
        restaurant={restaurant}
        signedIn={signedIn}
        onToggleFavorite={(next) => setRestaurantFavorite(slug, next)}
      />
      <p className="mt-bw-2 text-bw-base text-zinc-700">
        {filter.source === 'none' && filter.strictness !== 'strict' ? (
          <>
            Showing <span className="font-bold">{totalVisible}</span> item
            {totalVisible === 1 ? '' : 's'}. No filter applied.
          </>
        ) : (
          <>
            Showing <span className="font-bold">{totalVisible}</span> item
            {totalVisible === 1 ? '' : 's'} that match your filter
            {totalHidden > 0 ? `, hiding ${totalHidden}.` : '.'}
          </>
        )}
      </p>

      <FilterControls
        filter={filter}
        strictnessOverride={strictnessOverride}
        isPending={isPending}
        slug={slug}
        unconfirmedStrictCount={unconfirmedStrictCount}
        onStrictnessChange={(next) => {
          tracker.track('filter_changed', {
            kind: 'strictness',
            from: strictnessOverride ?? filter.strictness,
            to: next,
          });
          setStrictnessOverride(next);
        }}
      />

      <ClaimSection slug={slug} restaurant={restaurant} />

      {shareTokenInvalid && <ShareTokenNotice filter={filter} />}

      {presetInvalid && (
        <p
          role="note"
          data-testid="preset-invalid-notice"
          className="mt-bw-3 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark"
        >
          That diet link isn&rsquo;t recognized, so the menu below is <strong>unfiltered</strong>.
        </p>
      )}

      {error && (
        <p className="mt-bw-3 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
          Could not refresh items — {error}
        </p>
      )}

      <AllergenNotice />

      <TopPicksRow
        items={rawItems}
        restaurantSlug={slug}
        presetSlug={presetSlug}
        signedIn={signedIn}
      />

      <SectionList
        sections={overriddenSections}
        restaurantSlug={slug}
        presetSlug={presetSlug}
        shownAnyway={shownAnyway}
        onToggleOverride={toggleOverride}
        onSetPersistentOverride={setPersistentOverride}
      />
    </main>
  );
}

/**
 * Menu-page hierarchy pass — strict mode hides an item either because
 * an avoid list matched it or because its ingredients/tags aren't
 * confirmed yet. Only the second case is counted here: an item also
 * caught by an avoid-list reason is hidden for a real reason too, so
 * naming it under "unconfirmed" would overstate what confirming
 * ingredients would actually unlock.
 */
export function countUnconfirmedStrictHidden(sections: ItemSection<RestaurantItem>[]): number {
  return sections.reduce(
    (acc, s) =>
      acc +
      s.hidden.filter(
        (it) => it.reasons.length > 0 && it.reasons.every((r) => r.kind === 'unconfirmed_strict'),
      ).length,
    0,
  );
}

/**
 * Legal remediation E1 — the point-of-use allergen disclaimer.
 *
 * Persistent and non-dismissable: it sits at the top of every filtered
 * menu so the "safe to eat" framing is never read as a guarantee. Names
 * the false-negative case explicitly (a result can still miss an
 * allergen), matching the ToS allergen disclaimer.
 */
export function AllergenNotice() {
  return (
    <div
      role="note"
      data-testid="allergen-notice"
      className="mt-bw-4 rounded-bw-md border border-warn/40 bg-warn/10 p-bw-3 text-bw-sm text-zinc-800"
    >
      <strong>A filter, not a guarantee.</strong> BiteWorthy reads menus with AI and your dietary
      filter — but recipes change and a result can still miss an allergen. Always confirm with the
      restaurant before ordering for a serious allergy.
    </div>
  );
}

// Re-exported so existing tests (and any other importers) that reach
// these through '../RestaurantClient' keep working after the split.
export { RestaurantContactLine } from './PageHeader';
export { FilterBadge, ShareTokenNotice, StrictnessToggle, ShareLinkButton } from './FilterControls';
export { HiddenReasonChip, SectionBlock } from './SectionList';
