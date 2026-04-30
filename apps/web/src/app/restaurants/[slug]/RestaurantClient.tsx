'use client';

import { useEffect, useMemo, useState, useTransition, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import { ClaimError, requestClaim } from '../../../lib/restaurant-claim';
import {
  applyOverrides,
  encodeProfileToken,
  groupItemsBySection,
  hiddenReasonLabel,
  type HideReason,
  type ItemSection,
  type Strictness,
} from '@biteworthy/filter-engine';
import {
  clearNeverHide,
  fetchRestaurantItems,
  setNeverHide,
  type FilterSummary,
  type Restaurant,
  type RestaurantItem,
  type RestaurantItemsResponse,
} from '../../../lib/restaurants';

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
}: {
  slug: string;
  restaurant: Restaurant;
  initialItems: RestaurantItemsResponse;
  /** Phase 3.9 — passed from SSR when the URL had ?p=<token>. */
  profileToken?: string | null;
}) {
  const [filter, setFilter] = useState<FilterSummary>(initialItems.filter);
  const [sections, setSections] = useState<ItemSection<RestaurantItem>[]>(() =>
    groupItemsBySection(initialItems.items),
  );
  const [strictnessOverride, setStrictnessOverride] = useState<Strictness | null>(null);
  const [shownAnyway, setShownAnyway] = useState<Set<string>>(() => new Set());
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  const isInitialRender = strictnessOverride === null;

  useEffect(() => {
    if (isInitialRender) return;
    let cancelled = false;
    startTransition(() => {
      // Keep the share-link token in play across refetches so the
      // strictness override doesn't silently drop the encoded profile.
      fetchRestaurantItems(slug, {
        strictness: strictnessOverride ?? undefined,
        profileToken: profileToken ?? undefined,
      })
        .then((res) => {
          if (cancelled) return;
          setFilter(res.filter);
          setSections(groupItemsBySection(res.items));
          setShownAnyway(new Set());
        })
        .catch((e) => {
          if (!cancelled) setError((e as Error).message);
        });
    });
    return () => {
      cancelled = true;
    };
  }, [slug, strictnessOverride, isInitialRender, profileToken]);

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
          onChange={setStrictnessOverride}
        />
        <ShareLinkButton slug={slug} filter={filter} />
      </div>

      <ClaimSection slug={slug} restaurant={restaurant} />

      {error && (
        <p className="mt-bw-3 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
          Could not refresh items — {error}
        </p>
      )}

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
          shownAnyway={shownAnyway}
          onToggleOverride={toggleOverride}
          onSetPersistentOverride={setPersistentOverride}
        />
      ))}
    </main>
  );
}

function FilterBadge({ filter }: { filter: FilterSummary }) {
  const label =
    filter.source === 'preset'
      ? `Preset · ${filter.preset_slug ?? 'unknown'}`
      : filter.source === 'user_profile'
      ? 'Your saved profile'
      : 'No filter';
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
  shownAnyway,
  onToggleOverride,
  onSetPersistentOverride,
}: {
  section: ItemSection<RestaurantItem>;
  restaurantSlug: string;
  shownAnyway: Set<string>;
  onToggleOverride: (itemId: string) => void;
  onSetPersistentOverride: (itemId: string, next: boolean) => void;
}) {
  const [hiddenOpen, setHiddenOpen] = useState(false);
  return (
    <section className="mt-bw-6">
      <h2 className="text-bw-lg font-bold">{section.name}</h2>
      <ul className="mt-bw-2 divide-y divide-zinc-100">
        {section.visible.map((item) => (
          <ItemRow
            key={item.id}
            item={item}
            restaurantSlug={restaurantSlug}
            overridden={shownAnyway.has(item.id) || item.overridden_by_user === true}
            onToggleOverride={onToggleOverride}
            onSetPersistentOverride={onSetPersistentOverride}
          />
        ))}
        {section.visible.length === 0 && section.hidden.length > 0 && (
          <li className="py-bw-2 text-bw-sm text-zinc-500">
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
          className="mt-bw-2 divide-y divide-zinc-100"
        >
          {section.hidden.map((item) => (
            <ItemRow
              key={item.id}
              item={item}
              restaurantSlug={restaurantSlug}
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

function ItemRow({
  item,
  restaurantSlug,
  hidden = false,
  overridden,
  onToggleOverride,
  onSetPersistentOverride,
}: {
  item: RestaurantItem;
  restaurantSlug: string;
  hidden?: boolean;
  overridden: boolean;
  onToggleOverride: (itemId: string) => void;
  onSetPersistentOverride: (itemId: string, next: boolean) => void;
}) {
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
        Verification email sent to <strong>{done.email}</strong>. Click the link to confirm your claim.
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
    } catch (e) {
      if (e instanceof ClaimError && e.status === 401) {
        router.replace(`/login?next=${encodeURIComponent(`/restaurants/${slug}`)}`);
        return;
      }
      setError((e as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <form onSubmit={submit} className="mt-bw-3 rounded-bw-md border border-zinc-200 p-bw-3" data-testid="claim-form">
      <p className="text-bw-sm font-semibold text-zinc-700">Claim this restaurant</p>
      <p className="mt-1 text-bw-xs text-zinc-500">
        Use an email at the restaurant&rsquo;s own domain — we&rsquo;ll send a one-time verification link.
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

export function ShareLinkButton({ slug, filter }: { slug: string; filter: FilterSummary }) {
  const [copied, setCopied] = useState(false);

  const handleClick = async () => {
    const token = encodeProfileToken({
      avoid_ingredient_ids: filter.avoid_ingredient_ids,
      avoid_tag_ids: filter.avoid_tag_ids,
      strictness: filter.strictness,
    });
    const origin = typeof window !== 'undefined' ? window.location.origin : '';
    const url = `${origin}/r/${encodeURIComponent(slug)}?p=${token}`;
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      setTimeout(() => setCopied(false), 2_000);
    } catch {
      // Clipboard blocked (rare in modern browsers, common in iframes).
      // Fall back to a prompt so the user can copy manually.
      window.prompt('Copy this share link', url);
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
