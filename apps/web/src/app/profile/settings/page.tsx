'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import type { DietaryPreset, Strictness } from '@biteworthy/filter-engine';
import { OPT_OUT_KEY } from '../../../lib/track';
import {
  fetchProfile,
  updateProfile,
  fetchMyReviews,
  fetchMyFavorites,
  NotSignedInError,
  type ProfilePatch,
  type ProfilePayload,
  type MyReview,
  type FavoriteRestaurant,
  type FavoriteDish,
} from '../../../lib/profile';
import {
  createToken,
  listTokens,
  revokeToken,
  type McpTokenSummary,
  type McpTokenWithSecret,
} from '../../../lib/mcp-tokens';
import { listConnectedApps, disconnectApp, type ConnectedApp } from '../../../lib/connected-apps';
import {
  fetchDietaryProfiles,
  searchIngredients,
  type IngredientSearchResult,
} from '../../../lib/onboarding';

/**
 * The account page. Shows every dietary preference the profile stores
 * — presets, strictness, avoid lists, taste signals — and lets the
 * user change them in place (previously they could only be set once,
 * in the onboarding wizard). Plus the legal-remediation analytics
 * opt-out that already lived here.
 *
 * Every edit is a partial PATCH: the Rails endpoint replaces only the
 * arrays it receives, so changing one preference never disturbs the
 * others. Each array we send IS replaced wholesale, so we send the
 * full canonical array rebuilt from the loaded profile.
 */
export default function ProfileSettingsPage() {
  return (
    <main className="mx-auto max-w-2xl px-bw-6 pt-bw-12 pb-bw-16">
      <h1 className="text-bw-2xl font-bold text-zinc-900">Account</h1>
      <PreferencesSection />
      <FavoritesSection />
      <MyReviewsSection />
      <ConnectedAppsSection />
      <McpTokensSection />
      <AnalyticsSection />
    </main>
  );
}

const STRICTNESSES: Strictness[] = ['relaxed', 'balanced', 'strict'];
const STRICTNESS_BLURB: Record<Strictness, string> = {
  relaxed: 'Show items even if some ingredients are inferred.',
  balanced: 'Hide items where the avoid match is confident.',
  strict: 'Also hide items the AI marked suggested or inferred.',
};

function PreferencesSection() {
  const router = useRouter();
  const [profile, setProfile] = useState<ProfilePayload | null>(null);
  const [presets, setPresets] = useState<DietaryPreset[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    fetchProfile()
      .then(setProfile)
      .catch((e) => {
        if (e instanceof NotSignedInError) {
          router.replace(`/login?next=${encodeURIComponent('/profile/settings')}`);
          return;
        }
        setLoadError((e as Error).message);
      });
  }, [router]);

  useEffect(() => {
    fetchDietaryProfiles()
      .then(setPresets)
      .catch(() => {
        // Presets are optional sugar — a load failure just hides the picker.
      });
  }, []);

  // Persist a partial patch, then adopt the returned payload so the
  // resolved names (e.g. a just-added ingredient) stay in sync.
  const save = async (patch: ProfilePatch) => {
    try {
      setSaving(true);
      setSaveError(null);
      const updated = await updateProfile(patch);
      setProfile(updated);
    } catch (e) {
      if (e instanceof NotSignedInError) {
        router.replace(`/login?next=${encodeURIComponent('/profile/settings')}`);
        return;
      }
      setSaveError((e as Error).message);
    } finally {
      setSaving(false);
    }
  };

  if (loadError) {
    return (
      <section className="mt-bw-8" data-testid="preferences-error">
        <h2 className="text-bw-lg font-bold text-zinc-900">Dietary preferences</h2>
        <p className="mt-bw-3 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
          Could not load your preferences — {loadError}
        </p>
      </section>
    );
  }

  if (!profile) {
    return (
      <section className="mt-bw-8">
        <h2 className="text-bw-lg font-bold text-zinc-900">Dietary preferences</h2>
        <p className="mt-bw-3 text-bw-sm text-zinc-500" data-testid="preferences-loading">
          Loading your preferences…
        </p>
      </section>
    );
  }

  return (
    <section className="mt-bw-8" data-testid="preferences">
      <div className="flex items-baseline justify-between">
        <h2 className="text-bw-lg font-bold text-zinc-900">Dietary preferences</h2>
        <span
          className="text-bw-xs text-zinc-400"
          data-testid="preferences-saving"
          aria-live="polite"
        >
          {saving ? 'Saving…' : ''}
        </span>
      </div>

      {saveError && (
        <p
          className="mt-bw-3 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark"
          data-testid="preferences-save-error"
        >
          {saveError}
        </p>
      )}

      <PresetSubsection
        current={profile.primary_dietary_profile}
        presets={presets}
        disabled={saving}
        onApply={(slug) => save({ dietary_profile_slug: slug })}
      />

      <StrictnessSubsection
        active={profile.strictness}
        disabled={saving}
        onPick={(strictness) => save({ strictness })}
      />

      <AvoidIngredientsSubsection
        items={profile.avoid_ingredients}
        disabled={saving}
        onRemove={(id) =>
          save({ avoid_ingredient_ids: profile.avoid_ingredient_ids.filter((x) => x !== id) })
        }
        onAdd={(id) => {
          if (profile.avoid_ingredient_ids.includes(id)) return;
          save({ avoid_ingredient_ids: [...profile.avoid_ingredient_ids, id] });
        }}
      />

      <AvoidTagsSubsection
        items={profile.avoid_tags}
        disabled={saving}
        onRemove={(id) => save({ avoid_tag_ids: profile.avoid_tag_ids.filter((x) => x !== id) })}
      />

      <TasteSubsection
        likedTags={profile.liked_tags}
        likedIngredients={profile.liked_ingredients}
        dislikedTags={profile.disliked_tags}
        dislikedIngredients={profile.disliked_ingredients}
      />

      <p className="mt-bw-6 text-bw-xs text-zinc-400" data-testid="disclaimer-status">
        {profile.disclaimer_acknowledged_at
          ? `Allergen disclaimer accepted on ${new Date(profile.disclaimer_acknowledged_at).toLocaleDateString()}.`
          : 'You have not accepted the allergen disclaimer yet.'}
      </p>
    </section>
  );
}

// ─── Subsections ──────────────────────────────────────────────────

function SubsectionHeader({ title, hint }: { title: string; hint: string }) {
  return (
    <>
      <h3 className="text-bw-base font-semibold text-zinc-800">{title}</h3>
      <p className="mt-bw-1 text-bw-sm text-zinc-500">{hint}</p>
    </>
  );
}

function RemovableChip({
  label,
  onRemove,
  disabled,
  testId,
}: {
  label: string;
  onRemove: () => void;
  disabled: boolean;
  testId: string;
}) {
  return (
    <span className="inline-flex items-center gap-bw-2 rounded-bw-pill border border-zinc-200 bg-white py-bw-1 pl-bw-3 pr-bw-2 text-bw-sm text-zinc-800">
      {label}
      <button
        type="button"
        onClick={onRemove}
        disabled={disabled}
        aria-label={`Remove ${label}`}
        data-testid={testId}
        className="text-zinc-400 hover:text-bite disabled:opacity-40"
      >
        ✕
      </button>
    </span>
  );
}

function PresetSubsection({
  current,
  presets,
  disabled,
  onApply,
}: {
  current: ProfilePayload['primary_dietary_profile'];
  presets: DietaryPreset[];
  disabled: boolean;
  onApply: (slug: string) => void;
}) {
  const [open, setOpen] = useState(false);
  return (
    <div className="mt-bw-6" data-testid="pref-preset">
      <SubsectionHeader
        title="Diet preset"
        hint="Applying a preset adds its avoid rules on top of your lists — it never removes what you already chose."
      />
      <p className="mt-bw-2 text-bw-sm text-zinc-700">
        Current: <span className="font-semibold">{current ? current.name : 'None'}</span>
      </p>
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        data-testid="preset-toggle"
        className="mt-bw-2 text-bw-sm font-semibold text-bite hover:text-bite-dark"
      >
        {open ? 'Hide presets' : 'Apply a preset'}
      </button>
      {open && presets.length > 0 && (
        <div className="mt-bw-3 grid grid-cols-1 gap-bw-2 sm:grid-cols-2">
          {presets.map((p) => (
            <button
              key={p.slug}
              type="button"
              disabled={disabled}
              data-testid={`apply-preset-${p.slug}`}
              onClick={() => onApply(p.slug)}
              className="rounded-bw-md border border-zinc-200 bg-white p-bw-3 text-left transition hover:border-zinc-300 disabled:opacity-50"
            >
              <p className="font-bold text-zinc-900">{p.name}</p>
              <p className="mt-1 text-bw-sm text-zinc-500">{p.description}</p>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function StrictnessSubsection({
  active,
  disabled,
  onPick,
}: {
  active: Strictness;
  disabled: boolean;
  onPick: (s: Strictness) => void;
}) {
  return (
    <div className="mt-bw-6" data-testid="pref-strictness">
      <SubsectionHeader
        title="Strictness"
        hint="How aggressively we hide items we're unsure about."
      />
      <div className="mt-bw-3 flex flex-col gap-bw-2">
        {STRICTNESSES.map((s) => {
          const selected = active === s;
          return (
            <button
              key={s}
              type="button"
              disabled={disabled}
              aria-pressed={selected}
              data-testid={`set-strictness-${s}`}
              onClick={() => onPick(s)}
              className={[
                'rounded-bw-md border p-bw-3 text-left transition disabled:opacity-50',
                selected
                  ? 'border-bite bg-bite-light'
                  : 'border-zinc-200 bg-white hover:border-zinc-300',
              ].join(' ')}
            >
              <p className={['font-bold', selected ? 'text-bite-dark' : 'text-zinc-900'].join(' ')}>
                {s.charAt(0).toUpperCase() + s.slice(1)}
              </p>
              <p
                className={['mt-1 text-bw-sm', selected ? 'text-bite-dark' : 'text-zinc-500'].join(
                  ' ',
                )}
              >
                {STRICTNESS_BLURB[s]}
              </p>
            </button>
          );
        })}
      </div>
    </div>
  );
}

function AvoidIngredientsSubsection({
  items,
  disabled,
  onRemove,
  onAdd,
}: {
  items: ProfilePayload['avoid_ingredients'];
  disabled: boolean;
  onRemove: (id: string) => void;
  onAdd: (id: string) => void;
}) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<IngredientSearchResult[]>([]);

  useEffect(() => {
    if (query.trim().length === 0) {
      setResults([]);
      return;
    }
    const handle = setTimeout(() => {
      searchIngredients(query)
        .then(setResults)
        .catch(() => setResults([]));
    }, 250);
    return () => clearTimeout(handle);
  }, [query]);

  const addedIds = new Set(items.map((i) => i.id));

  return (
    <div className="mt-bw-6" data-testid="pref-avoid-ingredients">
      <SubsectionHeader
        title="Avoid ingredients"
        hint="Items containing these are hidden. This is your hard safety filter."
      />
      {items.length > 0 ? (
        <div className="mt-bw-3 flex flex-wrap gap-bw-2">
          {items.map((i) => (
            <RemovableChip
              key={i.id}
              label={i.name}
              disabled={disabled}
              onRemove={() => onRemove(i.id)}
              testId={`remove-avoid-ingredient-${i.slug}`}
            />
          ))}
        </div>
      ) : (
        <p className="mt-bw-3 text-bw-sm text-zinc-400">None yet.</p>
      )}

      <input
        type="search"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder="Search ingredients to avoid (e.g. 'cilantro')"
        aria-label="avoid-ingredient-search"
        className="mt-bw-3 w-full rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-base"
      />
      {results.length > 0 && (
        <ul className="mt-bw-2 divide-y divide-zinc-100">
          {results.map((r) => {
            const added = addedIds.has(r.id);
            return (
              <li key={r.id}>
                <button
                  type="button"
                  disabled={disabled || added}
                  onClick={() => onAdd(r.id)}
                  data-testid={`add-avoid-ingredient-${r.slug}`}
                  className="flex w-full items-center justify-between py-bw-2 text-left disabled:opacity-50"
                >
                  <span className="text-bw-base text-zinc-900">{r.name}</span>
                  <span className={['font-semibold', added ? 'text-ok' : 'text-bite'].join(' ')}>
                    {added ? '✓ added' : '+ add'}
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

function AvoidTagsSubsection({
  items,
  disabled,
  onRemove,
}: {
  items: ProfilePayload['avoid_tags'];
  disabled: boolean;
  onRemove: (id: string) => void;
}) {
  return (
    <div className="mt-bw-6" data-testid="pref-avoid-tags">
      <SubsectionHeader
        title="Avoid categories"
        hint="Whole tags you avoid (e.g. a preparation or allergen group). Usually added by presets."
      />
      {items.length > 0 ? (
        <div className="mt-bw-3 flex flex-wrap gap-bw-2">
          {items.map((t) => (
            <RemovableChip
              key={t.id}
              label={t.name}
              disabled={disabled}
              onRemove={() => onRemove(t.id)}
              testId={`remove-avoid-tag-${t.slug}`}
            />
          ))}
        </div>
      ) : (
        <p className="mt-bw-3 text-bw-sm text-zinc-400">None yet.</p>
      )}
    </div>
  );
}

function TasteSubsection({
  likedTags,
  likedIngredients,
  dislikedTags,
  dislikedIngredients,
}: {
  likedTags: ProfilePayload['liked_tags'];
  likedIngredients: ProfilePayload['liked_ingredients'];
  dislikedTags: ProfilePayload['disliked_tags'];
  dislikedIngredients: ProfilePayload['disliked_ingredients'];
}) {
  // Taste covers both tags (cuisines/flavors) and specific ingredients;
  // show them together per love/pass row.
  const love = [...likedTags, ...likedIngredients];
  const pass = [...dislikedTags, ...dislikedIngredients];
  return (
    <div className="mt-bw-6" data-testid="pref-taste">
      <SubsectionHeader
        title="Taste"
        hint="Soft signals that rank your Top Picks — they never hide safe food."
      />
      <div className="mt-bw-3 space-y-bw-2">
        <TasteRow label="Love" tone="text-ok" items={love} />
        <TasteRow label="Pass" tone="text-bite" items={pass} />
      </div>
      {/* Editing taste reuses the existing "Improve my picks" flow so the
          love/pass cycling logic lives in one place. */}
      <a
        href="/onboarding?step=taste"
        data-testid="edit-taste-link"
        className="mt-bw-3 inline-block text-bw-sm font-semibold text-bite hover:text-bite-dark"
      >
        Edit taste →
      </a>
    </div>
  );
}

function TasteRow({
  label,
  tone,
  items,
}: {
  label: string;
  tone: string;
  items: Array<{ id: string; name: string }>;
}) {
  return (
    <div className="flex flex-wrap items-center gap-bw-2">
      <span className={['text-bw-sm font-semibold', tone].join(' ')}>{label}:</span>
      {items.length > 0 ? (
        items.map((t) => (
          <span
            key={t.id}
            className="rounded-bw-pill border border-zinc-200 bg-white px-bw-3 py-bw-1 text-bw-sm text-zinc-700"
          >
            {t.name}
          </span>
        ))
      ) : (
        <span className="text-bw-sm text-zinc-400">none</span>
      )}
    </div>
  );
}

// ─── Favorites ────────────────────────────────────────────────────

function FavoritesSection() {
  const router = useRouter();
  const [restaurants, setRestaurants] = useState<FavoriteRestaurant[] | null>(null);
  const [items, setItems] = useState<FavoriteDish[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchMyFavorites()
      .then((f) => {
        setRestaurants(f.restaurants);
        setItems(f.items);
      })
      .catch((e) => {
        if (e instanceof NotSignedInError) {
          router.replace(`/login?next=${encodeURIComponent('/profile/settings')}`);
          return;
        }
        setError((e as Error).message);
      });
  }, [router]);

  const empty = restaurants !== null && restaurants.length === 0 && items.length === 0;

  return (
    <section className="mt-bw-8 border-t border-zinc-100 pt-bw-8" data-testid="favorites">
      <h2 className="text-bw-lg font-bold text-zinc-900">Favorites</h2>
      {error ? (
        <p className="mt-bw-3 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
          Could not load your favorites — {error}
        </p>
      ) : restaurants === null ? (
        <p className="mt-bw-3 text-bw-sm text-zinc-500" data-testid="favorites-loading">
          Loading your favorites…
        </p>
      ) : empty ? (
        <p className="mt-bw-3 text-bw-sm text-zinc-400" data-testid="favorites-empty">
          You haven’t saved any restaurants or dishes yet.
        </p>
      ) : (
        <div className="mt-bw-4 space-y-bw-6">
          {restaurants.length > 0 && (
            <div data-testid="favorite-restaurants">
              <h3 className="text-bw-base font-semibold text-zinc-800">Restaurants</h3>
              <ul className="mt-bw-2 space-y-bw-2">
                {restaurants.map((r) => (
                  <li key={r.id} data-testid={`favorite-restaurant-${r.id}`}>
                    {r.status === 'published' ? (
                      <a
                        href={`/restaurants/${encodeURIComponent(r.slug)}`}
                        className="text-bw-base font-semibold text-zinc-900 hover:text-bite"
                      >
                        {r.name}
                      </a>
                    ) : (
                      <span className="text-bw-base font-semibold text-zinc-500">
                        {r.name} <span className="text-bw-xs">(unavailable)</span>
                      </span>
                    )}
                  </li>
                ))}
              </ul>
            </div>
          )}
          {items.length > 0 && (
            <div data-testid="favorite-dishes">
              <h3 className="text-bw-base font-semibold text-zinc-800">Dishes</h3>
              <ul className="mt-bw-2 space-y-bw-2">
                {items.map((d) => {
                  // Safe to link only when the dish AND its restaurant are
                  // published — the dish page 404s otherwise.
                  const linkable = d.status === 'published' && d.restaurant.status === 'published';
                  return (
                    <li key={d.id} data-testid={`favorite-dish-${d.id}`}>
                      {linkable ? (
                        <a
                          href={`/restaurants/${encodeURIComponent(d.restaurant.slug)}/items/${encodeURIComponent(d.id)}`}
                          className="text-bw-base font-semibold text-zinc-900 hover:text-bite"
                        >
                          {d.name}
                        </a>
                      ) : (
                        <span className="text-bw-base font-semibold text-zinc-500">
                          {d.name} <span className="text-bw-xs">(no longer available)</span>
                        </span>
                      )}
                      <span className="text-bw-sm text-zinc-500"> · {d.restaurant.name}</span>
                    </li>
                  );
                })}
              </ul>
            </div>
          )}
        </div>
      )}
    </section>
  );
}

// ─── My reviews ───────────────────────────────────────────────────

const MY_REVIEWS_PAGE = 20;

function MyReviewsSection() {
  const router = useRouter();
  const [reviews, setReviews] = useState<MyReview[] | null>(null);
  const [total, setTotal] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);

  const onError = (e: unknown) => {
    if (e instanceof NotSignedInError) {
      router.replace(`/login?next=${encodeURIComponent('/profile/settings')}`);
      return;
    }
    setError((e as Error).message);
  };

  useEffect(() => {
    fetchMyReviews({ limit: MY_REVIEWS_PAGE, offset: 0 })
      .then((r) => {
        setReviews(r.reviews);
        setTotal(r.total);
      })
      .catch(onError);
    // onError closes over `router` only; re-running on router change is fine.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [router]);

  // Offset pagination so a prolific reviewer isn't capped at the first page.
  const loadMore = async () => {
    if (!reviews) return;
    try {
      setLoadingMore(true);
      const r = await fetchMyReviews({ limit: MY_REVIEWS_PAGE, offset: reviews.length });
      setReviews((prev) => [...(prev ?? []), ...r.reviews]);
      setTotal(r.total);
    } catch (e) {
      onError(e);
    } finally {
      setLoadingMore(false);
    }
  };

  return (
    <section className="mt-bw-8 border-t border-zinc-100 pt-bw-8" data-testid="my-reviews">
      <h2 className="text-bw-lg font-bold text-zinc-900">
        My reviews{reviews && total > 0 ? ` (${total})` : ''}
      </h2>
      {error ? (
        <p className="mt-bw-3 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
          Could not load your reviews — {error}
        </p>
      ) : reviews === null ? (
        <p className="mt-bw-3 text-bw-sm text-zinc-500" data-testid="my-reviews-loading">
          Loading your reviews…
        </p>
      ) : reviews.length === 0 ? (
        <p className="mt-bw-3 text-bw-sm text-zinc-400" data-testid="my-reviews-empty">
          You haven’t written any reviews yet.
        </p>
      ) : (
        <>
          <ul className="mt-bw-4 space-y-bw-3">
            {reviews.map((r) => (
              <MyReviewRow key={r.id} review={r} />
            ))}
          </ul>
          {reviews.length < total && (
            <button
              type="button"
              onClick={loadMore}
              disabled={loadingMore}
              data-testid="my-reviews-load-more"
              className="mt-bw-4 w-full rounded-bw-md border border-zinc-200 py-bw-2 text-bw-sm font-semibold text-zinc-700 hover:border-zinc-300 disabled:opacity-50"
            >
              {loadingMore ? 'Loading…' : `Show more (${total - reviews.length})`}
            </button>
          )}
        </>
      )}
    </section>
  );
}

function MyReviewRow({ review }: { review: MyReview }) {
  const { item } = review;
  // The public item page is published-only, so only link a dish that
  // still resolves — otherwise the author lands on a 404 for their own
  // review. Encode both segments like every sibling link (slugs are
  // only presence/uniqueness-validated, not auto-parameterized).
  const linkable = item.status === 'published';
  const href = `/restaurants/${encodeURIComponent(item.restaurant.slug)}/items/${encodeURIComponent(item.id)}`;
  return (
    <li
      className="rounded-bw-md border border-zinc-200 p-bw-4"
      data-testid={`my-review-${review.id}`}
    >
      <div className="flex items-baseline justify-between gap-bw-3">
        {linkable ? (
          <a href={href} className="font-semibold text-zinc-900 hover:text-bite">
            {item.name}
          </a>
        ) : (
          <span className="font-semibold text-zinc-900">{item.name}</span>
        )}
        <span className="shrink-0 text-bw-sm" aria-label={`${review.rating} out of 5`}>
          <span className="text-warn">{'★'.repeat(review.rating)}</span>
          <span className="text-zinc-300">{'☆'.repeat(5 - review.rating)}</span>
        </span>
      </div>
      <p className="text-bw-sm text-zinc-500">{item.restaurant.name}</p>
      {review.body && <p className="mt-bw-2 text-bw-sm text-zinc-700">{review.body}</p>}
      {!linkable && (
        <p className="mt-bw-1 text-bw-xs text-zinc-400">This dish is no longer on the menu.</p>
      )}
      {review.hidden && (
        <p
          className="mt-bw-2 text-bw-xs font-semibold text-hide"
          data-testid={`my-review-hidden-${review.id}`}
        >
          Hidden by moderation{review.hidden_reason ? ` — ${review.hidden_reason}` : ''}
        </p>
      )}
    </li>
  );
}

/**
 * The OAuth grants this person approved, and the only supported way to
 * take one back.
 *
 * Approving used to be a one-way door: the API skips doorkeeper's own
 * management UI (it assumes a browser session this API does not have),
 * and while an access token expires in two hours the refresh chain behind
 * it never does. So "wait it out" was never a way to disconnect anything.
 *
 * Each row reads back the same sentences the consent screen showed, so
 * the decision to disconnect is made against the same words as the
 * decision to connect — not a list of scope slugs.
 */
function ConnectedAppsSection() {
  const [apps, setApps] = useState<ConnectedApp[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const load = async () => {
    try {
      setApps(await listConnectedApps());
    } catch (e) {
      setError((e as Error).message);
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const disconnect = async (app: ConnectedApp) => {
    setBusy(app.id);
    setError(null);
    try {
      await disconnectApp(app.id);
      await load();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(null);
    }
  };

  return (
    <section className="mt-bw-10" data-testid="connected-apps">
      <h2 className="text-bw-lg font-bold text-zinc-900">Connected apps</h2>
      <p className="mt-bw-1 text-bw-sm text-zinc-600">
        Apps you signed in to with your BiteWorthy account. Disconnecting one takes effect
        immediately — it stops working until you approve it again.
      </p>

      <ul className="mt-bw-4 flex flex-col gap-bw-2">
        {apps.map((app) => (
          <li
            key={app.id}
            className="flex items-start justify-between gap-bw-3 rounded-bw-md border border-zinc-200 px-bw-3 py-bw-2"
          >
            <span className="min-w-0">
              <span className="block truncate text-bw-sm font-medium text-zinc-900">
                {app.name}
              </span>
              {/* Anyone can register an app under any name, so the name
                  alone cannot tell two apart. The destination can — same
                  thing the consent screen showed before approving. */}
              {app.redirect_host ? (
                <span className="block truncate text-bw-xs text-zinc-500">
                  Sends you to {app.redirect_host}
                </span>
              ) : null}
              <ul className="mt-bw-1 flex flex-col gap-bw-1">
                {app.scope_details.map((detail) => (
                  <li key={detail.scope} className="text-bw-xs text-zinc-500">
                    {detail.description}
                  </li>
                ))}
              </ul>
              {app.connected_at ? (
                <span className="mt-bw-1 block text-bw-xs text-zinc-400">
                  Connected {new Date(app.connected_at).toLocaleDateString()}
                </span>
              ) : null}
            </span>
            <button
              type="button"
              onClick={() => void disconnect(app)}
              disabled={busy === app.id}
              className="shrink-0 text-bw-sm text-danger disabled:opacity-50"
            >
              Disconnect
            </button>
          </li>
        ))}
        {apps.length === 0 ? (
          <li className="text-bw-sm text-zinc-500">No apps connected yet.</li>
        ) : null}
      </ul>

      {error ? (
        <p
          role="alert"
          className="mt-bw-2 text-bw-sm text-danger"
          data-testid="connected-apps-error"
        >
          {error}
        </p>
      ) : null}
    </section>
  );
}

/**
 * Least-privilege credentials for MCP clients (Claude Code, Claude
 * Desktop).
 *
 * Without one, connecting a client means handing it the same session this
 * browser holds — everything the account can do. A token here names what
 * it may touch and can be revoked on its own.
 *
 * The secret is shown **once**, right after creation, because only its
 * digest is stored and nothing can reproduce it. The UI says so rather
 * than letting someone assume they can come back for it.
 */
function McpTokensSection() {
  const [tokens, setTokens] = useState<McpTokenSummary[]>([]);
  const [available, setAvailable] = useState<string[]>([]);
  const [name, setName] = useState('');
  const [chosen, setChosen] = useState<string[]>([]);
  const [fresh, setFresh] = useState<McpTokenWithSecret | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = async () => {
    try {
      const list = await listTokens();
      setTokens(list.tokens);
      setAvailable(list.scopes);
    } catch (e) {
      setError((e as Error).message);
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const create = async () => {
    setBusy(true);
    setError(null);
    try {
      setFresh(await createToken(name.trim(), chosen));
      setName('');
      setChosen([]);
      await load();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const revoke = async (id: string) => {
    try {
      await revokeToken(id);
      await load();
    } catch (e) {
      setError((e as Error).message);
    }
  };

  const toggle = (scope: string) =>
    setChosen((current) =>
      current.includes(scope) ? current.filter((s) => s !== scope) : [...current, scope],
    );

  return (
    <section className="mt-bw-10" data-testid="mcp-tokens">
      <h2 className="text-bw-lg font-bold text-zinc-900">Access tokens</h2>
      <p className="mt-bw-1 text-bw-sm text-zinc-600">
        Tokens you paste into Claude Code or Claude Desktop yourself. Pick only what the app needs —
        leave everything unticked and it gets the same access you have.
      </p>

      {fresh ? (
        <div
          className="mt-bw-4 rounded-bw-md border border-warn bg-warn/10 p-bw-3"
          data-testid="fresh-token"
        >
          <p className="text-bw-sm font-medium text-zinc-900">
            Copy this now — it is not stored and cannot be shown again.
          </p>
          <code className="mt-bw-2 block overflow-x-auto text-bw-xs text-zinc-800">
            {fresh.secret}
          </code>
        </div>
      ) : null}

      <ul className="mt-bw-4 flex flex-col gap-bw-2">
        {tokens.map((token) => (
          <li
            key={token.id}
            className="flex items-center justify-between rounded-bw-md border border-zinc-200 px-bw-3 py-bw-2"
          >
            <span className="min-w-0">
              <span className="block truncate text-bw-sm font-medium text-zinc-900">
                {token.name}
              </span>
              <span className="block truncate text-bw-xs text-zinc-500">
                {token.scopes.length ? token.scopes.join(', ') : 'full access'}
                {token.last_used_at ? ' · used' : ' · never used'}
              </span>
            </span>
            <button
              type="button"
              onClick={() => void revoke(token.id)}
              className="text-bw-sm text-danger"
            >
              Revoke
            </button>
          </li>
        ))}
        {tokens.length === 0 ? (
          <li className="text-bw-sm text-zinc-500">No connected apps yet.</li>
        ) : null}
      </ul>

      <div className="mt-bw-4 flex flex-col gap-bw-2">
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="What is it for? e.g. Claude Code"
          aria-label="Token name"
          className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-sm"
        />
        <div className="flex flex-wrap gap-bw-1">
          {available.map((scope) => (
            <button
              key={scope}
              type="button"
              onClick={() => toggle(scope)}
              aria-pressed={chosen.includes(scope)}
              className={`rounded-bw-md border px-bw-2 py-bw-1 text-bw-xs ${
                chosen.includes(scope)
                  ? 'border-bite bg-bite/10 text-bite-dark'
                  : 'border-zinc-300 text-zinc-600'
              }`}
            >
              {scope}
            </button>
          ))}
        </div>
        <button
          type="button"
          onClick={() => void create()}
          disabled={busy || name.trim() === ''}
          className="self-start rounded-bw-md bg-bite px-bw-4 py-bw-2 text-bw-sm font-bold text-white disabled:opacity-50"
        >
          Create token
        </button>
      </div>

      {error ? (
        <p role="alert" className="mt-bw-2 text-bw-sm text-danger" data-testid="mcp-tokens-error">
          {error}
        </p>
      ) : null}
    </section>
  );
}

// ─── Analytics opt-out (legal remediation E7a — pre-existing) ──────

/**
 * Legal remediation E7a — the analytics opt-out the Privacy Policy
 * promises ("turn them off with the toggle in /profile/settings").
 *
 * Web analytics are on by default (the wrapper also honors the
 * browser's Do-Not-Track). This toggle writes the same
 * `localStorage.bw_analytics_opt_out` flag that `buildWebTracker`
 * reads, so flipping it off makes the tracker a no-op on the next
 * load. We never send the dietary profile on analytics events
 * regardless (see packages/analytics — profile_set carries no health
 * fields).
 */
function AnalyticsSection() {
  // null until we've read localStorage (avoids an SSR/client mismatch).
  const [optedOut, setOptedOut] = useState<boolean | null>(null);

  useEffect(() => {
    try {
      setOptedOut(localStorage.getItem(OPT_OUT_KEY) === '1');
    } catch {
      setOptedOut(false);
    }
  }, []);

  const setOptOut = (next: boolean) => {
    try {
      if (next) localStorage.setItem(OPT_OUT_KEY, '1');
      else localStorage.removeItem(OPT_OUT_KEY);
    } catch {
      // localStorage unavailable (private mode) — nothing to persist.
    }
    setOptedOut(next);
  };

  const analyticsOn = optedOut === false;

  return (
    <section className="mt-bw-8 border-t border-zinc-100 pt-bw-8">
      <h2 className="text-bw-lg font-bold text-zinc-900">Product analytics</h2>
      <p className="mt-bw-2 text-bw-sm text-zinc-600">
        We use privacy-respecting product analytics to understand the launch funnel. Events are
        never tied to your dietary profile — we don’t send what you avoid, your presets, or your
        strictness. We also honor your browser’s Do-Not-Track signal automatically.
      </p>

      <label className="mt-bw-4 flex items-center justify-between rounded-bw-md border border-zinc-200 p-bw-4">
        <span className="text-bw-base font-semibold text-zinc-800">
          Allow anonymous product analytics
        </span>
        <input
          type="checkbox"
          role="switch"
          aria-label="analytics-opt-in"
          disabled={optedOut === null}
          checked={analyticsOn}
          onChange={(e) => setOptOut(!e.target.checked)}
          className="h-5 w-5"
        />
      </label>

      <p className="mt-bw-2 text-bw-xs text-zinc-500" data-testid="analytics-state">
        {optedOut === null
          ? 'Loading…'
          : analyticsOn
            ? 'Analytics are on. Turning this off takes effect on your next page load.'
            : 'Analytics are off. You’ve opted out on this device.'}
      </p>
    </section>
  );
}
