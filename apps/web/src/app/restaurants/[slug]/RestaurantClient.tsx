'use client';

import { useEffect, useMemo, useState, useTransition, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import { ClaimError, requestClaim } from '../../../lib/restaurant-claim';
import {
  applyOverrides,
  encodeProfileToken,
  filterSourceLabel,
  groupItemsBySection,
  hiddenReasonLabel,
  type HideReason,
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
import FavoriteButton from './_FavoriteButton';
import { ItemRow } from './ItemRow';
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
 */

const STRICTNESSES: Strictness[] = ['relaxed', 'balanced', 'strict'];

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

  return (
    <main className="mx-auto max-w-3xl px-bw-6 py-bw-12">
      <p className="text-bite text-bw-sm font-semibold uppercase tracking-wider">
        {restaurant.city.name}, {restaurant.city.region}
      </p>
      <h1 className="mt-bw-2 text-bw-3xl font-bold">{restaurant.name}</h1>
      <RestaurantContactLine restaurant={restaurant} />
      {signedIn && (
        <div className="mt-bw-3">
          <FavoriteButton
            initialFavorited={restaurant.favorited ?? false}
            onToggle={(next) => setRestaurantFavorite(slug, next)}
            savedLabel="Saved"
            unsavedLabel="Save restaurant"
            testId="favorite-restaurant"
          />
        </div>
      )}
      <p className="mt-bw-2 text-bw-base text-zinc-700">
        Showing <span className="font-bold">{totalVisible}</span> item
        {totalVisible === 1 ? '' : 's'} that match your filter
        {totalHidden > 0 ? `, hiding ${totalHidden}.` : '.'}
      </p>

      <div className="mt-bw-3 flex flex-wrap items-center gap-bw-2">
        <FilterBadge filter={filter} />
        <StrictnessToggle
          active={strictnessOverride ?? filter.strictness}
          loading={isPending}
          onChange={(next) => {
            tracker.track('filter_changed', {
              kind: 'strictness',
              from: strictnessOverride ?? filter.strictness,
              to: next,
            });
            setStrictnessOverride(next);
          }}
        />
        <ShareLinkButton slug={slug} filter={filter} tracker={tracker} />
      </div>

      <ClaimSection slug={slug} restaurant={restaurant} />

      {shareTokenInvalid && <ShareTokenNotice filter={filter} />}

      {presetInvalid && (
        <p
          role="note"
          data-testid="preset-invalid-notice"
          className="mt-bw-3 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark"
        >
          That diet link isn&rsquo;t recognized, so the menu below is{' '}
          <strong>unfiltered</strong>.
        </p>
      )}

      {error && (
        <p className="mt-bw-3 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
          Could not refresh items — {error}
        </p>
      )}

      <AllergenNotice />

      <TopPicksRow items={rawItems} restaurantSlug={slug} />

      {overriddenSections.length === 0 && (
        <p className="mt-bw-6 text-center text-bw-base text-zinc-500">
          No published items at this restaurant yet.
        </p>
      )}

      {overriddenSections.map((section) => (
        <SectionBlock
          key={section.id ?? '__none__'}
          section={section}
          restaurantSlug={slug}
          presetSlug={presetSlug}
          shownAnyway={shownAnyway}
          onToggleOverride={toggleOverride}
          onSetPersistentOverride={setPersistentOverride}
        />
      ))}
    </main>
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
      This share link is invalid or has expired, so {applied}. Ask whoever sent it for a fresh
      link.
    </p>
  );
}

/** Digits to dial: extensions ("ext 2", "x2", "#2") can't ride a tel: URI. */
function dialable(phone: string): string {
  return phone.split(/(?:ext|x|#)/i)[0]!.replace(/[^+\d]/g, '');
}

/** Scheme-less stored values ("www.x.com") must not resolve as relative URLs. */
function externalHref(website: string): string {
  return /^https?:\/\//i.test(website) ? website : `https://${website}`;
}

/**
 * Phone + website, already in the `#show` payload but never rendered —
 * the "confirm with the restaurant" disclaimer ends in a phone call, so
 * the page should hand over the number. Renders nothing when the data
 * is absent (most community-scanned restaurants at first).
 */
export function RestaurantContactLine({ restaurant }: { restaurant: Restaurant }) {
  if (!restaurant.phone && !restaurant.website) return null;
  return (
    <p className="mt-bw-2 flex flex-wrap gap-bw-4 text-bw-sm" data-testid="restaurant-contact">
      {restaurant.phone && (
        <a
          href={`tel:${dialable(restaurant.phone)}`}
          data-testid="restaurant-phone"
          className="font-semibold text-zinc-700 hover:text-bite-dark"
        >
          ☎ {restaurant.phone}
        </a>
      )}
      {restaurant.website && (
        <a
          href={externalHref(restaurant.website)}
          target="_blank"
          rel="noopener noreferrer"
          data-testid="restaurant-website"
          className="font-semibold text-zinc-700 hover:text-bite-dark"
        >
          Website ↗
        </a>
      )}
    </p>
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

function SectionBlock({
  section,
  restaurantSlug,
  presetSlug,
  shownAnyway,
  onToggleOverride,
  onSetPersistentOverride,
}: {
  section: ItemSection<RestaurantItem>;
  restaurantSlug: string;
  presetSlug: string | null;
  shownAnyway: Set<string>;
  onToggleOverride: (itemId: string) => void;
  onSetPersistentOverride: (itemId: string, next: boolean) => void;
}) {
  const [hiddenOpen, setHiddenOpen] = useState(false);
  return (
    <section className="mt-bw-6">
      <h2 className="text-bw-lg font-bold">{section.name}</h2>
      <ul className="mt-bw-2 grid grid-cols-1 gap-bw-4 sm:grid-cols-2 lg:grid-cols-3">
        {section.visible.map((item) => (
          <ItemRow
            key={item.id}
            item={item}
            restaurantSlug={restaurantSlug}
            presetSlug={presetSlug}
            overridden={shownAnyway.has(item.id) || item.overridden_by_user === true}
            onToggleOverride={onToggleOverride}
            onSetPersistentOverride={onSetPersistentOverride}
          />
        ))}
        {section.visible.length === 0 && section.hidden.length > 0 && (
          <li className="col-span-full py-bw-2 text-bw-sm text-zinc-500">
            Every item in this section is hidden by your filter.
          </li>
        )}
      </ul>

      {section.hidden.length > 0 && (
        <button
          type="button"
          onClick={() => setHiddenOpen((v) => !v)}
          aria-expanded={hiddenOpen}
          aria-controls={`hidden-${section.id ?? 'none'}`}
          className="mt-bw-2 text-bw-sm font-semibold text-bite hover:text-bite-dark"
        >
          {hiddenOpen ? '▾ Hide' : '▸ Show'} items hidden by your filter ({section.hidden.length})
        </button>
      )}

      {hiddenOpen && (
        <ul
          id={`hidden-${section.id ?? 'none'}`}
          className="mt-bw-2 grid grid-cols-1 gap-bw-4 sm:grid-cols-2 lg:grid-cols-3"
        >
          {section.hidden.map((item) => (
            <ItemRow
              key={item.id}
              item={item}
              restaurantSlug={restaurantSlug}
              presetSlug={presetSlug}
              hidden
              overridden={false}
              onToggleOverride={onToggleOverride}
              onSetPersistentOverride={onSetPersistentOverride}
            />
          ))}
        </ul>
      )}
    </section>
  );
}

export function HiddenReasonChip({ reason }: { reason: HideReason }) {
  return (
    <span
      data-testid={`chip-${reason.kind}`}
      className="rounded-bw-pill border border-zinc-200 bg-zinc-50 px-bw-2 py-bw-0_5 text-bw-xs font-semibold text-hide"
    >
      {hiddenReasonLabel(reason)}
    </span>
  );
}

/**
 * Phase 3.9 — share the current filter as a `/r/<slug>?p=<token>` URL.
 *
 * The token encodes the filter currently applied on the server (as
 * reported by `filter` in the items response) — preset, manual avoid
 * lists, strictness. A friend opening the link sees the same hidden/
 * visible split without needing to sign in or know the encoder's
 * profile.
 */
/**
 * Phase 4.9 — claim flow entry point on the restaurant page.
 *
 * Hidden once the restaurant is already claimed. Shows a tiny inline
 * form ("@<your-domain> email"); on submit, POSTs to the claim
 * endpoint and shows a confirmation. 401 from the proxy bounces to
 * /login because the POST requires auth.
 */
function ClaimSection({ slug, restaurant }: { slug: string; restaurant: Restaurant }) {
  const router = useRouter();
  const tracker = useTracker();
  const [email, setEmail] = useState('');
  const [open, setOpen] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [done, setDone] = useState<{ email: string; auto: boolean } | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (restaurant.claimed_by_user_id) {
    return (
      <p className="mt-bw-3 text-bw-xs text-zinc-500" data-testid="claimed-notice">
        ✓ This restaurant is owner-claimed.
      </p>
    );
  }

  if (done) {
    return (
      <p className="mt-bw-3 text-bw-sm text-zinc-700" data-testid="claim-sent">
        Verification email sent to <strong>{done.email}</strong>. Click the link to confirm your
        claim.
        {!done.auto && (
          <span className="ml-1 text-bw-xs text-zinc-500">
            (Domain didn&rsquo;t match this restaurant&rsquo;s website — admin review may follow.)
          </span>
        )}
      </p>
    );
  }

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        data-testid="open-claim"
        className="mt-bw-3 text-bw-sm font-semibold text-bite hover:text-bite-dark"
      >
        Claim this restaurant
      </button>
    );
  }

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (!email.includes('@')) {
      setError('Enter a valid email.');
      return;
    }
    try {
      setSubmitting(true);
      const result = await requestClaim(slug, email);
      setDone({ email: result.email, auto: result.auto_acceptable });
      tracker.track('restaurant_claimed', {
        restaurant_slug: slug,
        decision: result.auto_acceptable ? 'auto_acceptable' : 'admin_review',
      });
    } catch (e) {
      if (e instanceof ClaimError && e.status === 401) {
        // Keep ?profile= / ?p= across the login round-trip — a bare slug
        // would silently drop the applied filter.
        const next = `${window.location.pathname}${window.location.search}`;
        router.replace(`/login?next=${encodeURIComponent(next)}`);
        return;
      }
      setError((e as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <form
      onSubmit={submit}
      className="mt-bw-3 rounded-bw-md border border-zinc-200 p-bw-3"
      data-testid="claim-form"
    >
      <p className="text-bw-sm font-semibold text-zinc-700">Claim this restaurant</p>
      <p className="mt-1 text-bw-xs text-zinc-500">
        Use an email at the restaurant&rsquo;s own domain — we&rsquo;ll send a one-time verification
        link.
      </p>
      <input
        type="email"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        placeholder="you@yourrestaurant.com"
        aria-label="claim-email"
        required
        className="mt-bw-2 w-full rounded-bw-md border border-zinc-300 px-bw-2 py-bw-2 text-bw-sm"
      />
      {error && (
        <p className="mt-bw-2 rounded-bw-md bg-bite-light px-bw-2 py-bw-1 text-bw-xs text-bite-dark">
          {error}
        </p>
      )}
      <div className="mt-bw-2 flex items-center gap-bw-2 justify-end">
        <button
          type="button"
          onClick={() => setOpen(false)}
          className="text-bw-sm font-semibold text-zinc-500 hover:text-zinc-700"
        >
          Cancel
        </button>
        <button
          type="submit"
          disabled={submitting}
          data-testid="submit-claim"
          className={[
            'rounded-bw-md bg-bite px-bw-3 py-bw-2 text-bw-sm font-bold text-white',
            submitting ? 'opacity-60' : 'hover:bg-bite-dark',
          ].join(' ')}
        >
          {submitting ? 'Sending…' : 'Send verification'}
        </button>
      </div>
    </form>
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

function capitalize(s: string) {
  return s.charAt(0).toUpperCase() + s.slice(1);
}
