'use client';

import { Suspense, useEffect, useReducer, useState, type FormEvent } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import {
  initialDraft,
  onboardingReducer,
  tasteStateOf,
  toProfilePayload,
  toTastePayload,
  type DietaryPreset,
  type DraftProfile,
  type Strictness,
  type TasteState,
} from '@biteworthy/filter-engine';
import {
  fetchDietaryProfiles,
  fetchTags,
  saveProfile,
  saveTaste,
  searchIngredients,
  type IngredientSearchResult,
  type TasteTag,
} from '../../lib/onboarding';
import { useTracker } from '../_PostHogProvider';

/**
 * Phase 3.8 + 4.1 — web mirror of the mobile 4-step onboarding flow.
 *
 *   1. Pick presets ("What can't you eat?")
 *   2. Add specific ingredients ("Anything else?")
 *   3. Set strictness ("How strict?")
 *   4. Taste ("What do you love?") — Phase 8.5, skippable
 *   5. Done → PATCH /api/profile (Next proxy reads the bw_session
 *      cookie + forwards to Rails), navigate home.
 *
 * Phase 4.1 dropped the paste-the-JWT input; if the request comes
 * back 401, the user is bounced to /login?next=/onboarding so they
 * can sign in and resume.
 *
 * Phase 8.5 — `?step=taste` enters the taste step standalone ("Improve
 * my picks"). That mode saves ONLY the taste arrays (toTastePayload),
 * so refining picks can never wipe the avoid lists. Taste is soft:
 * safety filters, taste ranks.
 */
type Step = 'presets' | 'ingredients' | 'strictness' | 'taste' | 'done';

const STRICTNESSES: Strictness[] = ['relaxed', 'balanced', 'strict'];
const STRICTNESS_BLURB: Record<Strictness, string> = {
  relaxed: 'Show items even if some ingredients are inferred.',
  balanced: 'Hide items where the avoid match is confident.',
  strict: 'Also hide items the AI marked suggested or inferred.',
};

// Persist the in-progress draft so an anonymous user who fills out the flow,
// hits "Done", and gets bounced through sign-up (the 401 → /login redirect in
// `finalize`) comes back to their selections instead of a blank form.
// sessionStorage: scoped to the tab session (survives the client-side redirect,
// gone when the tab closes — no stale health-adjacent draft left behind).
const DRAFT_KEY = 'bw_onboarding_draft';

function loadDraft(): DraftProfile | null {
  if (typeof window === 'undefined') return null;
  try {
    const raw = window.sessionStorage.getItem(DRAFT_KEY);
    return raw ? (JSON.parse(raw) as DraftProfile) : null;
  } catch {
    return null;
  }
}

function saveDraft(draft: DraftProfile): void {
  try {
    window.sessionStorage.setItem(DRAFT_KEY, JSON.stringify(draft));
  } catch {
    // Private mode / quota — persistence is best-effort, never fatal.
  }
}

function clearDraft(): void {
  try {
    window.sessionStorage.removeItem(DRAFT_KEY);
  } catch {
    // no-op
  }
}

export default function OnboardingPage() {
  // useSearchParams (in OnboardingFlow) needs a Suspense boundary or
  // Next 15's prod build bails the whole page out of static rendering.
  return (
    <Suspense>
      <OnboardingFlow />
    </Suspense>
  );
}

function OnboardingFlow() {
  const router = useRouter();
  const tracker = useTracker();
  const searchParams = useSearchParams();
  const standalone = searchParams.get('step') === 'taste';

  const [step, setStep] = useState<Step>(standalone ? 'taste' : 'presets');
  const [draft, dispatch] = useReducer(onboardingReducer, initialDraft);
  const [presets, setPresets] = useState<DietaryPreset[]>([]);
  const [presetsError, setPresetsError] = useState<string | null>(null);
  const [loadingPresets, setLoadingPresets] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<IngredientSearchResult[]>([]);
  const [tags, setTags] = useState<TasteTag[]>([]);
  const [tasteQuery, setTasteQuery] = useState('');
  const [tasteResults, setTasteResults] = useState<IngredientSearchResult[]>([]);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [hydrated, setHydrated] = useState(false);

  // Restore a persisted draft once, after mount. A lazy useReducer initializer
  // would read sessionStorage during render and mismatch the SSR HTML, so
  // hydrate post-mount instead. Skipped in standalone taste mode so an old
  // full-onboarding draft can't leak into "Improve my picks".
  useEffect(() => {
    if (!standalone) {
      const saved = loadDraft();
      if (saved) dispatch({ type: 'HYDRATE', draft: saved });
    }
    setHydrated(true);
  }, [standalone]);

  // Persist on change, but only after hydration so the empty initialDraft on
  // the first render can't clobber a saved draft.
  useEffect(() => {
    if (hydrated && !standalone) saveDraft(draft);
  }, [draft, hydrated, standalone]);

  useEffect(() => {
    fetchDietaryProfiles()
      .then(setPresets)
      .catch((e) => setPresetsError((e as Error).message))
      .finally(() => setLoadingPresets(false));
  }, []);

  // Load taste tag chips once (cuisine + flavor families).
  useEffect(() => {
    fetchTags()
      .then(setTags)
      .catch(() => {
        // Tags are optional — taste is skippable, so a load failure
        // just leaves the chip grid empty.
      });
  }, []);

  // Debounced ingredient search (avoid-list step).
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

  // Debounced ingredient search (taste step — separate query so the
  // two searches don't bleed into each other).
  useEffect(() => {
    if (step !== 'taste' || tasteQuery.trim().length === 0) {
      setTasteResults([]);
      return;
    }
    const handle = setTimeout(() => {
      searchIngredients(tasteQuery)
        .then(setTasteResults)
        .catch(() => {
          // Non-fatal.
        });
    }, 250);
    return () => clearTimeout(handle);
  }, [tasteQuery, step]);

  const tasteSignalCount =
    draft.likedTagIds.length +
    draft.dislikedTagIds.length +
    draft.likedIngredientIds.length +
    draft.dislikedIngredientIds.length;

  const finalize = async (e: FormEvent) => {
    e.preventDefault();
    try {
      setSaving(true);
      setSaveError(null);
      const payload = toProfilePayload(draft, presets);
      // Legal remediation E1 — the review step gates this submit behind
      // the allergen-disclaimer checkbox, so record the acknowledgment.
      await saveProfile({ ...payload, acknowledge_disclaimer: true });
      clearDraft();
      // Legal remediation E7 — funnel conversion only; the dietary
      // profile (preset/strictness/avoid sizes) is health data and is
      // never attached to this identified event.
      tracker.track('profile_set', {
        taste_signal_count: tasteSignalCount,
      });
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

  // Standalone "Improve my picks" save — taste arrays only, so it can
  // never wipe the user's existing avoid lists (wholesale-replace
  // semantics on the endpoint).
  const finalizeTaste = async () => {
    try {
      setSaving(true);
      setSaveError(null);
      await saveTaste(toTastePayload(draft));
      router.replace('/');
    } catch (err) {
      const message = (err as Error).message;
      if (message.includes('401')) {
        router.replace(`/login?next=${encodeURIComponent('/onboarding?step=taste')}`);
        return;
      }
      setSaveError(message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <main className="mx-auto max-w-2xl px-bw-6 py-bw-12">
      {/* Persistent escape hatch — without it the only way out of the
          multi-step flow was to complete it (or edit the URL). Standalone
          "Improve my picks" already has its own Cancel on the taste step. */}
      {!standalone && (
        <div className="mb-bw-6 flex justify-end">
          <button
            type="button"
            onClick={() => {
              clearDraft();
              router.replace('/');
            }}
            data-testid="onboarding-exit"
            className="text-bw-sm font-semibold text-zinc-500 hover:text-zinc-800"
          >
            Exit
          </button>
        </div>
      )}

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
          onNext={() => setStep('taste')}
        />
      )}

      {step === 'taste' && (
        <TasteStep
          standalone={standalone}
          tags={tags}
          likedTagIds={draft.likedTagIds}
          dislikedTagIds={draft.dislikedTagIds}
          onCycleTag={(tagId) => dispatch({ type: 'CYCLE_TASTE_TAG', tagId })}
          query={tasteQuery}
          results={tasteResults}
          likedIngredientIds={draft.likedIngredientIds}
          dislikedIngredientIds={draft.dislikedIngredientIds}
          onQueryChange={setTasteQuery}
          onCycleIngredient={(ingredientId) =>
            dispatch({ type: 'CYCLE_TASTE_INGREDIENT', ingredientId })
          }
          signalCount={tasteSignalCount}
          saving={saving}
          error={saveError}
          onNext={() => setStep('done')}
          onSave={finalizeTaste}
          onSkip={() => (standalone ? router.replace('/') : setStep('done'))}
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
        Step {step} of 5
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
      <NextButton label="Next →" onClick={onNext} testId="next-to-taste" />
    </>
  );
}

// ─── Phase 8.5 — taste step ("What do you love?") ─────────────────

function TasteChip({
  label,
  state,
  onClick,
  testId,
}: {
  label: string;
  state: TasteState;
  onClick: () => void;
  testId: string;
}) {
  const tone =
    state === 'liked'
      ? 'border-ok bg-bite-light text-ok'
      : state === 'disliked'
        ? 'border-bite bg-bite-light text-bite-dark line-through'
        : 'border-zinc-200 bg-white text-zinc-700 hover:border-zinc-300';
  const prefix = state === 'liked' ? '♥ ' : state === 'disliked' ? '✕ ' : '';
  return (
    <button
      type="button"
      data-testid={testId}
      data-state={state}
      aria-pressed={state !== 'neutral'}
      onClick={onClick}
      className={['rounded-full border px-bw-3 py-bw-2 text-bw-sm font-semibold transition', tone].join(
        ' ',
      )}
    >
      {prefix}
      {label}
    </button>
  );
}

function TasteStep({
  standalone,
  tags,
  likedTagIds,
  dislikedTagIds,
  onCycleTag,
  query,
  results,
  likedIngredientIds,
  dislikedIngredientIds,
  onQueryChange,
  onCycleIngredient,
  signalCount,
  saving,
  error,
  onNext,
  onSave,
  onSkip,
}: {
  standalone: boolean;
  tags: TasteTag[];
  likedTagIds: string[];
  dislikedTagIds: string[];
  onCycleTag: (tagId: string) => void;
  query: string;
  results: IngredientSearchResult[];
  likedIngredientIds: string[];
  dislikedIngredientIds: string[];
  onQueryChange: (q: string) => void;
  onCycleIngredient: (ingredientId: string) => void;
  signalCount: number;
  saving: boolean;
  error: string | null;
  onNext: () => void;
  onSave: () => void;
  onSkip: () => void;
}) {
  return (
    <>
      {standalone ? (
        <>
          <p className="text-bite text-bw-sm font-semibold uppercase tracking-wider">
            Improve your picks
          </p>
          <h1 className="mt-bw-2 text-bw-2xl font-bold">What do you love?</h1>
          <p className="mt-bw-2 text-bw-base text-zinc-700">
            Tap to love a cuisine or flavor; tap again to pass. This only ranks your menus —
            it never hides anything your dietary filter allows.
          </p>
        </>
      ) : (
        <StepHeader
          step={4}
          title="What do you love?"
          body="Tap to love a cuisine or flavor; tap again to pass. Optional — this only ranks your Top Picks, it never hides safe food."
        />
      )}

      {tags.length > 0 && (
        <div className="mt-bw-4 flex flex-wrap gap-bw-2" data-testid="taste-tags">
          {tags.map((t) => (
            <TasteChip
              key={t.id}
              label={t.name}
              state={tasteStateOf(t.id, likedTagIds, dislikedTagIds)}
              onClick={() => onCycleTag(t.id)}
              testId={`taste-tag-${t.slug}`}
            />
          ))}
        </div>
      )}

      <input
        type="search"
        value={query}
        onChange={(e) => onQueryChange(e.target.value)}
        placeholder="Search a favorite ingredient (e.g. 'basil')"
        aria-label="taste-ingredient-search"
        className="mt-bw-4 w-full rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-base"
      />
      <ul className="mt-bw-2 divide-y divide-zinc-100">
        {results.map((r) => {
          const state = tasteStateOf(r.id, likedIngredientIds, dislikedIngredientIds);
          return (
            <li key={r.id}>
              <button
                type="button"
                onClick={() => onCycleIngredient(r.id)}
                data-testid={`taste-ing-${r.slug}`}
                data-state={state}
                className="flex w-full items-center justify-between py-bw-3 text-left"
              >
                <span className="text-bw-base text-zinc-900">{r.name}</span>
                <span
                  className={[
                    'font-semibold',
                    state === 'liked'
                      ? 'text-ok'
                      : state === 'disliked'
                        ? 'text-bite'
                        : 'text-zinc-400',
                  ].join(' ')}
                >
                  {state === 'liked' ? '♥ love' : state === 'disliked' ? '✕ pass' : '+ love'}
                </span>
              </button>
            </li>
          );
        })}
      </ul>

      <p className="mt-bw-3 text-bw-sm text-zinc-500">{signalCount} taste signal(s) set</p>

      {error && (
        <p className="mt-bw-3 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
          {error}
        </p>
      )}

      {standalone ? (
        <button
          type="button"
          onClick={onSave}
          disabled={saving}
          data-testid="save-taste"
          className={[
            'mt-bw-6 w-full rounded-bw-md bg-bite px-bw-4 py-bw-3 font-bold text-white',
            saving ? 'opacity-60' : 'hover:bg-bite-dark',
          ].join(' ')}
        >
          {saving ? 'Saving…' : 'Save picks'}
        </button>
      ) : (
        <NextButton label="Review →" onClick={onNext} testId="next-to-done" />
      )}

      <button
        type="button"
        onClick={onSkip}
        data-testid="skip-taste"
        className="mt-bw-3 w-full text-bw-sm font-semibold text-zinc-500 hover:text-zinc-700"
      >
        {standalone ? 'Cancel' : 'Skip for now'}
      </button>
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
  // Legal remediation E1 — the user must accept the allergen disclaimer
  // before the profile saves; the acceptance is recorded server-side.
  const [acknowledged, setAcknowledged] = useState(false);
  return (
    <form onSubmit={onSubmit}>
      <StepHeader step={5} title="Ready?" body="Saving will replace any existing avoid lists on your profile." />

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

      <label className="mt-bw-6 flex items-start gap-bw-3 rounded-bw-md border border-warn/40 bg-warn/10 p-bw-3 text-bw-sm text-zinc-800">
        <input
          type="checkbox"
          checked={acknowledged}
          onChange={(e) => setAcknowledged(e.target.checked)}
          data-testid="acknowledge-disclaimer"
          className="mt-bw-1 h-4 w-4 shrink-0"
        />
        <span>
          I understand BiteWorthy is a planning tool, not a guarantee — results can miss an
          allergen, and I’ll confirm with the restaurant before ordering for a serious allergy.
        </span>
      </label>

      {error && (
        <p className="mt-bw-3 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
          {error}
        </p>
      )}

      <button
        type="submit"
        disabled={saving || !acknowledged}
        data-testid="finish"
        className={[
          'mt-bw-6 w-full rounded-bw-md bg-bite px-bw-4 py-bw-3 font-bold text-white',
          saving || !acknowledged ? 'opacity-60' : 'hover:bg-bite-dark',
        ].join(' ')}
      >
        {saving ? 'Saving…' : 'Save profile'}
      </button>
    </form>
  );
}
