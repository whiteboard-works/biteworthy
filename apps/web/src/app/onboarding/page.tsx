'use client';

import { useEffect, useReducer, useState, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import {
  initialDraft,
  onboardingReducer,
  toProfilePayload,
  type DietaryPreset,
  type Strictness,
} from '@biteworthy/filter-engine';
import {
  fetchDietaryProfiles,
  saveProfile,
  searchIngredients,
  type IngredientSearchResult,
} from '../../lib/onboarding';

/**
 * Phase 3.8 + 4.1 — web mirror of the mobile 4-step onboarding flow.
 *
 *   1. Pick presets ("What can't you eat?")
 *   2. Add specific ingredients ("Anything else?")
 *   3. Set strictness ("How strict?")
 *   4. Done → PATCH /api/profile (Next proxy reads the bw_session
 *      cookie + forwards to Rails), navigate home.
 *
 * Phase 4.1 dropped the paste-the-JWT input; if the request comes
 * back 401, the user is bounced to /login?next=/onboarding so they
 * can sign in and resume.
 */
type Step = 'presets' | 'ingredients' | 'strictness' | 'done';

const STRICTNESSES: Strictness[] = ['relaxed', 'balanced', 'strict'];
const STRICTNESS_BLURB: Record<Strictness, string> = {
  relaxed: 'Show items even if some ingredients are inferred.',
  balanced: 'Hide items where the avoid match is confident.',
  strict: 'Also hide items the AI marked suggested or inferred.',
};

export default function OnboardingPage() {
  const router = useRouter();

  const [step, setStep] = useState<Step>('presets');
  const [draft, dispatch] = useReducer(onboardingReducer, initialDraft);
  const [presets, setPresets] = useState<DietaryPreset[]>([]);
  const [presetsError, setPresetsError] = useState<string | null>(null);
  const [loadingPresets, setLoadingPresets] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<IngredientSearchResult[]>([]);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  useEffect(() => {
    fetchDietaryProfiles()
      .then(setPresets)
      .catch((e) => setPresetsError((e as Error).message))
      .finally(() => setLoadingPresets(false));
  }, []);

  // Debounced ingredient search.
  useEffect(() => {
    if (step !== 'ingredients') return;
    const handle = setTimeout(() => {
      searchIngredients(searchQuery)
        .then(setSearchResults)
        .catch(() => {
          // Search errors are non-fatal — silently no-op.
        });
    }, 250);
    return () => clearTimeout(handle);
  }, [searchQuery, step]);

  const finalize = async (e: FormEvent) => {
    e.preventDefault();
    try {
      setSaving(true);
      setSaveError(null);
      await saveProfile(toProfilePayload(draft, presets));
      router.replace('/');
    } catch (err) {
      const message = (err as Error).message;
      // 401 from the proxy means the cookie expired or never existed
      // — bounce to login and come back here to finish.
      if (message.includes('401')) {
        router.replace(`/login?next=${encodeURIComponent('/onboarding')}`);
        return;
      }
      setSaveError(message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <main className="mx-auto max-w-2xl px-bw-6 py-bw-12">
      {step === 'presets' && (
        <PresetsStep
          presets={presets}
          loading={loadingPresets}
          error={presetsError}
          selectedSlugs={draft.selectedPresetSlugs}
          onToggle={(slug) => dispatch({ type: 'TOGGLE_PRESET', slug })}
          onNext={() => setStep('ingredients')}
        />
      )}

      {step === 'ingredients' && (
        <IngredientsStep
          query={searchQuery}
          results={searchResults}
          addedIds={draft.manualIngredientIds}
          onQueryChange={setSearchQuery}
          onToggle={(id, added) =>
            dispatch({
              type: added ? 'REMOVE_MANUAL_INGREDIENT' : 'ADD_MANUAL_INGREDIENT',
              ingredientId: id,
            })
          }
          onNext={() => setStep('strictness')}
        />
      )}

      {step === 'strictness' && (
        <StrictnessStep
          active={draft.strictness}
          onPick={(s) => dispatch({ type: 'SET_STRICTNESS', strictness: s })}
          onNext={() => setStep('done')}
        />
      )}

      {step === 'done' && (
        <ReviewStep
          presetCount={draft.selectedPresetSlugs.length}
          ingredientCount={draft.manualIngredientIds.length}
          strictness={draft.strictness}
          saving={saving}
          error={saveError}
          onSubmit={finalize}
        />
      )}
    </main>
  );
}

// ─── Step components ──────────────────────────────────────────────

function StepHeader({
  step,
  title,
  body,
}: {
  step: number;
  title: string;
  body: string;
}) {
  return (
    <>
      <p className="text-bite text-bw-sm font-semibold uppercase tracking-wider">
        Step {step} of 4
      </p>
      <h1 className="mt-bw-2 text-bw-2xl font-bold">{title}</h1>
      <p className="mt-bw-2 text-bw-base text-zinc-700">{body}</p>
    </>
  );
}

function NextButton({
  label,
  onClick,
  testId,
}: {
  label: string;
  onClick: () => void;
  testId: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      data-testid={testId}
      className="mt-bw-6 w-full rounded-bw-md bg-bite px-bw-4 py-bw-3 font-bold text-white hover:bg-bite-dark"
    >
      {label}
    </button>
  );
}

function PresetsStep({
  presets,
  loading,
  error,
  selectedSlugs,
  onToggle,
  onNext,
}: {
  presets: DietaryPreset[];
  loading: boolean;
  error: string | null;
  selectedSlugs: string[];
  onToggle: (slug: string) => void;
  onNext: () => void;
}) {
  return (
    <>
      <StepHeader step={1} title="What can't you eat?" body="Tap any presets that apply. You can multi-select." />
      {error && (
        <p className="mt-bw-3 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
          Could not load presets — {error}
        </p>
      )}
      {loading ? (
        <p className="mt-bw-6 text-bw-sm text-zinc-500" data-testid="presets-loading">
          Loading presets…
        </p>
      ) : (
        <div className="mt-bw-4 grid grid-cols-1 gap-bw-2 sm:grid-cols-2">
          {presets.map((p) => {
            const selected = selectedSlugs.includes(p.slug);
            return (
              <button
                key={p.slug}
                type="button"
                aria-pressed={selected}
                data-testid={`preset-${p.slug}`}
                onClick={() => onToggle(p.slug)}
                className={[
                  'rounded-bw-md border p-bw-3 text-left transition',
                  selected
                    ? 'border-bite bg-bite-light'
                    : 'border-zinc-200 bg-white hover:border-zinc-300',
                ].join(' ')}
              >
                <p className={['font-bold', selected ? 'text-bite-dark' : 'text-zinc-900'].join(' ')}>
                  {p.name}
                </p>
                <p
                  className={[
                    'mt-1 text-bw-sm',
                    selected ? 'text-bite-dark' : 'text-zinc-500',
                  ].join(' ')}
                >
                  {p.description}
                </p>
              </button>
            );
          })}
        </div>
      )}
      <NextButton label="Next →" onClick={onNext} testId="next-to-ingredients" />
    </>
  );
}

function IngredientsStep({
  query,
  results,
  addedIds,
  onQueryChange,
  onToggle,
  onNext,
}: {
  query: string;
  results: IngredientSearchResult[];
  addedIds: string[];
  onQueryChange: (q: string) => void;
  onToggle: (id: string, isAlreadyAdded: boolean) => void;
  onNext: () => void;
}) {
  return (
    <>
      <StepHeader step={2} title="Anything else?" body="Search for specific ingredients to avoid." />
      <input
        type="search"
        value={query}
        onChange={(e) => onQueryChange(e.target.value)}
        placeholder="Search ingredients (e.g. 'cilantro')"
        aria-label="ingredient-search"
        className="mt-bw-4 w-full rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-base"
      />
      <ul className="mt-bw-3 divide-y divide-zinc-100">
        {results.map((r) => {
          const added = addedIds.includes(r.id);
          return (
            <li key={r.id}>
              <button
                type="button"
                onClick={() => onToggle(r.id, added)}
                data-testid={`add-${r.slug}`}
                className={[
                  'flex w-full items-center justify-between py-bw-3 text-left',
                  added ? 'bg-bite-light px-bw-3' : '',
                ].join(' ')}
              >
                <span>
                  <span className="block text-bw-base text-zinc-900">{r.name}</span>
                  {r.aliases.length > 0 && (
                    <span className="block text-bw-xs text-zinc-500">
                      aka {r.aliases.join(', ')}
                    </span>
                  )}
                </span>
                <span className={['font-semibold', added ? 'text-ok' : 'text-bite'].join(' ')}>
                  {added ? '✓ added' : '+ add'}
                </span>
              </button>
            </li>
          );
        })}
        {results.length === 0 && (
          <li className="py-bw-6 text-center text-bw-sm text-zinc-500">
            {query ? 'No matches — try a different word.' : 'Type to search the ingredient catalog.'}
          </li>
        )}
      </ul>
      <p className="mt-bw-3 text-bw-sm text-zinc-500">{addedIds.length} added manually</p>
      <NextButton label="Next →" onClick={onNext} testId="next-to-strictness" />
    </>
  );
}

function StrictnessStep({
  active,
  onPick,
  onNext,
}: {
  active: Strictness;
  onPick: (s: Strictness) => void;
  onNext: () => void;
}) {
  return (
    <>
      <StepHeader
        step={3}
        title="How strict?"
        body="Strict mode also hides items the AI hasn't fully confirmed. Pick balanced if unsure."
      />
      <div className="mt-bw-4 flex flex-col gap-bw-2">
        {STRICTNESSES.map((s) => {
          const selected = active === s;
          return (
            <button
              key={s}
              type="button"
              data-testid={`strictness-${s}`}
              aria-pressed={selected}
              onClick={() => onPick(s)}
              className={[
                'rounded-bw-md border p-bw-3 text-left transition',
                selected ? 'border-bite bg-bite-light' : 'border-zinc-200 bg-white hover:border-zinc-300',
              ].join(' ')}
            >
              <p className={['font-bold', selected ? 'text-bite-dark' : 'text-zinc-900'].join(' ')}>
                {s.charAt(0).toUpperCase() + s.slice(1)}
              </p>
              <p
                className={['mt-1 text-bw-sm', selected ? 'text-bite-dark' : 'text-zinc-500'].join(' ')}
              >
                {STRICTNESS_BLURB[s]}
              </p>
            </button>
          );
        })}
      </div>
      <NextButton label="Review →" onClick={onNext} testId="next-to-done" />
    </>
  );
}

function ReviewStep({
  presetCount,
  ingredientCount,
  strictness,
  saving,
  error,
  onSubmit,
}: {
  presetCount: number;
  ingredientCount: number;
  strictness: Strictness;
  saving: boolean;
  error: string | null;
  onSubmit: (e: FormEvent) => void;
}) {
  return (
    <form onSubmit={onSubmit}>
      <StepHeader step={4} title="Ready?" body="Saving will replace any existing avoid lists on your profile." />

      <p className="mt-bw-4 text-bw-base text-zinc-700">
        Avoiding{' '}
        <span className="font-bold">
          {presetCount} preset{presetCount === 1 ? '' : 's'}
        </span>{' '}
        +{' '}
        <span className="font-bold">
          {ingredientCount} ingredient{ingredientCount === 1 ? '' : 's'}
        </span>
        , strictness <span className="font-bold">{strictness}</span>.
      </p>

      {error && (
        <p className="mt-bw-3 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
          {error}
        </p>
      )}

      <button
        type="submit"
        disabled={saving}
        data-testid="finish"
        className={[
          'mt-bw-6 w-full rounded-bw-md bg-bite px-bw-4 py-bw-3 font-bold text-white',
          saving ? 'opacity-60' : 'hover:bg-bite-dark',
        ].join(' ')}
      >
        {saving ? 'Saving…' : 'Save profile'}
      </button>
    </form>
  );
}
