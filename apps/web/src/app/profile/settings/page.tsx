'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import type { DietaryPreset, Strictness } from '@biteworthy/filter-engine';
import { OPT_OUT_KEY } from '../../../lib/track';
import {
  fetchProfile,
  updateProfile,
  NotSignedInError,
  type ProfilePatch,
  type ProfilePayload,
} from '../../../lib/profile';
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

      <TasteSubsection liked={profile.liked_tags} disliked={profile.disliked_tags} />

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
      <SubsectionHeader title="Strictness" hint="How aggressively we hide items we're unsure about." />
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
                selected ? 'border-bite bg-bite-light' : 'border-zinc-200 bg-white hover:border-zinc-300',
              ].join(' ')}
            >
              <p className={['font-bold', selected ? 'text-bite-dark' : 'text-zinc-900'].join(' ')}>
                {s.charAt(0).toUpperCase() + s.slice(1)}
              </p>
              <p className={['mt-1 text-bw-sm', selected ? 'text-bite-dark' : 'text-zinc-500'].join(' ')}>
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
  liked,
  disliked,
}: {
  liked: ProfilePayload['liked_tags'];
  disliked: ProfilePayload['disliked_tags'];
}) {
  return (
    <div className="mt-bw-6" data-testid="pref-taste">
      <SubsectionHeader
        title="Taste"
        hint="Soft signals that rank your Top Picks — they never hide safe food."
      />
      <div className="mt-bw-3 space-y-bw-2">
        <TasteRow label="Love" tone="text-ok" items={liked} />
        <TasteRow label="Pass" tone="text-bite" items={disliked} />
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
  items: ProfilePayload['liked_tags'];
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
